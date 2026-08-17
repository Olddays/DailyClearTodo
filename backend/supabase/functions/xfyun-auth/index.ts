import { createClient } from "npm:@supabase/supabase-js@2";

// Mints a short-lived, HMAC-signed WebSocket URL for 讯飞 (iFlytek)'s streaming
// "语音听写" (IAT) API, per their documented WebAPI auth scheme:
// https://www.xfyun.cn/doc/asr/voicedictation/API.html
//
// The APIKey/APISecret never leave this function -- the client only ever sees
// the resulting signed URL, which is bound to the request timestamp and can't
// be reused to derive the secret. This mirrors why the Zhipu API key lives in
// the `chat` function instead of the Flutter app: any credential embedded in a
// compiled client binary can be extracted and used to burn the developer's
// quota.
const APP_ID = Deno.env.get("XFYUN_APP_ID")!;
const API_KEY = Deno.env.get("XFYUN_API_KEY")!;
const API_SECRET = Deno.env.get("XFYUN_API_SECRET")!;

const HOST = "iat-api.xfyun.cn";
const PATH = "/v2/iat";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function hmacSha256Base64(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(signature)));
}

async function buildSignedUrl(): Promise<string> {
  // RFC1123 date, e.g. "Mon, 01 Jan 2026 00:00:00 GMT" -- 讯飞 validates the
  // signature against this exact string, so it must match what's sent as the
  // `date` query param below.
  const date = new Date().toUTCString();
  const signatureOrigin = `host: ${HOST}\ndate: ${date}\nGET ${PATH} HTTP/1.1`;
  const signatureBase64 = await hmacSha256Base64(API_SECRET, signatureOrigin);
  const authorizationOrigin =
    `api_key="${API_KEY}", algorithm="hmac-sha256", headers="host date request-line", signature="${signatureBase64}"`;
  const authorization = btoa(authorizationOrigin);

  const params = new URLSearchParams({ authorization, date, host: HOST });
  return `wss://${HOST}${PATH}?${params.toString()}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
  }

  // Same auth pattern as the chat function -- require a real logged-in user so
  // anonymous callers can't burn the developer's 讯飞 quota.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) {
    return new Response(JSON.stringify({ error: "missing_authorization" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
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

  try {
    const wsUrl = await buildSignedUrl();
    return new Response(JSON.stringify({ appId: APP_ID, wsUrl }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("xfyun-auth error:", err);
    return new Response(JSON.stringify({ error: "internal_error", detail: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
