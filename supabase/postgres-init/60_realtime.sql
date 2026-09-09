-- 60_realtime.sql — realtime listens to these tables for the app's
-- postgres_changes subscriptions (subscribeToLeaderboard on participants,
-- subscribeToScans on scans in src/lib/api.js). REPLICA IDENTITY FULL so
-- UPDATE/DELETE payloads carry the full row. Publication survives restarts
-- (stored in ./data/db); the realtime container creates its own slot.
-- The realtime container connects with search_path=_realtime and runs its own
-- Ecto migrations there on boot; the schema must pre-exist (the
-- supabase/postgres image ships it, plain postgres does not).
CREATE SCHEMA IF NOT EXISTS _realtime;
-- Tenant migrations also expect a `realtime` schema (same origin).
CREATE SCHEMA IF NOT EXISTS realtime;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime FOR TABLE public.participants, public.scans;
  END IF;
END $$;
ALTER TABLE public.participants REPLICA IDENTITY FULL;
ALTER TABLE public.scans REPLICA IDENTITY FULL;
