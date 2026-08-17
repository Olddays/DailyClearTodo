-- 日清 DailyClear: core schema
-- Design: "today" is a query (tasks.task_date = user's current local date), not a
-- separate table. "History" is the same tasks table for past dates, plus a durable
-- day_archives summary written once by the archive job.

create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists moddatetime;
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Per-user profile. timezone is the linchpin for correct local-midnight archiving.
create table public.user_profiles (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  timezone      text not null default 'UTC',   -- IANA tz name, e.g. 'Asia/Shanghai'
  display_name  text,
  created_at    timestamptz not null default now()
);

-- Tasks: one row per task, scoped to the LOCAL calendar date it was planned for.
create table public.tasks (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  task_date          date not null,
  title              text not null,
  status             text not null default 'pending'
                       check (status in ('pending', 'in_progress', 'done', 'abandoned')),
  position           smallint not null default 0 check (position between 0 and 2),
  planned_pomodoros  smallint,
  pomodoros_used     smallint not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  completed_at       timestamptz
);
create index tasks_user_date_idx on public.tasks (user_id, task_date);
create trigger tasks_set_updated_at before update on public.tasks
  for each row execute procedure moddatetime(updated_at);

-- Pomodoro session log: append-only, one row per pomodoro attempt.
-- Durable source of truth for pomodoro history; tasks.pomodoros_used is a
-- denormalized counter kept in sync via trigger below for cheap reads.
create table public.pomodoro_sessions (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references public.tasks(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  started_at    timestamptz not null,
  ended_at      timestamptz,
  duration_sec  integer not null default 1500,
  outcome       text check (outcome in ('completed', 'interrupted', 'task_done')),
  created_at    timestamptz not null default now()
);
create index pomo_task_idx on public.pomodoro_sessions (task_id);

-- Fires on INSERT (the common case: a session is logged after it already
-- finished, ended_at set from the start) and on UPDATE (a session that was
-- inserted while still running, later closed out) -- must handle both since a
-- plain "after update" trigger never sees the INSERT case at all.
create or replace function public.bump_pomodoro_count() returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    if new.ended_at is not null then
      update public.tasks set pomodoros_used = pomodoros_used + 1 where id = new.task_id;
    end if;
  elsif TG_OP = 'UPDATE' then
    if new.ended_at is not null and old.ended_at is null then
      update public.tasks set pomodoros_used = pomodoros_used + 1 where id = new.task_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;
create trigger pomo_bump after insert or update on public.pomodoro_sessions
  for each row execute procedure public.bump_pomodoro_count();

-- Day archive: ONE row per user per local calendar day, written once by the archive
-- job. History reads this for stats instead of recomputing aggregates every time.
create table public.day_archives (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users(id) on delete cascade,
  archive_date      date not null,
  total_tasks       smallint not null,
  done_tasks        smallint not null,
  completion_rate   numeric(4,3) not null,
  total_pomodoros   integer not null default 0,
  archived_at       timestamptz not null default now(),
  unique (user_id, archive_date)
);
create index day_archives_user_date_idx on public.day_archives (user_id, archive_date desc);

-- Chat message history: multi-turn context + transcript display. Pomodoro-end
-- check-ins are also written here directly (without going through the LLM) so the
-- transcript stays continuous.
create table public.chat_messages (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  role          text not null check (role in ('user', 'assistant', 'tool')),
  content       jsonb not null,
  created_at    timestamptz not null default now()
);
create index chat_messages_user_created_idx on public.chat_messages (user_id, created_at);

-- Deterministic gate for "only allow add_task during morning planning" -- not
-- trusted to the LLM/system prompt alone.
create table public.daily_planning_state (
  user_id        uuid not null references auth.users(id) on delete cascade,
  plan_date      date not null,
  planned_at     timestamptz,
  primary key (user_id, plan_date)
);

-- New auth.users rows get a matching profile automatically (default UTC timezone;
-- client updates it to the device's real timezone right after sign-up).
create or replace function public.handle_new_user() returns trigger as $$
begin
  insert into public.user_profiles (user_id) values (new.id);
  return new;
end;
$$ language plpgsql security definer set search_path = public;
create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();
