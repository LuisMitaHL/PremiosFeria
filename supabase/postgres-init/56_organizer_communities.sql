-- 56_organizer_communities.sql — the organiser owns who the stands are (spec 023).
--
-- The line this draws did not exist before: the organiser owns *who a community
-- is* -- its name, its stand number, its credentials -- and the community owns
-- *what it does* -- its activities, its prizes, its handovers. A stand renaming
-- itself mid-fair changes what attendees are looking for on a map somebody
-- already printed.

-- Contraseñas generadas, nunca elegidas. Diez stands aprovisionados a las
-- apuradas la mañana de la feria es exactamente la situación que produce
-- "meh2026". Sin los caracteres que se confunden al copiarlos de una pantalla
-- y teclearlos en otra.
CREATE OR REPLACE FUNCTION generate_stand_password() RETURNS TEXT
LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE
  v_alphabet TEXT := '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ';
  v_out TEXT := '';
  v_byte INT;
BEGIN
  FOR i IN 1..12 LOOP
    v_byte := get_byte(gen_random_bytes(1), 0);
    v_out := v_out || substr(v_alphabet, (v_byte % length(v_alphabet)) + 1, 1);
  END LOOP;
  RETURN v_out;
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Crear una comunidad. Es el único camino: sin esto no hay stands, y sin
-- stands no hay feria.
CREATE OR REPLACE FUNCTION create_community(
  p_name TEXT,
  p_username TEXT,
  p_stand_number TEXT,
  p_emoji TEXT,
  p_description TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_password TEXT;
  v_row communities%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF btrim(COALESCE(p_username, '')) = '' OR btrim(COALESCE(p_name, '')) = '' THEN
    RETURN jsonb_build_object('error', 'El nombre y el usuario son obligatorios.');
  END IF;

  v_password := generate_stand_password();

  BEGIN
    INSERT INTO communities (username, name, stand_number, emoji, description,
                             password_hash, auth_user_id)
    VALUES (lower(btrim(p_username)), btrim(p_name), btrim(p_stand_number),
            COALESCE(NULLIF(btrim(p_emoji), ''), 'BookOpen'),
            NULLIF(btrim(COALESCE(p_description, '')), ''),
            crypt(v_password, gen_salt('bf', 12)),
            gen_random_uuid())
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Ese nombre de usuario ya existe.');
  END;

  -- La comunidad es su propia identidad, igual que en la siembra.
  UPDATE communities SET auth_user_id = id WHERE id = v_row.id RETURNING * INTO v_row;

  -- La contraseña se devuelve UNA sola vez, acá. Después solo queda el hash:
  -- guardar algo recuperable es guardar algo robable.
  RETURN jsonb_build_object(
    'community', to_jsonb(v_row) - 'password_hash',
    'password', v_password
  );
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Corregir los datos. El nombre de usuario NO se cambia: es lo que se le
-- entregó al stand en un papel, y cambiarlo invalida ese papel en silencio.
CREATE OR REPLACE FUNCTION update_community_profile(
  p_id UUID,
  p_name TEXT,
  p_stand_number TEXT,
  p_emoji TEXT,
  p_description TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row communities%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN
    RETURN jsonb_build_object('error', 'El nombre es obligatorio.');
  END IF;

  UPDATE communities
  SET name = btrim(p_name),
      stand_number = btrim(p_stand_number),
      emoji = COALESCE(NULLIF(btrim(p_emoji), ''), emoji),
      description = NULLIF(btrim(COALESCE(p_description, '')), '')
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;
  RETURN jsonb_build_object('community', to_jsonb(v_row) - 'password_hash');
END;
$fn$;

-- Restablecer la contraseña. Hoy esto exige una sentencia SQL a mano, que es
-- el punto de dolor más concreto durante un evento.
CREATE OR REPLACE FUNCTION reset_community_password(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_password TEXT;
  v_username TEXT;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  v_password := generate_stand_password();
  UPDATE communities SET password_hash = crypt(v_password, gen_salt('bf', 12))
  WHERE id = p_id
  RETURNING username INTO v_username;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;
  RETURN jsonb_build_object('username', v_username, 'password', v_password);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Retirar y reincorporar. Nunca eliminar.
CREATE OR REPLACE FUNCTION set_community_withdrawn(p_id UUID, p_withdrawn BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row communities%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  UPDATE communities SET is_withdrawn = COALESCE(p_withdrawn, false)
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;

  -- Retirar cierra lo que esté en curso: dejar una actividad abierta en un
  -- stand que ya no está sería seguir otorgando puntos por él.
  IF v_row.is_withdrawn THEN
    UPDATE activities
    SET finished_at = LEAST(now(), started_at + make_interval(mins => duration_min))
    WHERE community_id = p_id AND started_at IS NOT NULL AND finished_at IS NULL;
  END IF;

  RETURN jsonb_build_object('community', to_jsonb(v_row) - 'password_hash');
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Autoridad sobre los premios: lo que el spec 021 dejó diferido acá.
CREATE OR REPLACE FUNCTION set_reward_cost(p_reward_id UUID, p_cost INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row rewards%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  BEGIN
    UPDATE rewards SET cost = p_cost WHERE id = p_reward_id RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    -- El techo ata también al organizador: autoridad para corregir un precio
    -- no es autoridad para romper la economía.
    RETURN jsonb_build_object('error', 'El costo no puede superar los 300 puntos.');
  END;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;
  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;

CREATE OR REPLACE FUNCTION set_reward_stock(p_reward_id UUID, p_stock INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row rewards%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  BEGIN
    UPDATE rewards SET stock = p_stock WHERE id = p_reward_id RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    RETURN jsonb_build_object('error', 'El stock no puede ser menor a cero.');
  END;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;
  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;

CREATE OR REPLACE FUNCTION set_reward_withdrawn(p_reward_id UUID, p_withdrawn BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row rewards%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  UPDATE rewards SET is_withdrawn = COALESCE(p_withdrawn, false)
  WHERE id = p_reward_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;
  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;
