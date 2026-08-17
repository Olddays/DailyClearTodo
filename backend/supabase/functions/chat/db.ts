import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

// Service-role client: bypasses RLS. Every function below takes an explicit
// userId derived from the caller's verified JWT (see index.ts) -- never trust a
// userId coming from tool-call input, since the model could in principle be
// steered into passing an arbitrary one.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
}

export async function getUserTimezone(db: SupabaseClient, userId: string): Promise<string> {
  const { data, error } = await db
    .from("user_profiles")
    .select("timezone")
    .eq("user_id", userId)
    .single();
  if (error) throw error;
  return data.timezone ?? "UTC";
}

// The user's current LOCAL calendar date, as a 'YYYY-MM-DD' string. All task_date
// comparisons go through this so "today" always means the user's own wall clock,
// not the server's UTC date.
export async function getLocalToday(db: SupabaseClient, userId: string): Promise<string> {
  const tz = await getUserTimezone(db, userId);
  const now = new Date();
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(now); // en-CA => YYYY-MM-DD
}
