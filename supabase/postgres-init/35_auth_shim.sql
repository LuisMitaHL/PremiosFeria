-- 35_auth_shim.sql — minimal auth.jwt()/auth.uid() helpers.
-- PostgREST sets `request.jwt.claims` from the verified JWT on every request
-- (signed by our auth service with the shared JWT_SECRET); these helpers
-- expose it to RLS policies (40) and RPC (50), which resolve auth.uid() at
-- DDL time. Permanent: there is no GoTrue/auth schema in this stack.
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
