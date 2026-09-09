-- 10_anon_role_trigger.sql — GoTrue v2.177 stores anonymous users with
-- role='' (empty string), so their JWTs carry "role":"" and PostgREST fails
-- with `role "" does not exist`. Supabase Cloud issues role=authenticated
-- for anonymous users; this trigger restores that behavior.
-- Additive only (function lives in public, not in GoTrue's auth schema) and
-- idempotent. Existing pre-fix rows are repaired by the UPDATE below.
-- Already-issued tokens keep the empty claim until refresh (GoTrue refresh
-- mints a new JWT from the fixed row — self-heals).
CREATE OR REPLACE FUNCTION public.fix_anon_role() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.role IS NULL OR NEW.role = '' THEN
    NEW.role := 'authenticated';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS fix_anon_role ON auth.users;
CREATE TRIGGER fix_anon_role
  BEFORE INSERT OR UPDATE OF role ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.fix_anon_role();

UPDATE auth.users SET role = 'authenticated'
  WHERE role IS NULL OR role = '';
