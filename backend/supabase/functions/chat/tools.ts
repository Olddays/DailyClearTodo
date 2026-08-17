import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { getLocalToday } from "./db.ts";

// deno-lint-ignore no-explicit-any
type JsonSchema = any;

interface ToolSpec {
  name: string;
  description: string;
  parameters: JsonSchema;
}

// Provider-agnostic specs; TOOL_DEFS below wraps these in the OpenAI-compatible
// {type:"function", function:{...}} shape Zhipu's /chat/completions expects.
const TOOL_SPECS: ToolSpec[] = [
  {
    name: "get_today_tasks",
    description:
      "Get the current user's tasks for today (their local date), including status and pomodoros used. Call this before adding tasks or answering status questions -- never guess what's already planned.",
    parameters: { type: "object", properties: {}, required: [] },
  },
  {
    name: "add_task",
    description:
      "Add a new task to today's plan. ONLY callable during morning planning, before any task has started execution today. Max 3 tasks per day. The server rejects calls outside the planning window -- if rejected, tell the user only status updates are allowed right now.",
    parameters: {
      type: "object",
      properties: { title: { type: "string", description: "Short task description" } },
      required: ["title"],
    },
  },
  {
    name: "update_task_status",
    description:
      "Update a task's status. Use when the user reports starting, completing, or abandoning a task, or answers 完成/未完/继续 after a pomodoro-end check-in.",
    parameters: {
      type: "object",
      properties: {
        task_id: { type: "string" },
        status: { type: "string", enum: ["pending", "in_progress", "done", "abandoned"] },
      },
      required: ["task_id", "status"],
    },
  },
  {
    name: "log_pomodoro",
    description:
      "Record a pomodoro session against a task (the client-side timer already ran; this just persists the result). Call when the user reports a pomodoro finished or when confirming a pomodoro-end check-in.",
    parameters: {
      type: "object",
      properties: {
        task_id: { type: "string" },
        outcome: { type: "string", enum: ["completed", "interrupted", "task_done"] },
        duration_sec: { type: "integer", description: "Actual duration in seconds, default 1500" },
      },
      required: ["task_id", "outcome"],
    },
  },
  {
    name: "get_history",
    description: "Get archived day records (tasks + completion_rate) for a date range. Use for '查看历史' or questions about a specific past date.",
    parameters: {
      type: "object",
      properties: {
        start_date: { type: "string", description: "YYYY-MM-DD" },
        end_date: { type: "string", description: "YYYY-MM-DD" },
      },
      required: ["start_date", "end_date"],
    },
  },
  {
    name: "get_week_summary",
    description:
      "Get aggregated completion-rate statistics for a week. Use for '本周总结'. Completion rate is always computed server-side from day_archives -- never estimate it.",
    parameters: {
      type: "object",
      properties: { week_offset: { type: "integer", description: "0 = this week, -1 = last week, etc.", default: 0 } },
      required: [],
    },
  },
];

export const TOOL_DEFS = TOOL_SPECS.map((spec) => ({
  type: "function" as const,
  function: spec,
}));

// Every handler takes the verified userId (from the caller's JWT, never from tool
// input) so the model can't be steered into touching another user's data.
export async function dispatchTool(
  db: SupabaseClient,
  userId: string,
  name: string,
  input: Record<string, unknown>,
): Promise<unknown> {
  switch (name) {
    case "get_today_tasks":
      return getTodayTasks(db, userId);
    case "add_task":
      return addTask(db, userId, String(input.title ?? "").trim());
    case "update_task_status":
      return updateTaskStatus(db, userId, String(input.task_id), String(input.status));
    case "log_pomodoro":
      return logPomodoro(
        db,
        userId,
        String(input.task_id),
        String(input.outcome),
        typeof input.duration_sec === "number" ? input.duration_sec : 1500,
      );
    case "get_history":
      return getHistory(db, userId, String(input.start_date), String(input.end_date));
    case "get_week_summary":
      return getWeekSummary(db, userId, typeof input.week_offset === "number" ? input.week_offset : 0);
    default:
      return { error: "unknown_tool", tool: name };
  }
}

async function getTodayTasks(db: SupabaseClient, userId: string) {
  const today = await getLocalToday(db, userId);
  const { data, error } = await db
    .from("tasks")
    .select("id, title, status, position, pomodoros_used, planned_pomodoros")
    .eq("user_id", userId)
    .eq("task_date", today)
    .order("position");
  if (error) throw error;
  return { date: today, tasks: data };
}

// The morning-planning guardrail lives here, not in the system prompt: add_task is
// only allowed while today has fewer than 3 tasks AND none of them has started
// execution yet (no in_progress/done status, no pomodoros logged). This is checked
// server-side on every call so a persuasive user message can't talk the model into
// reopening planning mid-day.
async function addTask(db: SupabaseClient, userId: string, title: string) {
  if (!title) return { error: "empty_title" };

  const today = await getLocalToday(db, userId);
  const { data: existing, error: fetchErr } = await db
    .from("tasks")
    .select("id, status, pomodoros_used")
    .eq("user_id", userId)
    .eq("task_date", today);
  if (fetchErr) throw fetchErr;

  if (existing.length >= 3) {
    return { error: "planning_closed", reason: "max_3_tasks_reached" };
  }
  const executionStarted = existing.some((t) => t.status !== "pending" || t.pomodoros_used > 0);
  if (executionStarted) {
    return { error: "planning_closed", reason: "execution_already_started" };
  }

  const { data, error } = await db
    .from("tasks")
    .insert({ user_id: userId, task_date: today, title, position: existing.length })
    .select("id, title, status, position")
    .single();
  if (error) throw error;

  await db
    .from("daily_planning_state")
    .upsert({ user_id: userId, plan_date: today, planned_at: new Date().toISOString() }, { onConflict: "user_id,plan_date", ignoreDuplicates: false });

  return { task: data };
}

async function updateTaskStatus(db: SupabaseClient, userId: string, taskId: string, status: string) {
  const patch: Record<string, unknown> = { status };
  if (status === "done") patch.completed_at = new Date().toISOString();
  const { data, error } = await db
    .from("tasks")
    .update(patch)
    .eq("id", taskId)
    .eq("user_id", userId) // service-role bypasses RLS -- this filter IS the access control here
    .select("id, title, status")
    .single();
  if (error) throw error;
  if (!data) return { error: "not_found_or_not_owned" };
  return { task: data };
}

async function logPomodoro(
  db: SupabaseClient,
  userId: string,
  taskId: string,
  outcome: string,
  durationSec: number,
) {
  // Ownership check up front -- a service-role insert has no RLS to fall back on.
  const { data: task, error: taskErr } = await db
    .from("tasks")
    .select("id")
    .eq("id", taskId)
    .eq("user_id", userId)
    .single();
  if (taskErr || !task) return { error: "not_found_or_not_owned" };

  const endedAt = new Date();
  const startedAt = new Date(endedAt.getTime() - durationSec * 1000);
  const { data, error } = await db
    .from("pomodoro_sessions")
    .insert({
      task_id: taskId,
      user_id: userId,
      started_at: startedAt.toISOString(),
      ended_at: endedAt.toISOString(),
      duration_sec: durationSec,
      outcome,
    })
    .select("id")
    .single();
  if (error) throw error;
  return { pomodoro_session_id: data.id };
}

async function getHistory(db: SupabaseClient, userId: string, startDate: string, endDate: string) {
  const { data: archives, error: archErr } = await db
    .from("day_archives")
    .select("archive_date, total_tasks, done_tasks, completion_rate, total_pomodoros")
    .eq("user_id", userId)
    .gte("archive_date", startDate)
    .lte("archive_date", endDate)
    .order("archive_date", { ascending: false });
  if (archErr) throw archErr;

  const { data: tasks, error: taskErr } = await db
    .from("tasks")
    .select("task_date, title, status, pomodoros_used")
    .eq("user_id", userId)
    .gte("task_date", startDate)
    .lte("task_date", endDate)
    .order("task_date", { ascending: false });
  if (taskErr) throw taskErr;

  return { archives, tasks };
}

async function getWeekSummary(db: SupabaseClient, userId: string, weekOffset: number) {
  const today = await getLocalToday(db, userId);
  const anchor = new Date(`${today}T00:00:00Z`);
  const dow = anchor.getUTCDay() === 0 ? 7 : anchor.getUTCDay(); // Monday-start week
  const monday = new Date(anchor);
  monday.setUTCDate(anchor.getUTCDate() - (dow - 1) + weekOffset * 7);
  const sunday = new Date(monday);
  sunday.setUTCDate(monday.getUTCDate() + 6);

  const startDate = monday.toISOString().slice(0, 10);
  const endDate = sunday.toISOString().slice(0, 10);

  const { data, error } = await db
    .from("day_archives")
    .select("archive_date, total_tasks, done_tasks, completion_rate, total_pomodoros")
    .eq("user_id", userId)
    .gte("archive_date", startDate)
    .lte("archive_date", endDate)
    .order("archive_date");
  if (error) throw error;

  const totalTasks = data.reduce((s, r) => s + r.total_tasks, 0);
  const doneTasks = data.reduce((s, r) => s + r.done_tasks, 0);
  const totalPomodoros = data.reduce((s, r) => s + r.total_pomodoros, 0);

  return {
    start_date: startDate,
    end_date: endDate,
    days: data,
    total_tasks: totalTasks,
    done_tasks: doneTasks,
    completion_rate: totalTasks === 0 ? 0 : Math.round((doneTasks / totalTasks) * 1000) / 1000,
    total_pomodoros: totalPomodoros,
  };
}
