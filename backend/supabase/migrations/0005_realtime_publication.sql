-- Tables the Flutter client subscribes to via supabase_flutter's `.stream()`
-- (Postgres logical replication through Realtime) must be explicitly added to
-- the supabase_realtime publication -- RLS and table existence alone are not
-- enough; without this, .stream() throws RealtimeSubscribeException at runtime.
alter publication supabase_realtime add table public.chat_messages;
alter publication supabase_realtime add table public.tasks;
