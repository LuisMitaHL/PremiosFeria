-- 52_activities.sql — the activity lifecycle (spec 019).
--
-- Every rule here is enforced in the database, because the stand's screen is
-- public code on a device the stand controls (constitution III). The screen
-- draws the state; this file decides it.

-- ---------------------------------------------------------------------------
-- The state is DERIVED, never stored.
--
-- Nothing in this stack runs in the background: no scheduler, no job, no timer.
-- If the state were a column, something would have to go and change it, and an
-- activity nobody closed would keep awarding points until someone noticed. By
-- deriving it, "has this ended?" is a question answered at the moment it is
-- asked, and spec 019 R10 -- an activity finishes on its own when its duration
-- elapses, with nobody's screen open -- is simply true.
--
-- Taking the table type as its only argument also makes PostgREST expose it as
-- a computed column, so the screens read the same state the rules use.
CREATE OR REPLACE FUNCTION activity_state(a activities) RETURNS TEXT
LANGUAGE sql STABLE AS $fn$
  SELECT CASE
    WHEN a.started_at IS NULL THEN 'scheduled'
    WHEN a.finished_at IS NOT NULL THEN 'finished'
    WHEN now() >= a.started_at + make_interval(mins => a.duration_min) THEN 'finished'
    ELSE 'running'
  END
$fn$;

-- ---------------------------------------------------------------------------
-- At most three per community, for the whole event -- finished ones included.
--
-- A CHECK cannot count rows, so this is a trigger. The lock on the community
-- row is the point of it: without it, two inserts arriving together both read
-- a count of two and both succeed (constitution VI).
CREATE OR REPLACE FUNCTION activities_enforce_limit() RETURNS TRIGGER
LANGUAGE plpgsql AS $fn$
DECLARE
  v_count INT;
BEGIN
  PERFORM 1 FROM communities WHERE id = NEW.community_id FOR UPDATE;

  SELECT count(*) INTO v_count FROM activities WHERE community_id = NEW.community_id;
  IF v_count >= 3 THEN
    RAISE EXCEPTION 'Ya creaste el máximo de 3 actividades.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS activities_limit ON activities;
CREATE TRIGGER activities_limit
  BEFORE INSERT ON activities
  FOR EACH ROW EXECUTE FUNCTION activities_enforce_limit();

-- ---------------------------------------------------------------------------
-- Resolve the calling stand. Identity is never a parameter (constitution IV).
-- Una comunidad retirada no resuelve (spec 023, R15 y R16). Filtrarlo acá, en
-- vez de en cada función, es lo que hace que valga para todas a la vez: crear y
-- iniciar actividades, registrar premios, reponer stock y confirmar entregas.
CREATE OR REPLACE FUNCTION calling_community() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT id FROM communities WHERE auth_user_id = auth.uid() AND NOT is_withdrawn
$fn$;

-- ---------------------------------------------------------------------------
-- Create. The limits on the fields are CHECK constraints on the table; this
-- translates their rejection into a message a stand can act on.
CREATE OR REPLACE FUNCTION create_activity(
  p_name TEXT,
  p_description TEXT,
  p_estimated_start TIME,
  p_duration_min INT,
  p_is_main_event BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row activities%ROWTYPE;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    -- No hay stand que atribuir — justamente por eso se rechaza —, así que el
    -- asiento queda a nombre de quien haya llamado, sea quien sea (spec 024, R8).
    PERFORM audit(p_action => 'activity.create', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'activity', p_subject_label => btrim(p_name),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  BEGIN
    INSERT INTO activities (community_id, name, description, estimated_start,
                            duration_min, is_main_event)
    VALUES (v_community, btrim(p_name), btrim(p_description), p_estimated_start,
            p_duration_min, COALESCE(p_is_main_event, false))
    RETURNING * INTO v_row;
  EXCEPTION
    -- Los asientos de rechazo van en los manejadores y no dentro del bloque
    -- protegido: si el registro no se puede escribir, la excepción sale de la
    -- función y la acción falla, que es lo que exige R21.
    WHEN unique_violation THEN
      -- The only unique index an insert can hit is the one main event per
      -- community; a new activity is never started, so it cannot collide with
      -- the one-running index.
      v_error := 'Ya tienes un evento principal.';
      PERFORM audit(p_action => 'activity.create', p_outcome => 'refused',
                    p_actor_kind => 'stand', p_actor_id => v_community,
                    p_subject_kind => 'activity', p_subject_label => btrim(p_name),
                    p_reason => v_error);
      RETURN jsonb_build_object('error', v_error);
    WHEN check_violation THEN
      v_error := CASE
        WHEN SQLERRM LIKE '%máximo de 3%' THEN 'Ya creaste el máximo de 3 actividades.'
        WHEN SQLERRM LIKE '%name%'        THEN 'El nombre debe tener entre 3 y 40 caracteres.'
        WHEN SQLERRM LIKE '%description%' THEN 'La descripción no puede superar los 100 caracteres.'
        WHEN SQLERRM LIKE '%duration%'    THEN
          CASE WHEN COALESCE(p_duration_min, 0) < 1
            THEN 'La duración debe ser de al menos un minuto.'
            ELSE 'La duración no puede superar los 60 minutos.'
          END
        ELSE 'Datos inválidos.'
      END;
      PERFORM audit(p_action => 'activity.create', p_outcome => 'refused',
                    p_actor_kind => 'stand', p_actor_id => v_community,
                    p_subject_kind => 'activity', p_subject_label => btrim(p_name),
                    p_reason => v_error);
      RETURN jsonb_build_object('error', v_error);
  END;

  PERFORM audit(p_action => 'activity.create', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'activity', p_subject_id => v_row.id,
                p_subject_label => v_row.name);

  RETURN jsonb_build_object('activity', to_jsonb(v_row));
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Edit, only while scheduled.
--
-- Freezing on start is what keeps two attendees from being awarded different
-- amounts for the same activity: the field that matters is is_main_event, worth
-- 20 points (spec 019, R21 and R22).
CREATE OR REPLACE FUNCTION update_activity(
  p_id UUID,
  p_name TEXT,
  p_description TEXT,
  p_estimated_start TIME,
  p_duration_min INT,
  p_is_main_event BOOLEAN
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row activities%ROWTYPE;
  v_before JSONB;
  v_label TEXT;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = p_id AND community_id = v_community;
  IF NOT FOUND THEN
    PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'Actividad no encontrada');
    RETURN jsonb_build_object('error', 'Actividad no encontrada');
  END IF;

  -- Solo los campos que esta edición toca, nunca la fila entera: copiarla es
  -- como un hash o una huella terminan en el registro (spec 024, R9).
  v_before := jsonb_build_object(
    'name', v_row.name,
    'description', v_row.description,
    'estimated_start', v_row.estimated_start,
    'duration_min', v_row.duration_min,
    'is_main_event', v_row.is_main_event);
  v_label := v_row.name;

  IF activity_state(v_row) <> 'scheduled' THEN
    v_error := 'No puedes editar una actividad que ya inició.';
    PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => v_row.id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  BEGIN
    UPDATE activities
    SET name = btrim(p_name),
        description = btrim(p_description),
        estimated_start = p_estimated_start,
        duration_min = p_duration_min,
        is_main_event = COALESCE(p_is_main_event, false)
    -- Re-checking the state in the WHERE is what makes this safe against an
    -- edit racing a start: the loser updates nothing.
    WHERE id = p_id AND community_id = v_community AND started_at IS NULL
    RETURNING * INTO v_row;
  EXCEPTION
    WHEN unique_violation THEN
      v_error := 'Ya tienes un evento principal.';
      PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                    p_actor_kind => 'stand', p_actor_id => v_community,
                    p_subject_kind => 'activity', p_subject_id => p_id,
                    p_subject_label => v_label, p_before => v_before,
                    p_reason => v_error);
      RETURN jsonb_build_object('error', v_error);
    WHEN check_violation THEN
      v_error := 'Datos inválidos.';
      PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                    p_actor_kind => 'stand', p_actor_id => v_community,
                    p_subject_kind => 'activity', p_subject_id => p_id,
                    p_subject_label => v_label, p_before => v_before,
                    p_reason => v_error);
      RETURN jsonb_build_object('error', v_error);
  END;

  IF NOT FOUND THEN
    v_error := 'No puedes editar una actividad que ya inició.';
    PERFORM audit(p_action => 'activity.update', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  PERFORM audit(p_action => 'activity.update', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'activity', p_subject_id => v_row.id,
                p_subject_label => v_row.name, p_before => v_before);

  RETURN jsonb_build_object('activity', to_jsonb(v_row));
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Close any activity of this stand whose duration has elapsed.
--
-- This is the reconciliation between the derived state and the one-running
-- index. An activity past its duration IS finished as far as every rule is
-- concerned, but its row still matches
--   started_at IS NOT NULL AND finished_at IS NULL
-- so it still occupies the index. Without this, a stand whose activity expired
-- could never start another -- which would contradict R10, the whole reason the
-- state is derived. Called before anything that depends on that index.
CREATE OR REPLACE FUNCTION close_expired_activities(p_community UUID) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $fn$
  UPDATE activities
  SET finished_at = started_at + make_interval(mins => duration_min)
  WHERE community_id = p_community
    AND started_at IS NOT NULL
    AND finished_at IS NULL
    AND now() >= started_at + make_interval(mins => duration_min)
$fn$;

-- ---------------------------------------------------------------------------
-- Start. The estimated time is a hint to attendees and gates nothing
-- (spec 019, R27): the clock that matters starts here.
CREATE OR REPLACE FUNCTION start_activity(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row activities%ROWTYPE;
  v_before JSONB;
  v_label TEXT;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    PERFORM audit(p_action => 'activity.start', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- Serialise starts for this stand, so two taps cannot both pass the check
  -- below. The unique index is still the real gate; this makes the message
  -- friendly instead of a constraint error.
  PERFORM 1 FROM communities WHERE id = v_community FOR UPDATE;
  PERFORM close_expired_activities(v_community);

  SELECT * INTO v_row FROM activities WHERE id = p_id AND community_id = v_community;
  IF NOT FOUND THEN
    PERFORM audit(p_action => 'activity.start', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'Actividad no encontrada');
    RETURN jsonb_build_object('error', 'Actividad no encontrada');
  END IF;

  -- Iniciar cambia un solo campo, y el registro guarda ese campo y nada más.
  v_before := jsonb_build_object('started_at', v_row.started_at);
  v_label := v_row.name;

  IF activity_state(v_row) = 'running' THEN
    v_error := 'Esta actividad ya está en curso.';
  ELSIF activity_state(v_row) = 'finished' THEN
    v_error := 'Esta actividad ya terminó.';
  ELSIF EXISTS (
    SELECT 1 FROM activities a
    WHERE a.community_id = v_community AND activity_state(a) = 'running'
  ) THEN
    v_error := 'Termina la actividad en curso antes de iniciar otra.';
  END IF;

  IF v_error IS NOT NULL THEN
    PERFORM audit(p_action => 'activity.start', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => v_row.id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  BEGIN
    UPDATE activities SET started_at = now()
    WHERE id = p_id AND community_id = v_community AND started_at IS NULL
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    v_error := 'Termina la actividad en curso antes de iniciar otra.';
    PERFORM audit(p_action => 'activity.start', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END;

  IF NOT FOUND THEN
    v_error := 'Esta actividad ya inició.';
    PERFORM audit(p_action => 'activity.start', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  PERFORM audit(p_action => 'activity.start', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'activity', p_subject_id => v_row.id,
                p_subject_label => v_row.name, p_before => v_before);

  RETURN jsonb_build_object('activity', to_jsonb(v_row));
END;
$fn$;

-- ---------------------------------------------------------------------------
-- Finish early. There is no reopening: closing is how a stand says "this is
-- over", and an attendee told they were too late must not find out otherwise
-- (spec 019, R12).
CREATE OR REPLACE FUNCTION finish_activity(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row activities%ROWTYPE;
  v_before JSONB;
  v_label TEXT;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    PERFORM audit(p_action => 'activity.finish', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = p_id AND community_id = v_community;
  IF NOT FOUND THEN
    PERFORM audit(p_action => 'activity.finish', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => p_id,
                  p_reason => 'Actividad no encontrada');
    RETURN jsonb_build_object('error', 'Actividad no encontrada');
  END IF;

  v_before := jsonb_build_object('finished_at', v_row.finished_at);
  v_label := v_row.name;

  IF activity_state(v_row) = 'scheduled' THEN
    v_error := 'Esta actividad todavía no ha iniciado.';
  -- Comprobar activity_state y no solo finished_at: una actividad cuya
  -- duración venció ya terminó, aunque nadie la haya cerrado. Sin esto, el
  -- stand toca "terminar" sobre algo que acabó hace veinte minutos y se le
  -- responde que salió bien.
  ELSIF activity_state(v_row) = 'finished' THEN
    v_error := 'Esta actividad ya terminó.';
  END IF;

  IF v_error IS NOT NULL THEN
    PERFORM audit(p_action => 'activity.finish', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'activity', p_subject_id => v_row.id,
                  p_subject_label => v_label, p_before => v_before,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  -- LEAST keeps the recorded end from being later than the duration allowed,
  -- for an activity that expired between the check above and this write.
  UPDATE activities
  SET finished_at = LEAST(now(), started_at + make_interval(mins => duration_min))
  WHERE id = p_id AND community_id = v_community AND finished_at IS NULL
  RETURNING * INTO v_row;

  PERFORM audit(p_action => 'activity.finish', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'activity', p_subject_id => p_id,
                p_subject_label => v_label, p_before => v_before);

  RETURN jsonb_build_object('activity', to_jsonb(v_row));
END;
$fn$;

GRANT EXECUTE ON FUNCTION activity_state(activities) TO anon;
