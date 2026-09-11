-- 51_stand_login.sql — username/password check for the auth service.
-- Case-insensitive on username; bcrypt compare via pgcrypto. Returns one row
-- on success, zero rows otherwise (the service maps both to a generic
-- invalid_credentials — no user enumeration). SECURITY DEFINER bypasses RLS
-- so anon callers can authenticate; the password hash never leaves the DB
-- (only id/username/name are returned).
-- Deja de ser STABLE porque ahora escribe: un intento fallido queda registrado
-- (spec 024, R4). El asiento dice que fallo y por que puerta, y nada mas. Un
-- registro de intentos fallidos que ademas guarde el usuario probado es una
-- lista de credenciales adivinadas, sentada en la unica pantalla que el
-- organizador mira todo el dia.
--
-- Un inicio de sesion correcto no se registra: no cambia nada, y R5 pide que
-- esto no se convierta en un flujo de diagnostico.
CREATE OR REPLACE FUNCTION stand_login(p_username TEXT, p_password TEXT)
RETURNS TABLE (id UUID, username TEXT, name TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  RETURN QUERY
  SELECT c.id, c.username, c.name
  FROM communities c
  WHERE lower(c.username) = lower(btrim(p_username))
    AND c.password_hash = crypt(p_password, c.password_hash)
    -- Una comunidad retirada no inicia sesion (spec 023, R15). Se comprueba
    -- aca y no en la pantalla: su admin ya tiene un token en la mano.
    AND NOT c.is_withdrawn;

  IF NOT FOUND THEN
    PERFORM audit(p_action => 'auth.sign_in_failed', p_outcome => 'refused',
                  p_actor_kind => 'anonymous',
                  p_detail => jsonb_build_object('scope', 'stand'),
                  p_reason => 'Credenciales incorrectas.');
  END IF;
END;
$fn$;

GRANT EXECUTE ON FUNCTION stand_login(TEXT, TEXT) TO anon;
