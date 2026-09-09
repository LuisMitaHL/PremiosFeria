-- 25_auth_columns.sql — links public rows to auth identities (audit F2/F4).
-- auth_user_id carries the caller's JWT sub: community id for stands
-- (auth_user_id = own id, set by the seed), anonymous uuid for participants.
-- Plain UUID columns, no FK: the auth service (not a GoTrue auth schema)
-- owns identity, so there is nothing to reference.
ALTER TABLE public.participants ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE public.communities ADD COLUMN IF NOT EXISTS auth_user_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS participants_auth_user_id_key
  ON public.participants(auth_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS communities_auth_user_id_key
  ON public.communities(auth_user_id);

-- Destructive on purpose: plaintext stand passwords must not exist in prod.
-- Login moves to the auth service (bcrypt in communities.password_hash).
-- `username` is kept (NOT NULL) as the bare login name.
ALTER TABLE public.communities DROP COLUMN IF EXISTS password;
