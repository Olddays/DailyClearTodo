-- Row Level Security: every table is owner-only for the client (anon/authenticated
-- roles). day_archives and daily_planning_state are read-only to the client --
-- only the service-role key (Edge Functions / pg_cron functions running as
-- security definer) may write them. This is what makes the archive "cold" and
-- tamper-proof: neither the client nor the LLM's tool calls (which run under the
-- user's own session) can fake a completion rate or reopen a closed day.

alter table public.user_profiles enable row level security;
alter table public.tasks enable row level security;
alter table public.pomodoro_sessions enable row level security;
alter table public.day_archives enable row level security;
alter table public.chat_messages enable row level security;
alter table public.daily_planning_state enable row level security;

create policy "own rows" on public.user_profiles for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rows" on public.tasks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rows" on public.pomodoro_sessions for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rows read" on public.day_archives for select
  using (user_id = auth.uid());

create policy "own rows" on public.chat_messages for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own rows read" on public.daily_planning_state for select
  using (user_id = auth.uid());
