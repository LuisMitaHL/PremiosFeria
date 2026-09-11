-- 57_registration.sql — registering and coming back (spec 001).
--
-- The nickname is the only thing an attendee gives, and it is also their way
-- back: typing it again on the same device returns the profile they already
-- have. That is what makes a name-only registration survive an afternoon.
--
-- One function, three outcomes, one atomic step. Split across a lookup and an
-- insert, two people registering the same nickname at once would both see it
-- free.

CREATE OR REPLACE FUNCTION register_or_recover(p_name TEXT, p_fingerprint TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_name TEXT := btrim(COALESCE(p_name, ''));
  v_uid UUID := auth.uid();
  v_existing participants%ROWTYPE;
  v_row participants%ROWTYPE;
  -- El motivo del rechazo del INSERT viaja hasta fuera del bloque para poder
  -- registrarlo: ver el comentario largo sobre el EXCEPTION, mas abajo.
  v_fallo TEXT;
BEGIN
  -- Un rechazo antes de que exista la fila lo hace alguien que todavia no es
  -- participante, asi que el actor es la sesion anonima y no un perfil.
  IF v_uid IS NULL THEN
    PERFORM audit(p_action => 'participant.register', p_outcome => 'refused',
                  p_actor_kind => 'anonymous',
                  p_reason => 'No se pudo crear tu sesión. Intenta de nuevo.');
    RETURN jsonb_build_object('error', 'No se pudo crear tu sesión. Intenta de nuevo.');
  END IF;

  IF char_length(v_name) < 2 THEN
    PERFORM audit(p_action => 'participant.register', p_outcome => 'refused',
                  p_actor_kind => 'anonymous', p_actor_id => v_uid,
                  p_reason => 'El nombre debe tener al menos 2 caracteres');
    RETURN jsonb_build_object('error', 'El nombre debe tener al menos 2 caracteres');
  END IF;
  IF char_length(v_name) > 24 THEN
    PERFORM audit(p_action => 'participant.register', p_outcome => 'refused',
                  p_actor_kind => 'anonymous', p_actor_id => v_uid,
                  p_reason => 'El nombre no puede tener más de 24 caracteres');
    RETURN jsonb_build_object('error', 'El nombre no puede tener más de 24 caracteres');
  END IF;

  -- ¿Ya existe ese nickname? Se bloquea la fila: dos intentos simultáneos sobre
  -- el mismo nombre se serializan acá, y el segundo ve lo que el primero dejó.
  SELECT * INTO v_existing FROM participants
  WHERE lower(btrim(name)) = lower(v_name)
  FOR UPDATE;

  IF FOUND THEN
    -- El dispositivo es el segundo factor que hace segura una identificación
    -- por nombre. Sin él, cualquiera escribe un nickname y se lleva el perfil.
    IF v_existing.fingerprint IS NOT NULL
       AND p_fingerprint IS NOT NULL
       AND v_existing.fingerprint = p_fingerprint THEN
      -- Vuelve a su perfil. Se re-vincula a esta sesión, que es el único lugar
      -- del sistema donde la identidad de una fila existente cambia.
      UPDATE participants SET auth_user_id = v_uid
      WHERE id = v_existing.id
      RETURNING * INTO v_row;

      -- Vuelve a su perfil por dispositivo, que no es lo mismo que recuperarlo
      -- con un codigo del organizador: se registra como registro, no como
      -- recuperacion, o el organizador leeria entregas de codigo que no hizo.
      PERFORM audit(p_action => 'participant.register', p_outcome => 'ok',
                    p_actor_kind => 'participant', p_actor_id => v_row.id,
                    p_subject_kind => 'participant', p_subject_id => v_row.id,
                    p_subject_label => v_row.name,
                    p_detail => jsonb_build_object('recovered', true));
      RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint',
                                'recovered', true);
    END IF;

    -- Mismo nombre, otro dispositivo. No se puede distinguir a quien cambió de
    -- teléfono de quien quiere el perfil ajeno, así que se rechaza: el error
    -- caro es el otro. Desde el spec 022 hay salida para quien de verdad lo
    -- perdió, y el mensaje ya puede prometerla (spec 001, R10b).
    PERFORM audit(p_action => 'participant.register', p_outcome => 'refused',
                  p_actor_kind => 'anonymous', p_actor_id => v_uid,
                  p_subject_kind => 'participant', p_subject_id => v_existing.id,
                  p_subject_label => v_existing.name,
                  p_reason => 'Ese nombre ya está en uso. Si es tuyo y cambiaste de dispositivo, acércate al stand de organización para recuperarlo.');
    RETURN jsonb_build_object('error',
      'Ese nombre ya está en uso. Si es tuyo y cambiaste de dispositivo, acércate al stand de organización para recuperarlo.');
  END IF;

  BEGIN
    INSERT INTO participants (name, fingerprint, auth_user_id)
    VALUES (v_name, NULLIF(btrim(COALESCE(p_fingerprint, '')), ''), v_uid)
    RETURNING * INTO v_row;
  EXCEPTION
    WHEN unique_violation THEN
      -- El índice es la puerta real: otra sesión ganó la carrera entre el
      -- SELECT de arriba y este INSERT.
      v_fallo := 'Ese nombre ya está en uso, elige otro.';
    WHEN check_violation THEN
      v_fallo := 'El nombre debe tener entre 2 y 24 caracteres';
  END;

  -- El asiento va FUERA del bloque a proposito. El registro tiene su propio
  -- CHECK (un rechazo sin motivo no se escribe), asi que un audit() descuidado
  -- ahi dentro levantaria check_violation y este mismo manejador lo convertiria
  -- en "el nombre debe tener entre 2 y 24 caracteres": un fallo al registrar
  -- disfrazado de rechazo comun, que es exactamente lo que R21 prohibe.
  IF v_fallo IS NOT NULL THEN
    PERFORM audit(p_action => 'participant.register', p_outcome => 'refused',
                  p_actor_kind => 'anonymous', p_actor_id => v_uid,
                  p_reason => v_fallo);
    RETURN jsonb_build_object('error', v_fallo);
  END IF;

  PERFORM audit(p_action => 'participant.register', p_outcome => 'ok',
                p_actor_kind => 'participant', p_actor_id => v_row.id,
                p_subject_kind => 'participant', p_subject_id => v_row.id,
                p_subject_label => v_row.name,
                p_detail => jsonb_build_object('recovered', false));
  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint',
                            'recovered', false);
END;
$fn$;
