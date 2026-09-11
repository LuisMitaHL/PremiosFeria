-- 58_organizer_students.sql — the complaints desk (spec 022).
--
-- Everything here is an exception to a rule the rest of the system enforces,
-- which is exactly why it is the most dangerous file in the set. Recovery is an
-- account takeover performed on purpose; an adjustment is the one change to a
-- balance that did not happen in the hall. Both are bounded, and both are
-- recorded.

-- Diez minutos. A diferencia del codigo de canje, nadie sondea este: el
-- organizador lo dicta y el estudiante lo escribe en su telefono nuevo. La
-- ventana es la que alcanza para cruzar el salon, no mas.
CREATE OR REPLACE FUNCTION recovery_code_ttl() RETURNS INTERVAL
LANGUAGE sql IMMUTABLE AS $fn$ SELECT INTERVAL '10 minutes' $fn$;

CREATE OR REPLACE FUNCTION recovery_code_is_live(c recovery_codes) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $fn$
  SELECT c.closed_at IS NULL AND c.issued_at > now() - recovery_code_ttl()
$fn$;

-- ---------------------------------------------------------------------------
-- El organizador emite el codigo, mirando a la persona.
CREATE OR REPLACE FUNCTION issue_recovery_code(p_participant_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row participants%ROWTYPE;
  v_code TEXT;
BEGIN
  IF calling_organizer() IS NULL THEN
    -- Que alguien que no es el organizador intente emitir un codigo de
    -- recuperacion es exactamente lo que el organizador deberia poder ver.
    PERFORM audit(p_action => 'participant.issue_recovery', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_row FROM participants WHERE id = p_participant_id FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM audit(p_action => 'participant.issue_recovery', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_reason => 'Estudiante no encontrado');
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;

  -- Emitir uno nuevo invalida el anterior.
  UPDATE recovery_codes SET closed_at = now(), closed_reason = 'replaced'
  WHERE participant_id = p_participant_id AND closed_at IS NULL;

  LOOP
    v_code := generate_claim_code();
    BEGIN
      INSERT INTO recovery_codes (participant_id, code) VALUES (p_participant_id, v_code);
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Colision con otro codigo abierto; se reintenta.
    END;
  END LOOP;

  -- Que se emitio, nunca cual. Un codigo de recuperacion en el registro es la
  -- capacidad de quedarse con el perfil de otro, y el registro lo lee el
  -- organizador en una pantalla abierta toda la tarde (R9).
  PERFORM audit(p_action => 'participant.issue_recovery', p_outcome => 'ok',
                p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                p_subject_kind => 'participant', p_subject_id => v_row.id,
                p_subject_label => v_row.name);

  RETURN jsonb_build_object('code', v_code, 'name', v_row.name);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- El estudiante lo escribe en su telefono nuevo.
--
-- Esto ES una toma de control de cuenta, hecha a proposito, y por eso todas las
-- defensas viven sobre el codigo: un solo uso, vida corta, uno por persona, e
-- impredecible. Mueve el perfil a este dispositivo; no lo copia.
CREATE OR REPLACE FUNCTION redeem_recovery_code(p_code TEXT, p_fingerprint TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid UUID := auth.uid();
  v_row recovery_codes%ROWTYPE;
  v_participant participants%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    PERFORM audit(p_action => 'participant.recover', p_outcome => 'refused',
                  p_actor_kind => 'anonymous',
                  p_reason => 'No se pudo crear tu sesión. Intenta de nuevo.');
    RETURN jsonb_build_object('error', 'No se pudo crear tu sesión. Intenta de nuevo.');
  END IF;

  SELECT * INTO v_row FROM recovery_codes
  WHERE code = upper(btrim(p_code)) AND closed_at IS NULL
  FOR UPDATE;

  IF NOT FOUND OR NOT recovery_code_is_live(v_row) THEN
    -- Sin sujeto: un codigo que no existe no apunta a nadie, y registrar el
    -- codigo tecleado convertiria el registro en una lista de intentos.
    PERFORM audit(p_action => 'participant.recover', p_outcome => 'refused',
                  p_actor_kind => 'anonymous', p_actor_id => v_uid,
                  p_reason => 'Código inválido o vencido. Pide uno nuevo en el stand de organización.');
    RETURN jsonb_build_object('error', 'Código inválido o vencido. Pide uno nuevo en el stand de organización.');
  END IF;

  -- Desvincular el dispositivo anterior es parte de la operacion, no un
  -- seguimiento: dos telefonos con el mismo perfil son dos personas sumando en
  -- un solo saldo, sin forma de saber cual es el dueno.
  UPDATE participants
  SET auth_user_id = v_uid,
      fingerprint = NULLIF(btrim(COALESCE(p_fingerprint, '')), '')
  WHERE id = v_row.participant_id
  RETURNING * INTO v_participant;

  UPDATE recovery_codes SET closed_at = now(), closed_reason = 'used'
  WHERE id = v_row.id;

  PERFORM audit(p_action => 'participant.recover', p_outcome => 'ok',
                p_actor_kind => 'participant', p_actor_id => v_participant.id,
                p_subject_kind => 'participant', p_subject_id => v_participant.id,
                p_subject_label => v_participant.name);

  RETURN jsonb_build_object('participant', to_jsonb(v_participant) - 'fingerprint');
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Ver lo que le paso a alguien. Para resolver un reclamo hay que poder mirar.
CREATE OR REPLACE FUNCTION participant_detail(p_participant_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row participants%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_row FROM participants WHERE id = p_participant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;

  RETURN jsonb_build_object(
    'participant', to_jsonb(v_row) - 'fingerprint',
    'scans', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'stand', c.name, 'type', s.type, 'activity', a.name,
        'points', s.points, 'at', s.created_at
      ) ORDER BY s.created_at DESC), '[]'::jsonb)
      FROM scans s
      JOIN communities c ON c.id = s.community_id
      LEFT JOIN activities a ON a.id = s.activity_id
      WHERE s.participant_id = p_participant_id
    ),
    'claims', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'reward', r.name, 'cost', r.cost, 'stand', c.name, 'at', cr.claimed_at
      ) ORDER BY cr.claimed_at DESC), '[]'::jsonb)
      FROM claimed_rewards cr
      JOIN rewards r ON r.id = cr.reward_id
      LEFT JOIN communities c ON c.id = cr.confirmed_by
      WHERE cr.participant_id = p_participant_id
    ),
    'adjustments', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'amount', pa.amount, 'reason', pa.reason, 'at', pa.adjusted_at
      ) ORDER BY pa.adjusted_at DESC), '[]'::jsonb)
      FROM point_adjustments pa
      WHERE pa.participant_id = p_participant_id
    )
  );
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Renombrar. Sujeto a las mismas reglas que el registro: el nickname sigue
-- siendo la llave de vuelta y sigue apareciendo en un ranking proyectado.
CREATE OR REPLACE FUNCTION organizer_rename_participant(p_participant_id UUID, p_name TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row participants%ROWTYPE;
  v_antes TEXT;
  v_fallo TEXT;
BEGIN
  IF calling_organizer() IS NULL THEN
    PERFORM audit(p_action => 'participant.rename', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- El nombre anterior se lee antes del UPDATE. Despues ya no existe en ningun
  -- lado, y "se renombro" sin decir desde que no responde la pregunta que
  -- alguien vino a hacer (R7).
  SELECT name INTO v_antes FROM participants WHERE id = p_participant_id;

  BEGIN
    UPDATE participants SET name = btrim(p_name)
    WHERE id = p_participant_id
    RETURNING * INTO v_row;
  EXCEPTION
    WHEN unique_violation THEN
      v_fallo := 'Ese nombre ya está en uso.';
    WHEN check_violation THEN
      v_fallo := 'El nombre debe tener entre 2 y 24 caracteres.';
  END;

  -- El asiento va fuera del bloque: el registro tiene su propio CHECK, que
  -- levanta check_violation, y ese manejador lo confundiria con un nombre de
  -- largo invalido (R21).
  IF v_fallo IS NULL AND NOT FOUND THEN
    v_fallo := 'Estudiante no encontrado';
  END IF;

  IF v_fallo IS NOT NULL THEN
    PERFORM audit(p_action => 'participant.rename', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_subject_kind => 'participant', p_subject_id => p_participant_id,
                  p_subject_label => v_antes,
                  p_reason => v_fallo);
    RETURN jsonb_build_object('error', v_fallo);
  END IF;

  PERFORM audit(p_action => 'participant.rename', p_outcome => 'ok',
                p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                p_subject_kind => 'participant', p_subject_id => v_row.id,
                p_subject_label => v_row.name,
                p_before => jsonb_build_object('name', v_antes));
  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint');
END;
$fn$;

-- Las dos sanciones. Bloquear el canje deja jugar y sumar: es la que el
-- registro anuncia para un nombre ofensivo, y quitarle todo a alguien por eso
-- seria desproporcionado. Retirar saca del evento.
CREATE OR REPLACE FUNCTION organizer_set_participant_flags(
  p_participant_id UUID,
  p_claims_barred BOOLEAN,
  p_removed BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row participants%ROWTYPE;
  v_antes participants%ROWTYPE;
BEGIN
  IF calling_organizer() IS NULL THEN
    PERFORM audit(p_action => 'participant.set_flags', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_antes FROM participants WHERE id = p_participant_id;

  UPDATE participants
  SET claims_barred = COALESCE(p_claims_barred, claims_barred),
      is_removed    = COALESCE(p_removed, is_removed)
  WHERE id = p_participant_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    PERFORM audit(p_action => 'participant.set_flags', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_subject_kind => 'participant', p_subject_id => p_participant_id,
                  p_reason => 'Estudiante no encontrado');
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;

  -- Solo las dos banderas, no la fila: v_antes trae tambien el fingerprint, y
  -- copiarla entera lo publicaria en el registro. El disparador lo rechazaria,
  -- pero la forma correcta es no llevarlo (R9).
  PERFORM audit(p_action => 'participant.set_flags', p_outcome => 'ok',
                p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                p_subject_kind => 'participant', p_subject_id => v_row.id,
                p_subject_label => v_row.name,
                p_before => jsonb_build_object('claims_barred', v_antes.claims_barred,
                                               'is_removed', v_antes.is_removed),
                p_detail => jsonb_build_object('claims_barred', v_row.claims_barred,
                                               'is_removed', v_row.is_removed));
  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint');
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Ajustar un saldo a mano.
--
-- Es el unico cambio de puntos que no ocurrio en el salon, y por eso exige
-- motivo: un numero sin motivo le dice a quien lo lea despues QUE cambio, pero
-- no si debia cambiar, que es la unica pregunta que vale la pena hacerle a un
-- ajuste. Y queda en su propia tabla para que un saldo pueda descomponerse en
-- ganado y otorgado.
CREATE OR REPLACE FUNCTION organizer_adjust_points(
  p_participant_id UUID,
  p_amount INT,
  p_reason TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row participants%ROWTYPE;
  v_antes INT;
  v_fallo TEXT;
BEGIN
  IF calling_organizer() IS NULL THEN
    PERFORM audit(p_action => 'participant.adjust_points', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN
    PERFORM audit(p_action => 'participant.adjust_points', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_subject_kind => 'participant', p_subject_id => p_participant_id,
                  p_reason => 'El ajuste no puede ser cero.');
    RETURN jsonb_build_object('error', 'El ajuste no puede ser cero.');
  END IF;
  IF char_length(btrim(COALESCE(p_reason, ''))) < 3 THEN
    PERFORM audit(p_action => 'participant.adjust_points', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_subject_kind => 'participant', p_subject_id => p_participant_id,
                  p_reason => 'Indica el motivo del ajuste.');
    RETURN jsonb_build_object('error', 'Indica el motivo del ajuste.');
  END IF;

  SELECT points INTO v_antes FROM participants WHERE id = p_participant_id;

  BEGIN
    -- La condicion vive en el WHERE: el CHECK de saldo no negativo ata a todos
    -- los que escriben, incluido el organizador (spec 020, R12).
    UPDATE participants SET points = points + p_amount
    WHERE id = p_participant_id AND points + p_amount >= 0
    RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    v_fallo := 'El ajuste dejaría el saldo en negativo.';
  END;

  -- Fuera del bloque: el CHECK del registro tambien levanta check_violation, y
  -- ese manejador lo haria pasar por un saldo negativo (R21).
  IF v_fallo IS NULL AND NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id) THEN
      v_fallo := 'El ajuste dejaría el saldo en negativo.';
    ELSE
      v_fallo := 'Estudiante no encontrado';
    END IF;
  END IF;

  IF v_fallo IS NOT NULL THEN
    PERFORM audit(p_action => 'participant.adjust_points', p_outcome => 'refused',
                  p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                  p_subject_kind => 'participant', p_subject_id => p_participant_id,
                  p_detail => jsonb_build_object('amount', p_amount),
                  p_reason => v_fallo);
    RETURN jsonb_build_object('error', v_fallo);
  END IF;

  INSERT INTO point_adjustments (participant_id, amount, reason)
  VALUES (p_participant_id, p_amount, btrim(p_reason));

  -- El motivo del ajuste va tambien en el asiento: es lo que se le pregunta a
  -- un ajuste, y tenerlo solo en point_adjustments obliga a cruzar dos lugares
  -- para leer una sola decision.
  PERFORM audit(p_action => 'participant.adjust_points', p_outcome => 'ok',
                p_actor_kind => 'organizer', p_actor_id => calling_organizer(),
                p_subject_kind => 'participant', p_subject_id => v_row.id,
                p_subject_label => v_row.name,
                p_before => jsonb_build_object('points', v_antes),
                p_detail => jsonb_build_object('amount', p_amount,
                                               'reason', btrim(p_reason),
                                               'points', v_row.points));
  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint');
END;
$fn$;
