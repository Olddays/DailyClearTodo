-- Archives ONE user's ONE local day. Idempotent: safe to call any number of times
-- for the same (user_id, local_date) -- guarded by an existence check AND the
-- day_archives unique constraint with `on conflict do nothing`.
create or replace function public.archive_user_day(p_user_id uuid, p_local_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total smallint;
  v_done  smallint;
  v_pomos integer;
begin
  if exists (
    select 1 from public.day_archives
    where user_id = p_user_id and archive_date = p_local_date
  ) then
    return;
  end if;

  select count(*), count(*) filter (where status = 'done'),
         coalesce(sum(pomodoros_used), 0)
    into v_total, v_done, v_pomos
    from public.tasks
   where user_id = p_user_id and task_date = p_local_date;

  insert into public.day_archives
    (user_id, archive_date, total_tasks, done_tasks, completion_rate, total_pomodoros)
  values (
    p_user_id, p_local_date, coalesce(v_total, 0), coalesce(v_done, 0),
    case when coalesce(v_total, 0) = 0 then 0 else round(v_done::numeric / v_total, 3) end,
    coalesce(v_pomos, 0)
  )
  on conflict (user_id, archive_date) do nothing;

  -- Freeze (not delete) any tasks still open -- history keeps them visible with a
  -- final status. Already-done tasks are untouched.
  update public.tasks
     set status = 'abandoned'
   where user_id = p_user_id and task_date = p_local_date
     and status in ('pending', 'in_progress');
end;
$$;

-- Sweep across all users. Rather than scheduling one cron entry per timezone
-- (doesn't scale, isn't how pg_cron works), this runs frequently and archives
-- "yesterday" for each user once their LOCAL date has rolled over -- which can only
-- happen strictly after their local 23:59:59. Silent: never writes a chat_messages
-- row or otherwise notifies the user (the "冷酷的归档" constraint) -- the only
-- surface for yesterday's leftover count is the next morning-planning turn, which
-- reads day_archives once via the chat Edge Function.
create or replace function public.run_archive_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_local_date date;
begin
  for r in select up.user_id, up.timezone from public.user_profiles up
  loop
    v_local_date := (now() at time zone r.timezone)::date;
    perform public.archive_user_day(r.user_id, v_local_date - 1);
  end loop;
end;
$$;
