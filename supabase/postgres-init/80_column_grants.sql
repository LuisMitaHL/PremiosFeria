-- 80_column_grants.sql — column-level privileges for the API roles.
--
-- MUST RUN LAST. It grants the columns that exist at the moment it runs, so a
-- column created by a later file gets no grant and is invisible to every client
-- — which looks like a permissions bug a long way from its cause. The number is
-- 80 for that reason. If you add a file after this one that creates or alters a
-- table, move this one after it.
--
-- Row level security is row level ONLY. `participants` and `communities` are
-- deliberately world-readable so the leaderboard and the stand list can be
-- public — and that means readable *in full*, every column, by anyone holding
-- the publishable key.
--
-- Three columns must never be part of that:
--
--   communities.password_hash  the bcrypt hash of a stand's password. Readable,
--                              it can be cracked offline and used to sign in as
--                              that stand, which is the ability to award points
--                              and confirm handovers. Violates spec 010 R5.
--   communities.password       the same thing in plaintext. Dropped in prod by
--                              25_auth_columns.sql; still present in the dev
--                              schema, which is why it is listed here.
--   organizers.password_hash   the most powerful credential in the system. The
--                              table has RLS on with no policy as well, so this
--                              is the second lock on the same door.
--   participants.fingerprint   the device a participant registered from. After
--                              spec 001 it is half of the key that recovers a
--                              profile, so publishing it publishes half a
--                              credential. Violates spec 007 R12.
--
-- participants.auth_user_id stays readable on purpose. The client resolves its
-- own profile by it, and revoking it would break every session. Knowing the
-- subject of somebody's token grants nothing, because tokens are signed. When
-- spec 001 moves that lookup into a function, this column can be revoked too.
--
-- Note that a column-level REVOKE has no effect while a table-level SELECT
-- grant exists (30_grants.sql issues one). The table grant has to be revoked
-- and the permitted columns granted back, which is what this does.
--
-- The column lists AND the role list are computed rather than written out, so
-- this file works against both the production schema and the dev one, which
-- deliberately differ: dev keeps a plaintext password column and creates only
-- the anon role. SECURITY DEFINER functions run as the owner and are unaffected:
-- stand_login still compares hashes, and the RPC still read what they need.
--
-- ADDING A COLUMN THAT HOLDS A SECRET? Add it to the list below, and add an
-- assertion to tests/sql/08_column_privileges.sql.
--
-- ADDING AN ORDINARY COLUMN? It is hidden by default, which is the safe way
-- round. Re-running this file grants it; tests/sql/08_column_privileges.sql
-- fails if any non-secret column is unreadable, so the mistake is caught.

DO $$
DECLARE
  v_table   TEXT;
  v_secret  TEXT[];
  v_columns TEXT;
  v_roles   TEXT;
BEGIN
  -- Only the API roles that actually exist here. Production has anon and
  -- authenticated; the dev stack creates only anon.
  SELECT string_agg(quote_ident(rolname), ', ' ORDER BY rolname)
  INTO v_roles
  FROM pg_roles
  WHERE rolname IN ('anon', 'authenticated');

  IF v_roles IS NULL THEN
    RAISE EXCEPTION
      'Neither anon nor authenticated exists, so column privileges cannot be set. '
      'Secrets would be readable by every client role.';
  END IF;

  FOREACH v_table IN ARRAY ARRAY['participants', 'communities', 'organizers'] LOOP
    v_secret := CASE v_table
      WHEN 'participants' THEN ARRAY['fingerprint']
      WHEN 'communities'  THEN ARRAY['password_hash', 'password']
      WHEN 'organizers'   THEN ARRAY['password_hash']
    END;

    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO v_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = v_table
      AND NOT (column_name = ANY (v_secret));

    EXECUTE format('REVOKE SELECT ON public.%I FROM %s', v_table, v_roles);
    EXECUTE format('GRANT SELECT (%s) ON public.%I TO %s', v_columns, v_table, v_roles);
  END LOOP;
END $$;
