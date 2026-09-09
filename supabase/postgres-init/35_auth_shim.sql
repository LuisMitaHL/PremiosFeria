-- 35_auth_shim.sql — minimal auth.jwt()/auth.uid() helpers.
-- PostgREST sets `request.jwt.claims` from the verified JWT on every request;
-- these helpers expose it to RLS policies (40) and RPC (50), which are
-- created right after and resolve auth.uid() at DDL time.
-- GoTrue only migrates auth.users/auth.identities tables later — it does not
-- define these helpers, so there is no conflict (same pattern as the dev
-- stack's 35_auth_compat.sql, minus roles/columns which live in 10/25).
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(auth.jwt() ->> 'sub', '')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO PUBLIC;
