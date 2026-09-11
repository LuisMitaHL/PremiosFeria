-- 54_fulfilment.sql — the in-person exchange (spec 018).
--
-- This is the only place in the system where points are spent, so it is the
-- only place they can be stolen. Two things carry that weight:
--
--   * The claim code is the one identifier the system accepts as "who". Every
--     safeguard sits on it: single use, short life, one at a time, unguessable.
--   * The exchange is one indivisible step. Balance, stock, the duplicate check
--     and the code are verified and changed together or not at all.

-- Sesenta segundos de tolerancia desde la última vez que la pantalla preguntó.
-- La decisión fue que el código vive "hasta que se use o se cierre el modal",
-- pero cerrar el navegador, bloquear el teléfono o perder señal no son ninguna
-- de esas cosas, y sin esto quedaría un código vivo sin nada que lo termine.
-- Atarlo al propio sondeo es lo que hace exigible la regla; el minuto es para
-- que un teléfono que se bloquea y despierta no pierda su código.
CREATE OR REPLACE FUNCTION claim_code_grace() RETURNS INTERVAL
LANGUAGE sql IMMUTABLE AS $fn$ SELECT INTERVAL '60 seconds' $fn$;

-- Alfabeto sin los caracteres que se confunden al leerlos de una pantalla y
-- teclearlos en otra, en un salón ruidoso: O/0, I/1/L. Cada ambigüedad es un
-- intento fallido delante de una fila.
CREATE OR REPLACE FUNCTION generate_claim_code() RETURNS TEXT
LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE
  v_alphabet TEXT := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_code TEXT := '';
  v_byte INT;
BEGIN
  -- De una fuente criptográfica, nunca de un id ni de un reloj: un código
  -- derivado de la identidad del estudiante deja gastar los puntos de alguien
  -- que jamás pasó por tu stand (spec 018, R7).
  FOR i IN 1..6 LOOP
    v_byte := get_byte(gen_random_bytes(1), 0);
    v_code := v_code || substr(v_alphabet, (v_byte % length(v_alphabet)) + 1, 1);
  END LOOP;
  RETURN v_code;
END;
$fn$;

CREATE OR REPLACE FUNCTION claim_code_is_live(c claim_codes) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $fn$
  SELECT c.closed_at IS NULL AND c.last_seen_at > now() - claim_code_grace()
$fn$;

-- ---------------------------------------------------------------------------
-- El estudiante pide un código. No compromete nada: ni puntos, ni stock, ni
-- premio. Por eso un canje abandonado no deja stock retenido y no hay ningún
-- vencimiento de reserva que ajustar (spec 018, R6).
CREATE OR REPLACE FUNCTION issue_claim_code()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_participant participants%ROWTYPE;
  v_existing claim_codes%ROWTYPE;
  v_code TEXT;
BEGIN
  SELECT * INTO v_participant FROM participants WHERE auth_user_id = auth.uid()
  FOR UPDATE;
  IF NOT FOUND THEN
    PERFORM audit(p_action => 'claim.issue_code', p_outcome => 'refused',
                  p_actor_kind => audit_actor(),
                  p_reason => 'Regístrate para participar.');
    RETURN jsonb_build_object('error', 'Regístrate para participar.');
  END IF;

  -- Si ya hay uno vivo, se devuelve ese mismo.
  --
  -- La regla es "como mucho un código vivo por participante", y devolver el que
  -- ya existe la cumple igual que emitir otro. La diferencia importa por dos
  -- razones. Una: dos peticiones que se cruzan -- una pantalla que se vuelve a
  -- montar, un toque doble- emitían dos códigos, y el que quedaba abierto no
  -- era necesariamente el que se estaba mostrando; el estudiante enseñaba un
  -- código muerto. Dos: reabrir la pantalla mientras el estudiante ya le está
  -- mostrando el código a alguien no debería invalidárselo.
  --
  -- Un código que ya venció sí se reemplaza: dejó de estar vivo.
  SELECT * INTO v_existing FROM claim_codes
  WHERE participant_id = v_participant.id AND closed_at IS NULL
  FOR UPDATE;

  IF FOUND AND claim_code_is_live(v_existing) THEN
    UPDATE claim_codes SET last_seen_at = now() WHERE id = v_existing.id;
    RETURN jsonb_build_object('code', v_existing.code, 'points', v_participant.points);
  END IF;

  UPDATE claim_codes SET closed_at = now(), closed_reason = 'replaced'
  WHERE participant_id = v_participant.id AND closed_at IS NULL;

  LOOP
    v_code := generate_claim_code();
    BEGIN
      INSERT INTO claim_codes (participant_id, code) VALUES (v_participant.id, v_code);
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      -- Colisión con otro código abierto: se reintenta. Con 31^6 combinaciones
      -- y unos pocos vivos a la vez, esto no ocurre en la práctica.
    END;
  END LOOP;

  -- El asiento dice que se emitio un codigo, nunca cual: un codigo de canje en
  -- el registro es la capacidad de gastar los puntos de otro, y el registro lo
  -- lee el organizador en una pantalla abierta todo el dia (R9).
  --
  -- Devolver un codigo que ya estaba vivo no pasa por aca a proposito: no se
  -- emitio nada, y una pantalla que se vuelve a montar llenaria el registro de
  -- emisiones que no ocurrieron.
  PERFORM audit(p_action => 'claim.issue_code', p_outcome => 'ok',
                p_actor_kind => 'participant', p_actor_id => v_participant.id,
                p_subject_kind => 'participant', p_subject_id => v_participant.id,
                p_subject_label => v_participant.name);

  RETURN jsonb_build_object('code', v_code, 'points', v_participant.points);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- La pantalla del estudiante pregunta por SU propio código, resuelto desde la
-- sesión: nunca se acepta un identificador (constitución IV). Cada consulta
-- renueva la tolerancia, que es lo que mantiene vivo el código.
CREATE OR REPLACE FUNCTION poll_my_claim_code()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_participant participants%ROWTYPE;
  v_row claim_codes%ROWTYPE;
  v_reward TEXT;
BEGIN
  SELECT * INTO v_participant FROM participants WHERE auth_user_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Regístrate para participar.');
  END IF;

  SELECT * INTO v_row FROM claim_codes
  WHERE participant_id = v_participant.id
  ORDER BY issued_at DESC LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('state', 'none');
  END IF;

  IF v_row.closed_reason = 'used' THEN
    SELECT r.name INTO v_reward
    FROM claimed_rewards cr JOIN rewards r ON r.id = cr.reward_id
    WHERE cr.participant_id = v_participant.id
    ORDER BY cr.claimed_at DESC LIMIT 1;

    RETURN jsonb_build_object('state', 'used', 'reward', v_reward,
                              'points', v_participant.points);
  END IF;

  IF NOT claim_code_is_live(v_row) THEN
    RETURN jsonb_build_object('state', 'expired');
  END IF;

  UPDATE claim_codes SET last_seen_at = now() WHERE id = v_row.id;
  RETURN jsonb_build_object('state', 'live', 'code', v_row.code,
                            'points', v_participant.points);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- El stand confirma la entrega. Acá se paga.
--
-- Todo o nada: se verifica que el código esté vivo, que el premio sea de este
-- stand, que el estudiante no lo haya canjeado ya, que le alcance y que quede
-- stock; y se descuenta, se descuenta, se registra y se consume el código, en
-- un solo paso. Lo que esto evita es un premio entregado sin cobrar, o puntos
-- cobrados por un premio que se quedó en la mesa.
--
-- Los pre-chequeos de abajo solo escriben mensajes accionables para el stand.
-- La puerta real son los UPDATE condicionales, igual que antes: la condición
-- vive en el WHERE, así que dos confirmaciones simultáneas se serializan en el
-- lock de la fila y la perdedora ve 0 filas.
-- Los rechazos de la entrega pasan todos por aca para que el motivo registrado
-- sea literalmente el devuelto. El sujeto es el premio: es lo que el
-- organizador busca cuando alguien reclama que no se lo entregaron.
CREATE OR REPLACE FUNCTION handover_refused(
  p_community UUID, p_reward UUID, p_reward_name TEXT, p_reason TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  PERFORM audit(
    p_action => 'claim.handover', p_outcome => 'refused',
    p_actor_kind => CASE WHEN p_community IS NULL THEN audit_actor() ELSE 'stand' END,
    p_actor_id => p_community,
    p_subject_kind => CASE WHEN p_reward IS NULL THEN NULL ELSE 'reward' END,
    p_subject_id => p_reward,
    p_subject_label => p_reward_name,
    p_reason => p_reason);
  RETURN jsonb_build_object('success', false, 'reason', p_reason);
END;
$fn$;

CREATE OR REPLACE FUNCTION confirm_handover(p_code TEXT, p_reward_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row claim_codes%ROWTYPE;
  v_participant participants%ROWTYPE;
  v_reward rewards%ROWTYPE;
  v_new_points INT;
  v_fallo TEXT;
BEGIN
  IF v_community IS NULL THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'No autorizado');
  END IF;

  -- Un stand solo entrega lo que tiene en su mesa. Se comprueba antes que el
  -- código, para no confirmarle a nadie que un código existe mientras busca un
  -- premio ajeno.
  SELECT * INTO v_reward FROM rewards
  WHERE id = p_reward_id AND community_id = v_community;
  IF NOT FOUND THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Solo puedes entregar premios de tu stand.');
  END IF;
  IF v_reward.is_withdrawn THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Este premio ya no está disponible.');
  END IF;

  SELECT * INTO v_row FROM claim_codes
  WHERE code = upper(btrim(p_code)) AND closed_at IS NULL
  FOR UPDATE;
  IF NOT FOUND OR NOT claim_code_is_live(v_row) THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Código inválido o vencido. Pide al estudiante que lo genere de nuevo.');
  END IF;

  SELECT * INTO v_participant FROM participants WHERE id = v_row.participant_id FOR UPDATE;

  -- Las dos sanciones del spec 022, comprobadas donde se decide el canje y no
  -- en la pantalla del stand. El motivo real se dice tal cual: decirle a un
  -- stand que faltan puntos cuando en realidad esta bloqueado lo manda a
  -- discutir con la persona equivocada.
  IF v_participant.is_removed THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Este estudiante ya no participa en el evento.');
  END IF;
  IF v_participant.claims_barred THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Este estudiante no puede canjear premios.');
  END IF;

  IF EXISTS (SELECT 1 FROM claimed_rewards
             WHERE participant_id = v_participant.id AND reward_id = p_reward_id) THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Este estudiante ya canjeó este premio.');
  END IF;

  IF v_participant.points < v_reward.cost THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Le faltan ' || (v_reward.cost - v_participant.points)::TEXT ||
                ' puntos para este premio.');
  END IF;

  IF v_reward.stock <= 0 THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, 'Ya no quedan unidades de este premio.');
  END IF;

  BEGIN
    UPDATE rewards SET stock = stock - 1
    WHERE id = p_reward_id AND stock > 0;
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', 'Ya no quedan unidades de este premio.';
    END IF;

    UPDATE participants SET points = points - v_reward.cost
    WHERE id = v_participant.id AND points >= v_reward.cost;
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', 'Los puntos del estudiante cambiaron, inténtalo de nuevo.';
    END IF;

    INSERT INTO claimed_rewards (participant_id, reward_id, confirmed_by)
    VALUES (v_participant.id, p_reward_id, v_community);

    -- El código se consume en el mismo paso. Si algo falla, esto se revierte
    -- con lo demás y el código sigue sirviendo (spec 018, R15).
    UPDATE claim_codes SET closed_at = now(), closed_reason = 'used'
    WHERE id = v_row.id AND closed_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', 'Código inválido o vencido. Pide al estudiante que lo genere de nuevo.';
    END IF;
  EXCEPTION
    WHEN unique_violation THEN
      v_fallo := 'Este estudiante ya canjeó este premio.';
    WHEN OTHERS THEN
      v_fallo := SQLERRM;
  END;

  -- Fuera del bloque a proposito. Ese WHEN OTHERS atrapa cualquier cosa, asi
  -- que un audit() ahi dentro convertiria un fallo al registrar en un rechazo
  -- corriente y el stand leeria un motivo inventado: justo lo que R21 prohibe.
  IF v_fallo IS NOT NULL THEN
    RETURN handover_refused(v_community, p_reward_id, v_reward.name, v_fallo);
  END IF;

  SELECT points INTO v_new_points FROM participants WHERE id = v_participant.id;

  -- Lo que valian los puntos y el stock ANTES de pagarlos: sin eso el asiento
  -- dice que hubo una entrega, pero no a costa de que (R7).
  PERFORM audit(p_action => 'claim.handover', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'reward', p_subject_id => p_reward_id,
                p_subject_label => v_reward.name,
                p_before => jsonb_build_object('points', v_participant.points,
                                               'stock', v_reward.stock),
                p_detail => jsonb_build_object('participant', v_participant.name,
                                               'participantId', v_participant.id,
                                               'cost', v_reward.cost,
                                               'newPoints', v_new_points));

  RETURN jsonb_build_object(
    'success', true,
    'participant', v_participant.name,
    'reward', v_reward.name,
    'cost', v_reward.cost,
    'newPoints', v_new_points
  );
END;
$fn$;

-- claim_reward queda eliminada: el canje ya no lo hace el estudiante desde el
-- catálogo, sino el stand al entregar el premio (spec 018). Dejarla sería dejar
-- un segundo camino para gastar puntos, sin stand y sin entrega.
DROP FUNCTION IF EXISTS claim_reward(UUID);

-- Ayudante interno, no endpoint: ver la nota en 45_audit.sql.
REVOKE ALL ON FUNCTION handover_refused(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
DO $revoke$
DECLARE v_roles TEXT;
BEGIN
  SELECT string_agg(quote_ident(rolname), ', ' ORDER BY rolname) INTO v_roles
  FROM pg_roles WHERE rolname IN ('anon', 'authenticated');
  IF v_roles IS NOT NULL THEN
    EXECUTE format('REVOKE ALL ON FUNCTION public.handover_refused(UUID, UUID, TEXT, TEXT) FROM %s', v_roles);
  END IF;
END;
$revoke$;
