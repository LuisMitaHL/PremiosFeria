-- 50_rpc.sql — canonical RPC source (game rules, SECURITY DEFINER:
-- anon callers execute with owner rights; scoping via auth.uid(), never
-- client-supplied ids).
--
-- Messages here are written without emoji, per AGENTS.md. The remaining emoji
-- elsewhere in the product are spec 016's to remove.

DROP FUNCTION IF EXISTS simple_hmac(TEXT, TEXT);

-- ---------------------------------------------------------------------------
-- 0. What everything is worth (spec 020).
--
-- Constants, in one place. A stand no longer sets its own values: a visit is
-- worth the same everywhere, so the leaderboard compares people rather than
-- routes. They are a function rather than a table row on purpose -- a row is an
-- invitation to edit it, and changing these mid-event would silently revalue
-- every prize and every position.
CREATE OR REPLACE FUNCTION points_config() RETURNS JSONB
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT jsonb_build_object(
    'visit', 10,
    'activity_main', 30,
    'activity_other', 10,
    'visit_cooldown_minutes', 30
  )
$fn$;

-- What a given scan is worth. One place, so the signing side and the awarding
-- side cannot disagree.
CREATE OR REPLACE FUNCTION scan_award(p_type TEXT, p_activity UUID) RETURNS INT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT CASE
    WHEN p_type = 'visit' THEN (points_config()->>'visit')::int
    WHEN EXISTS (SELECT 1 FROM activities WHERE id = p_activity AND is_main_event)
      THEN (points_config()->>'activity_main')::int
    ELSE (points_config()->>'activity_other')::int
  END
$fn$;

-- The signed string. Every field that decides the award is signed together, so
-- a payload cannot be assembled from parts of two valid codes.
CREATE OR REPLACE FUNCTION scan_signature(
  p_community UUID, p_activity UUID, p_ts BIGINT, p_type TEXT, p_secret TEXT
) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT encode(
    hmac(p_community || '|' || COALESCE(p_activity::text, '') || '|' || p_ts || '|' || p_type,
         p_secret, 'sha256'),
    'hex')
$fn$;

-- ---------------------------------------------------------------------------
-- 1. Firmar códigos QR en el servidor (el secreto nunca sale de la base).
-- Nota de despliegue: rota el secreto UNA vez tras aplicar esta versión,
-- porque el valor anterior fue público (hallazgo F3 del audit):
--   UPDATE settings SET value = gen_random_uuid()::text || gen_random_uuid()::text
--   WHERE key = 'hmac_secret';
CREATE OR REPLACE FUNCTION sign_scan_code(
  p_community_id UUID,
  p_type TEXT,
  p_activity_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_comm communities%ROWTYPE;
  v_act activities%ROWTYPE;
  v_secret TEXT;
  v_ts BIGINT;
  v_pts INT;
  v_tok TEXT;
BEGIN
  IF p_type NOT IN ('visit', 'activity') THEN
    RETURN jsonb_build_object('error', 'Tipo inválido');
  END IF;

  SELECT * INTO v_comm FROM communities WHERE id = p_community_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Comunidad no encontrada');
  END IF;

  IF v_comm.auth_user_id IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  IF v_comm.is_withdrawn THEN
    RETURN jsonb_build_object('error', 'Tu comunidad ya no está activa.');
  END IF;

  -- An activity code names its activity, and may only be produced while that
  -- activity is running (spec 011, R10). Projecting a code that awards nothing
  -- produces a queue of people being refused, and the stand finds out from the
  -- complaints.
  IF p_type = 'activity' THEN
    IF p_activity_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Falta indicar la actividad');
    END IF;
    SELECT * INTO v_act FROM activities
    WHERE id = p_activity_id AND community_id = v_comm.id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('error', 'Actividad no encontrada');
    END IF;
    IF activity_state(v_act) = 'scheduled' THEN
      RETURN jsonb_build_object('error', 'Esta actividad todavía no ha iniciado.');
    END IF;
    IF activity_state(v_act) = 'finished' THEN
      RETURN jsonb_build_object('error', 'Esta actividad ya terminó.');
    END IF;
  ELSIF p_activity_id IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'Una visita no lleva actividad');
  END IF;

  SELECT value INTO v_secret FROM settings WHERE key = 'hmac_secret';
  IF v_secret IS NULL THEN
    RETURN jsonb_build_object('error', 'Secreto no configurado');
  END IF;

  v_ts := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_pts := scan_award(p_type, p_activity_id);
  v_tok := scan_signature(v_comm.id, p_activity_id, v_ts, p_type, v_secret);

  RETURN jsonb_build_object(
    'payload', jsonb_build_object(
      'sid', v_comm.id,
      'act', p_activity_id,
      'ts', v_ts,
      'type', p_type,
      'name', v_comm.name,
      'emoji', v_comm.emoji,
      'activityName', v_act.name,
      'tok', v_tok
    ),
    -- Shown so the stand can tell attendees what the code is worth. It is not
    -- signed and never read back: the award is recomputed when the scan lands.
    'points', v_pts,
    'shortCode', upper(substring(v_tok from 1 for 6)),
    'ts', v_ts
  );
END;
$fn$;

-- ---------------------------------------------------------------------------
-- 2. Validar QR y registrar el escaneo.
--
-- Toda la decisión ocurre acá. El cliente es público: lo que llega es entrada
-- no confiable, y el monto se recalcula siempre (hallazgo F3 del audit).
CREATE OR REPLACE FUNCTION validate_and_scan(
  p_encoded_payload TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_json JSONB;
  v_secret TEXT;
  v_community communities%ROWTYPE;
  v_activity activities%ROWTYPE;
  v_existing scans%ROWTYPE;
  v_elapsed INTERVAL;
  v_cooldown INTERVAL;

  v_type TEXT;
  v_activity_id UUID;
  v_qr_ts BIGINT;
  v_current_ts BIGINT;
  v_final_pts INT;
  v_participant_id UUID;
BEGIN
  -- El participante es SIEMPRE el llamador autenticado (nunca un parámetro).
  SELECT id INTO v_participant_id FROM participants
  WHERE auth_user_id = auth.uid()
  FOR UPDATE; -- serializa los escaneos del mismo participante: el cooldown de
              -- visitas re-evalúa contra lo ya confirmado (hallazgo F8)
  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'Regístrate para participar.');
  END IF;

  IF (SELECT is_removed FROM participants WHERE id = v_participant_id) THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'Tu perfil ya no está activo.');
  END IF;

  v_json := p_encoded_payload::JSONB;
  SELECT value INTO v_secret FROM settings WHERE key = 'hmac_secret';
  v_current_ts := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;

  -- =========================================================================
  -- 0) Seleccionar flujo: código manual o payload completo
  -- =========================================================================
  IF v_json ? 'short_code' THEN
    DECLARE
      v_short_code TEXT := upper(btrim(v_json->>'short_code'));
      v_found BOOLEAN := false;
      v_cand RECORD;
      v_window BIGINT;
    BEGIN
      -- Candidatos: el código de visita de cada comunidad, más el de cada
      -- actividad en curso. Se recorren recalculando la firma, nunca buscando
      -- por el valor tecleado: no hay nada que inyectar y un casi-acierto no
      -- revela nada (spec 003).
      FOR v_cand IN
        SELECT c.id AS community_id, NULL::UUID AS activity_id, 'visit' AS type
        FROM communities c
        UNION ALL
        SELECT a.community_id, a.id, 'activity'
        FROM activities a
        WHERE activity_state(a) = 'running'
      LOOP
        FOREACH v_window IN ARRAY ARRAY[v_current_ts, v_current_ts - 1] LOOP
          IF upper(substring(
               scan_signature(v_cand.community_id, v_cand.activity_id, v_window,
                              v_cand.type, v_secret)
               from 1 for 6)) = v_short_code
          THEN
            v_type := v_cand.type;
            v_activity_id := v_cand.activity_id;
            v_qr_ts := v_window;
            SELECT * INTO v_community FROM communities WHERE id = v_cand.community_id;
            v_found := true;
            EXIT;
          END IF;
        END LOOP;
        EXIT WHEN v_found;
      END LOOP;

      IF NOT v_found THEN
        RETURN jsonb_build_object('valid', false,
          'reason', 'Código manual inválido o caducado.');
      END IF;
    END;

  ELSE
    -- =======================================================================
    -- Flujo normal de QR
    -- =======================================================================
    v_type := COALESCE(v_json->>'type', 'visit');
    v_activity_id := NULLIF(v_json->>'act', '')::UUID;
    v_qr_ts := (v_json->>'ts')::BIGINT;

    -- A) Ventana temporal. Una hacia atrás por latencia de red; ninguna hacia
    --    adelante, porque solo puede venir de un reloj mal puesto o de un
    --    payload construido.
    IF (v_current_ts - v_qr_ts) > 1 OR (v_qr_ts > v_current_ts) THEN
      RETURN jsonb_build_object('valid', false,
        'reason', 'Código QR caducado, escanea el código actual del stand.');
    END IF;

    SELECT * INTO v_community FROM communities WHERE id = (v_json->>'sid')::UUID;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('valid', false, 'reason', 'Comunidad no encontrada');
    END IF;

    -- B) Integridad criptográfica.
    IF scan_signature(v_community.id, v_activity_id, v_qr_ts, v_type, v_secret)
       IS DISTINCT FROM (v_json->>'tok') THEN
      RETURN jsonb_build_object('valid', false,
        'reason', 'Código QR inválido o falsificado.');
    END IF;
  END IF;

  IF v_type NOT IN ('visit', 'activity') THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'Tipo de código inválido.');
  END IF;

  -- Un stand retirado deja de otorgar puntos, incluso con un código que ya
  -- estaba dando vueltas (spec 023, R16).
  IF v_community.is_withdrawn THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'Este stand ya no está participando.');
  END IF;

  -- =========================================================================
  -- C) Estado de la actividad (spec 019). Una actividad solo otorga puntos
  --    mientras está en curso, y eso se decide acá, no en la pantalla: un
  --    teléfono que todavía la muestra abierta, o un código capturado mientras
  --    lo estaba, tiene que ser rechazado igual.
  -- =========================================================================
  IF v_type = 'activity' THEN
    SELECT * INTO v_activity FROM activities
    WHERE id = v_activity_id AND community_id = v_community.id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('valid', false, 'reason', 'Actividad no encontrada');
    END IF;
    IF activity_state(v_activity) = 'scheduled' THEN
      RETURN jsonb_build_object('valid', false,
        'reason', 'Esta actividad todavía no ha iniciado.');
    END IF;
    IF activity_state(v_activity) = 'finished' THEN
      RETURN jsonb_build_object('valid', false, 'reason', 'Esta actividad ya terminó.');
    END IF;
  END IF;

  -- =========================================================================
  -- D) Cooldown y unicidad.
  --    Visitas: repetibles pasados 30 minutos. Lo bastante como para que
  --    quedarse parado frente a un código sea mal uso de una tarde, y lo
  --    bastante poco como para premiar volver más tarde de verdad.
  --    Actividades: una sola vez cada una, respaldado por el índice único
  --    parcial sobre (participant_id, activity_id).
  -- =========================================================================
  IF v_type = 'visit' THEN
    v_cooldown := make_interval(mins => (points_config()->>'visit_cooldown_minutes')::int);

    SELECT * INTO v_existing FROM scans
      WHERE participant_id = v_participant_id
      AND community_id = v_community.id
      AND type = 'visit'
      ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
      v_elapsed := now() - v_existing.created_at;
      IF v_elapsed < v_cooldown THEN
        RETURN jsonb_build_object('valid', false, 'reason',
          'Ya visitaste este stand. Espera ' ||
          CEIL(EXTRACT(EPOCH FROM (v_cooldown - v_elapsed)) / 60)::TEXT ||
          ' minuto(s) para volver a registrar una visita.');
      END IF;
    END IF;
  ELSE
    SELECT * INTO v_existing FROM scans
      WHERE participant_id = v_participant_id
      AND activity_id = v_activity_id
      LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object('valid', false,
        'reason', 'Ya participaste en esta actividad.');
    END IF;
  END IF;

  -- =========================================================================
  -- E) El monto lo decide el sistema, siempre.
  --    Con los valores fijos el payload ya no lleva puntos, así que no hay
  --    nada que inflar. El clamp se queda igual: quitar una defensa porque el
  --    llamador actual es confiable es exactamente cómo apareció el hallazgo
  --    F3 (constitución VI).
  -- =========================================================================
  v_final_pts := GREATEST(0, scan_award(v_type, v_activity_id));

  -- El índice único parcial es la puerta real contra dos escaneos simultáneos
  -- de la misma actividad; acá solo se traduce el rechazo a un mensaje.
  BEGIN
    INSERT INTO scans (participant_id, community_id, activity_id, points, type)
    VALUES (v_participant_id, v_community.id, v_activity_id, v_final_pts, v_type);
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('valid', false,
        'reason', 'Ya participaste en esta actividad.');
  END;

  UPDATE participants SET points = points + v_final_pts
  WHERE id = v_participant_id;

  RETURN jsonb_build_object(
    'valid', true,
    'points', v_final_pts,
    'type', v_type,
    'groupName', v_community.name,
    'groupEmoji', v_community.emoji,
    'activityName', v_activity.name
  );
END;
$fn$;

-- El canje vive en 54_fulfilment.sql desde el spec 018: lo confirma el stand al
-- entregar el premio, no el estudiante desde el catálogo.
