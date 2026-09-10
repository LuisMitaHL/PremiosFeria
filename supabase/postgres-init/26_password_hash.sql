-- 26_password_hash.sql — bcrypt password hashes for stand logins.
-- Plaintext `password` was dropped in 25; the auth service verifies via the
-- stand_login RPC (crypt compare, SECURITY DEFINER). NULL hashes never match
-- (NULL = anything is NULL), so operator-created rows stay locked until set:
--   UPDATE communities SET password_hash = crypt('NewPass*', gen_salt('bf', 12))
--   WHERE username = 'meh';
ALTER TABLE public.communities ADD COLUMN IF NOT EXISTS password_hash TEXT;
