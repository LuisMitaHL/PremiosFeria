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
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_row FROM participants WHERE id = p_participant_id FOR UPDATE;
  IF NOT FOUND THEN
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
    RETURN jsonb_build_object('error', 'No se pudo crear tu sesión. Intenta de nuevo.');
  END IF;

  SELECT * INTO v_row FROM recovery_codes
  WHERE code = upper(btrim(p_code)) AND closed_at IS NULL
  FOR UPDATE;

  IF NOT FOUND OR NOT recovery_code_is_live(v_row) THEN
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
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  BEGIN
    UPDATE participants SET name = btrim(p_name)
    WHERE id = p_participant_id
    RETURNING * INTO v_row;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('error', 'Ese nombre ya está en uso.');
    WHEN check_violation THEN
      RETURN jsonb_build_object('error', 'El nombre debe tener entre 2 y 24 caracteres.');
  END;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;
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
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  UPDATE participants
  SET claims_barred = COALESCE(p_claims_barred, claims_barred),
      is_removed    = COALESCE(p_removed, is_removed)
  WHERE id = p_participant_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;
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
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN
    RETURN jsonb_build_object('error', 'El ajuste no puede ser cero.');
  END IF;
  IF char_length(btrim(COALESCE(p_reason, ''))) < 3 THEN
    RETURN jsonb_build_object('error', 'Indica el motivo del ajuste.');
  END IF;

  BEGIN
    -- La condicion vive en el WHERE: el CHECK de saldo no negativo ata a todos
    -- los que escriben, incluido el organizador (spec 020, R12).
    UPDATE participants SET points = points + p_amount
    WHERE id = p_participant_id AND points + p_amount >= 0
    RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    RETURN jsonb_build_object('error', 'El ajuste dejaría el saldo en negativo.');
  END;

  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM participants WHERE id = p_participant_id) THEN
      RETURN jsonb_build_object('error', 'El ajuste dejaría el saldo en negativo.');
    END IF;
    RETURN jsonb_build_object('error', 'Estudiante no encontrado');
  END IF;

  INSERT INTO point_adjustments (participant_id, amount, reason)
  VALUES (p_participant_id, p_amount, btrim(p_reason));

  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint');
END;
$fn$;
