-- 10_roles.sql — prod roles (idempotent; runs once on empty ./data/db).
-- PostgREST connects as `authenticator` and SET ROLEs to the JWT role per
-- request, so `authenticator` must be a member of every API role.
-- NOTE: no `community_admin` role here (dev mock artifact). Real GoTrue
-- issues role=authenticated; RLS keys off auth.uid(), not the role name.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;
END $$;

GRANT anon TO authenticated;
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;
-- Password for `authenticator` is set by 11_passwords.sh from POSTGRES_PASSWORD.
