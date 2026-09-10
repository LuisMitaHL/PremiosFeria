-- 51_stand_login.sql — username/password check for the auth service.
-- Case-insensitive on username; bcrypt compare via pgcrypto. Returns one row
-- on success, zero rows otherwise (the service maps both to a generic
-- invalid_credentials — no user enumeration). SECURITY DEFINER bypasses RLS
-- so anon callers can authenticate; the password hash never leaves the DB
-- (only id/username/name are returned).
CREATE OR REPLACE FUNCTION stand_login(p_username TEXT, p_password TEXT)
RETURNS TABLE (id UUID, username TEXT, name TEXT)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT c.id, c.username, c.name
  FROM communities c
  WHERE lower(c.username) = lower(btrim(p_username))
    AND c.password_hash = crypt(p_password, c.password_hash)
    -- Una comunidad retirada no inicia sesion (spec 023, R15). Se comprueba
    -- aca y no en la pantalla: su admin ya tiene un token en la mano.
    AND NOT c.is_withdrawn
$$;

GRANT EXECUTE ON FUNCTION stand_login(TEXT, TEXT) TO anon;
