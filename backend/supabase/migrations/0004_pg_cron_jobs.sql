-- Runs the archive sweep every 5 minutes. pg_cron runs inside Postgres itself on
-- the server's UTC clock -- no network round trip, no LLM involvement, no
-- dependency on any client being online. Worst-case lag between a user's true
-- local 23:59 and their archive landing is ~5 minutes.
select cron.schedule(
  'archive-sweep',
  '*/5 * * * *',
  $$ select public.run_archive_sweep(); $$
);
