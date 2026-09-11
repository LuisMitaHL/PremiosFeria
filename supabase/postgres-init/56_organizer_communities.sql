-- 56_organizer_communities.sql — the organiser owns who the stands are (spec 023).
--
-- The line this draws did not exist before: the organiser owns *who a community
-- is* -- its name, its stand number, its credentials -- and the community owns
-- *what it does* -- its activities, its prizes, its handovers. A stand renaming
-- itself mid-fair changes what attendees are looking for on a map somebody
-- already printed.
--
-- Cada función de acá deja su asiento en el registro de actividad (spec 024):
-- uno en el camino de éxito y uno en cada rechazo, con el mismo mensaje que se
-- devuelve como motivo. Es el archivo que más secretos maneja -- dos funciones
-- generan una contraseña -- y por eso vale una vez y para todas: en el asiento
-- se registra QUE la contraseña se creó o se restableció, nunca cuál es, y
-- `before` lleva sólo los campos que cambiaron y jamás la fila entera de
-- communities, que arrastraría el hash (spec 024, R9).

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
  -- Se resuelve una sola vez y se pasa al asiento: el registro no vuelve a
  -- deducir quién llamó, porque acá ya se sabe (spec 024, sección 2).
  v_organizer UUID := calling_organizer();
  v_password TEXT;
  v_row communities%ROWTYPE;
BEGIN
  IF v_organizer IS NULL THEN
    -- El rechazo es justamente que no se pudo resolver al llamante, así que el
    -- actor sale de la sesión y no de calling_organizer().
    PERFORM audit(
      p_action        => 'community.create',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF btrim(COALESCE(p_username, '')) = '' OR btrim(COALESCE(p_name, '')) = '' THEN
    PERFORM audit(
      p_action        => 'community.create',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_label => NULLIF(btrim(COALESCE(p_name, '')), ''),
      p_reason        => 'El nombre y el usuario son obligatorios.'
    );
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
    -- El asiento va en el manejador, nunca dentro del bloque protegido: si el
    -- registro no se puede escribir, la acción tiene que fallar y no devolver
    -- un rechazo tranquilo (spec 024, R21).
    PERFORM audit(
      p_action        => 'community.create',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_label => btrim(p_name),
      p_detail        => jsonb_build_object('username', lower(btrim(p_username))),
      p_reason        => 'Ese nombre de usuario ya existe.'
    );
    RETURN jsonb_build_object('error', 'Ese nombre de usuario ya existe.');
  END;

  -- La comunidad es su propia identidad, igual que en la siembra.
  UPDATE communities SET auth_user_id = id WHERE id = v_row.id RETURNING * INTO v_row;

  -- Queda el stand que se creó y con qué usuario entra. La contraseña no entra
  -- en ningún campo: el asiento dice que la comunidad existe, no cómo se abre.
  PERFORM audit(
    p_action        => 'community.create',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'community',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_detail        => jsonb_build_object('username', v_row.username,
                                          'stand_number', v_row.stand_number)
  );

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
  v_organizer UUID := calling_organizer();
  v_row communities%ROWTYPE;
  v_antes JSONB;
  v_despues JSONB;
  v_cambios JSONB;
  v_nuevos JSONB;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'community.update',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF btrim(COALESCE(p_name, '')) = '' THEN
    PERFORM audit(
      p_action        => 'community.update',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'El nombre es obligatorio.'
    );
    RETURN jsonb_build_object('error', 'El nombre es obligatorio.');
  END IF;

  -- Los valores viejos se leen ANTES del UPDATE: después ya no existen en
  -- ninguna parte, y un `before` leído al final diría que nada cambió
  -- (spec 024, R7). Se nombran los cuatro campos de perfil uno por uno en vez
  -- de copiar la fila, que traería el hash de la contraseña.
  SELECT jsonb_build_object('name', name, 'stand_number', stand_number,
                            'emoji', emoji, 'description', description)
    INTO v_antes
  FROM communities WHERE id = p_id;

  UPDATE communities
  SET name = btrim(p_name),
      stand_number = btrim(p_stand_number),
      emoji = COALESCE(NULLIF(btrim(p_emoji), ''), emoji),
      description = NULLIF(btrim(COALESCE(p_description, '')), '')
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'community.update',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'Comunidad no encontrada'
    );
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;

  v_despues := jsonb_build_object('name', v_row.name, 'stand_number', v_row.stand_number,
                                  'emoji', v_row.emoji, 'description', v_row.description);
  -- Sólo los campos que de verdad cambiaron. Guardar los cuatro siempre obliga
  -- a comparar a ojo para descubrir cuál se tocó, que es la pregunta.
  v_cambios := (SELECT jsonb_object_agg(k, v)
                FROM jsonb_each(v_antes) AS e(k, v)
                WHERE v IS DISTINCT FROM v_despues -> k);
  v_nuevos  := (SELECT jsonb_object_agg(k, v_despues -> k)
                FROM jsonb_object_keys(v_cambios) AS k);

  PERFORM audit(
    p_action        => 'community.update',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'community',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_before        => v_cambios,
    p_detail        => v_nuevos
  );

  RETURN jsonb_build_object('community', to_jsonb(v_row) - 'password_hash');
END;
$fn$;

-- Restablecer la contraseña. Hoy esto exige una sentencia SQL a mano, que es
-- el punto de dolor más concreto durante un evento.
CREATE OR REPLACE FUNCTION reset_community_password(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_organizer UUID := calling_organizer();
  v_password TEXT;
  v_username TEXT;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'community.reset_password',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  v_password := generate_stand_password();
  UPDATE communities SET password_hash = crypt(v_password, gen_salt('bf', 12))
  WHERE id = p_id
  RETURNING username INTO v_username;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'community.reset_password',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'Comunidad no encontrada'
    );
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;

  -- El asiento lleva a quién se le restableció y nada más. `before` va vacío a
  -- propósito: el valor anterior de esto es un hash bcrypt, y un hash es el
  -- secreto, no su descripción (spec 024, R9).
  PERFORM audit(
    p_action        => 'community.reset_password',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'community',
    p_subject_id    => p_id,
    p_subject_label => v_username
  );

  RETURN jsonb_build_object('username', v_username, 'password', v_password);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Retirar y reincorporar. Nunca eliminar.
CREATE OR REPLACE FUNCTION set_community_withdrawn(p_id UUID, p_withdrawn BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_organizer UUID := calling_organizer();
  v_row communities%ROWTYPE;
  v_antes BOOLEAN;
  v_cerradas INT := 0;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'community.set_withdrawn',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- El estado anterior, antes de pisarlo: el UPDATE devuelve el nuevo.
  SELECT is_withdrawn INTO v_antes FROM communities WHERE id = p_id;

  UPDATE communities SET is_withdrawn = COALESCE(p_withdrawn, false)
  WHERE id = p_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'community.set_withdrawn',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'community',
      p_subject_id    => p_id,
      p_reason        => 'Comunidad no encontrada'
    );
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;

  -- Retirar cierra lo que esté en curso: dejar una actividad abierta en un
  -- stand que ya no está sería seguir otorgando puntos por él.
  IF v_row.is_withdrawn THEN
    UPDATE activities
    SET finished_at = LEAST(now(), started_at + make_interval(mins => duration_min))
    WHERE community_id = p_id AND started_at IS NOT NULL AND finished_at IS NULL;
    GET DIAGNOSTICS v_cerradas = ROW_COUNT;
  END IF;

  -- Cuántas actividades se cerraron de arrastre va en el asiento porque si no
  -- se leen como actividades que terminaron solas, sin causa a la vista.
  PERFORM audit(
    p_action        => 'community.set_withdrawn',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'community',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_before        => jsonb_build_object('is_withdrawn', v_antes),
    p_detail        => jsonb_build_object('is_withdrawn', v_row.is_withdrawn,
                                          'activities_closed', v_cerradas)
  );

  RETURN jsonb_build_object('community', to_jsonb(v_row) - 'password_hash');
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Autoridad sobre los premios: lo que el spec 021 dejó diferido acá.
CREATE OR REPLACE FUNCTION set_reward_cost(p_reward_id UUID, p_cost INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_organizer UUID := calling_organizer();
  v_row rewards%ROWTYPE;
  v_antes INT;
  v_label TEXT;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'reward.reprice',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- "Costaba 200 y ahora cuesta 20" es el reclamo entero: el precio viejo hay
  -- que tomarlo acá, porque después del UPDATE ya no está en ningún lado.
  SELECT name, cost INTO v_label, v_antes FROM rewards WHERE id = p_reward_id;

  BEGIN
    UPDATE rewards SET cost = p_cost WHERE id = p_reward_id RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    -- El techo ata también al organizador: autoridad para corregir un precio
    -- no es autoridad para romper la economía.
    PERFORM audit(
      p_action        => 'reward.reprice',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_subject_label => v_label,
      p_before        => jsonb_build_object('cost', v_antes),
      p_detail        => jsonb_build_object('cost', p_cost),
      p_reason        => 'El costo no puede superar los 300 puntos.'
    );
    RETURN jsonb_build_object('error', 'El costo no puede superar los 300 puntos.');
  END;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'reward.reprice',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'Premio no encontrado'
    );
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;

  PERFORM audit(
    p_action        => 'reward.reprice',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'reward',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_before        => jsonb_build_object('cost', v_antes),
    p_detail        => jsonb_build_object('cost', v_row.cost)
  );

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;

CREATE OR REPLACE FUNCTION set_reward_stock(p_reward_id UUID, p_stock INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_organizer UUID := calling_organizer();
  v_row rewards%ROWTYPE;
  v_antes INT;
  v_label TEXT;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'reward.set_stock',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT name, stock INTO v_label, v_antes FROM rewards WHERE id = p_reward_id;

  BEGIN
    UPDATE rewards SET stock = p_stock WHERE id = p_reward_id RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    PERFORM audit(
      p_action        => 'reward.set_stock',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_subject_label => v_label,
      p_before        => jsonb_build_object('stock', v_antes),
      p_detail        => jsonb_build_object('stock', p_stock),
      p_reason        => 'El stock no puede ser menor a cero.'
    );
    RETURN jsonb_build_object('error', 'El stock no puede ser menor a cero.');
  END;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'reward.set_stock',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'Premio no encontrado'
    );
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;

  PERFORM audit(
    p_action        => 'reward.set_stock',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'reward',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_before        => jsonb_build_object('stock', v_antes),
    p_detail        => jsonb_build_object('stock', v_row.stock)
  );

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;

CREATE OR REPLACE FUNCTION set_reward_withdrawn(p_reward_id UUID, p_withdrawn BOOLEAN)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_organizer UUID := calling_organizer();
  v_row rewards%ROWTYPE;
  v_antes BOOLEAN;
BEGIN
  IF v_organizer IS NULL THEN
    PERFORM audit(
      p_action        => 'reward.withdraw',
      p_outcome       => 'refused',
      p_actor_kind    => audit_actor(),
      p_actor_id      => audit_actor_id(),
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'No autorizado'
    );
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT is_withdrawn INTO v_antes FROM rewards WHERE id = p_reward_id;

  UPDATE rewards SET is_withdrawn = COALESCE(p_withdrawn, false)
  WHERE id = p_reward_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM audit(
      p_action        => 'reward.withdraw',
      p_outcome       => 'refused',
      p_actor_kind    => 'organizer',
      p_actor_id      => v_organizer,
      p_subject_kind  => 'reward',
      p_subject_id    => p_reward_id,
      p_reason        => 'Premio no encontrado'
    );
    RETURN jsonb_build_object('error', 'Premio no encontrado');
  END IF;

  -- Retirar y reincorporar son la misma acción con distinto valor, y así se
  -- leen en el registro: el par before/detail dice en qué sentido fue.
  PERFORM audit(
    p_action        => 'reward.withdraw',
    p_outcome       => 'ok',
    p_actor_kind    => 'organizer',
    p_actor_id      => v_organizer,
    p_subject_kind  => 'reward',
    p_subject_id    => v_row.id,
    p_subject_label => v_row.name,
    p_before        => jsonb_build_object('is_withdrawn', v_antes),
    p_detail        => jsonb_build_object('is_withdrawn', v_row.is_withdrawn)
  );

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;
