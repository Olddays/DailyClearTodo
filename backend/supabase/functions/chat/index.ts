import { createClient } from "npm:@supabase/supabase-js@2";
import { serviceClient, getLocalToday } from "./db.ts";
import { TOOL_DEFS, dispatchTool } from "./tools.ts";
import { SYSTEM_PROMPT } from "./system_prompt.ts";

// Zhipu (智谱) BigModel -- OpenAI-compatible /chat/completions endpoint. Verified
// directly against the live API (not just docs): request/response shapes below
// (tool_calls array with function.name/function.arguments as a JSON string,
// tool results sent back as {role:"tool", tool_call_id, content}) match exactly.
const ZHIPU_BASE_URL = "https://open.bigmodel.cn/api/paas/v4";
const ZHIPU_API_KEY = Deno.env.get("ZHIPU_API_KEY")!;
const MODEL_ID = Deno.env.get("CHAT_MODEL_ID") ?? "glm-4-flash";
const MAX_TOOL_ITERATIONS = 8;
const HISTORY_TURN_LIMIT = 40; // recent chat_messages rows to replay as context

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ZhipuToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

interface ZhipuMessage {
  role: string;
  content?: string | null;
  tool_calls?: ZhipuToolCall[];
  tool_call_id?: string;
}

async function callZhipu(messages: ZhipuMessage[]): Promise<ZhipuMessage> {
  const res = await fetch(`${ZHIPU_BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${ZHIPU_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: MODEL_ID, messages, tools: TOOL_DEFS }),
  });
  if (!res.ok) {
    throw new Error(`zhipu_api_error ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  const choice = data.choices?.[0];
  if (!choice) throw new Error(`zhipu_api_error: no choices in response ${JSON.stringify(data)}`);
  return choice.message as ZhipuMessage;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) {
    return new Response(JSON.stringify({ error: "missing_authorization" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // Verify the JWT and recover the user id -- this is the ONLY source of truth
  // for "who is this request from"; tool-call input is never trusted for identity.
  const authClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: userData, error: userErr } = await authClient.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
  const userId = userData.user.id;

  let body: { message?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
  const message = (body.message ?? "").trim();
  if (!message) {
    return new Response(JSON.stringify({ error: "empty_message" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const db = serviceClient();

  // Stored as an Anthropic-style content-block array for forward compatibility
  // with the Flutter client's ChatMessage.text parser (looks for {type:"text"}
  // blocks) -- keeps the client provider-agnostic even though the model behind
  // this function has changed.
  const toBlocks = (text: string) => [{ type: "text", text }];

  await db.from("chat_messages").insert({
    user_id: userId,
    role: "user",
    content: toBlocks(message),
  });

  try {
    const finalText = await runAgentLoop(db, userId, message);
    await db.from("chat_messages").insert({ user_id: userId, role: "assistant", content: toBlocks(finalText) });
    return new Response(JSON.stringify({ content: toBlocks(finalText) }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("chat function error:", err);
    return new Response(JSON.stringify({ error: "internal_error", detail: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((b) => b && typeof b === "object" && b.type === "text")
      .map((b) => b.text as string)
      .join("");
  }
  return "";
}

async function loadRecentHistory(db: ReturnType<typeof serviceClient>, userId: string): Promise<ZhipuMessage[]> {
  const { data, error } = await db
    .from("chat_messages")
    .select("role, content, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(HISTORY_TURN_LIMIT + 1); // +1 because the just-inserted user message is included
  if (error) throw error;
  return (data ?? [])
    .slice(1) // drop the message we just inserted; it's appended explicitly below
    .reverse()
    .map((row) => ({ role: row.role === "tool" ? "user" : row.role, content: extractText(row.content) }));
}

async function runAgentLoop(db: ReturnType<typeof serviceClient>, userId: string, newMessage: string): Promise<string> {
  const today = await getLocalToday(db, userId);
  const history = await loadRecentHistory(db, userId);

  const messages: ZhipuMessage[] = [
    { role: "system", content: SYSTEM_PROMPT },
    ...history,
    { role: "user", content: `[今天的日期（用户本地时区）：${today}]\n\n${newMessage}` },
  ];

  for (let i = 0; i < MAX_TOOL_ITERATIONS; i++) {
    const reply = await callZhipu(messages);
    messages.push(reply);

    if (!reply.tool_calls || reply.tool_calls.length === 0) {
      return reply.content ?? "";
    }

    for (const call of reply.tool_calls) {
      let result: unknown;
      try {
        const input = call.function.arguments ? JSON.parse(call.function.arguments) : {};
        result = await dispatchTool(db, userId, call.function.name, input);
      } catch (err) {
        result = { error: "tool_execution_failed", detail: String(err) };
      }
      messages.push({ role: "tool", tool_call_id: call.id, content: JSON.stringify(result) });
    }
  }

  throw new Error("tool_loop_exceeded_max_iterations");
}
