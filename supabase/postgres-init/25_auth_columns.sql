-- 25_auth_columns.sql — links public rows to GoTrue users (audit F2/F4).
-- Same end state as admin-auth-migration.sql + participant-auth-migration.sql,
-- minus what a fresh prod DB does not need:
--   * no REFERENCES auth.users(...) — the auth schema is created by the GoTrue
--     container AFTER first boot; a FK here would fail at init time. Plain
--     UUID columns are enough (RLS/RPC only compare values to auth.uid()).
--   * no user provisioning — that lives in supabase/bootstrap/seed.sql, which
--     runs after GoTrue finishes its own migrations.
ALTER TABLE public.participants ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.communities ADD COLUMN IF NOT EXISTS auth_user_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS participants_auth_user_id_key
  ON public.participants(auth_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS communities_auth_user_id_key
  ON public.communities(auth_user_id);

-- Destructive on purpose: plaintext stand passwords must not exist in prod.
-- Login moves to GoTrue (auth.users, bcrypt). `username` is kept (NOT NULL)
-- as a human-readable login mapping; bootstrap seeds it with the email.
ALTER TABLE public.communities DROP COLUMN IF EXISTS password;
