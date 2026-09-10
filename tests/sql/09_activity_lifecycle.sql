-- The activity lifecycle (spec 019).
--
-- An activity is a gate on awarding points, so every rule about it is part of
-- the point economy: how many a stand may have, which one is the main event,
-- when it opens, when it closes, and who may touch it. The stand console is
-- public code on a device the stand controls, so none of that may rest on a
-- disabled button.
--
-- Two properties carry most of the weight here:
--
--   * The state is DERIVED from started_at, finished_at and duration_min.
--     Nothing runs in the background in this stack, so an activity nobody
--     closes has to end by itself -- which is only true if "has this ended?" is
--     a question answered at the moment it is asked (R10).
--   * The limits are STRUCTURAL. Three per stand, one main event, one running
--     at a time: each is a trigger or a unique index, not an IF, so two taps
--     arriving together cannot both succeed (constitution VI).
--
-- Time is moved by rewinding started_at, never by waiting.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text,
                     true);
END;
$fn$;

-- Create and return the id, failing loudly if the creation was refused.
CREATE FUNCTION pg_temp.must_create(p_name TEXT, p_desc TEXT, p_start TIME,
                                    p_dur INT, p_main BOOLEAN)
RETURNS UUID LANGUAGE plpgsql AS $fn$
DECLARE
  v_res JSONB;
BEGIN
  v_res := create_activity(p_name, p_desc, p_start, p_dur, p_main);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Creating the activity "%" was refused: %', p_name, v_res->>'error';
  END IF;
  RETURN (v_res->'activity'->>'id')::uuid;
END;
$fn$;

-- Did the creation get refused, one way or another? A missing required field
-- surfaces as a raised error rather than a returned one, and both count as a
-- refusal as far as the rule is concerned: nothing was created.
CREATE FUNCTION pg_temp.creation_refused(p_name TEXT, p_desc TEXT, p_start TIME,
                                         p_dur INT, p_main BOOLEAN)
RETURNS BOOLEAN LANGUAGE plpgsql AS $fn$
DECLARE
  v_res JSONB;
BEGIN
  v_res := create_activity(p_name, p_desc, p_start, p_dur, p_main);
  RETURN v_res ? 'error';
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END;
$fn$;

INSERT INTO communities (id, username, name, auth_user_id)
SELECT ('aaaa0009-0000-4000-8000-00000000000' || n)::uuid,
       'test_lifecycle_' || n, 'Lifecycle Stand ' || n,
       ('aaaa0009-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 7) AS n;

-- ---------------------------------------------------------------------------
-- Creation: the fields, their limits, and what a new activity looks like.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0009-0000-4000-8000-000000000005';
  v_id    UUID;
  v_row   activities%ROWTYPE;
  v_res   JSONB;
  v_count INT;
BEGIN
  PERFORM pg_temp.act_as(v_stand);

  v_id := pg_temp.must_create('Taller de Rust', 'Introduccion practica al lenguaje',
                              '10:00', 30, true);
  SELECT * INTO v_row FROM activities WHERE id = v_id;

  IF v_row.community_id <> v_stand THEN
    RAISE EXCEPTION 'The activity was created under stand % instead of the caller''s own',
      v_row.community_id;
  END IF;
  IF activity_state(v_row) <> 'scheduled' THEN
    RAISE EXCEPTION 'A brand new activity is %, not scheduled: it is awarding points before the stand has started it',
      activity_state(v_row);
  END IF;
  IF v_row.started_at IS NOT NULL OR v_row.finished_at IS NOT NULL THEN
    RAISE EXCEPTION 'A brand new activity already carries a start or an end time';
  END IF;
  IF NOT v_row.is_main_event THEN
    RAISE EXCEPTION 'The activity was not stored as the main event, so it will award 10 instead of 30';
  END IF;

  -- Every field is required (R2). A missing one must not produce a half-made
  -- activity that awards points with no name on it.
  IF NOT pg_temp.creation_refused(NULL, 'Descripcion', '10:00', 10, false) THEN
    RAISE EXCEPTION 'An activity was created with no name';
  END IF;
  IF NOT pg_temp.creation_refused('Nombre valido', NULL, '10:00', 10, false) THEN
    RAISE EXCEPTION 'An activity was created with no description';
  END IF;
  IF NOT pg_temp.creation_refused('Nombre valido', 'Descripcion', NULL, 10, false) THEN
    RAISE EXCEPTION 'An activity was created with no estimated start time';
  END IF;
  IF NOT pg_temp.creation_refused('Nombre valido', 'Descripcion', '10:00', NULL, false) THEN
    RAISE EXCEPTION 'An activity was created with no duration, so nothing ever ends it';
  END IF;

  -- The lengths and the duration bounds are enforced where the data is stored
  -- (R2b), so submitting straight to the API gets the same answer as the form.
  v_res := create_activity('ab', 'Descripcion', '10:00', 10, false);
  IF v_res->>'error' IS DISTINCT FROM 'El nombre debe tener entre 3 y 40 caracteres.' THEN
    RAISE EXCEPTION 'A two-character name was answered with "%"', v_res->>'error';
  END IF;

  -- And the limit is on the trimmed name, or three spaces is a legal name.
  v_res := create_activity('  ab  ', 'Descripcion', '10:00', 10, false);
  IF v_res->>'error' IS DISTINCT FROM 'El nombre debe tener entre 3 y 40 caracteres.' THEN
    RAISE EXCEPTION 'A two-character name padded with spaces was accepted: "%"',
      v_res->>'error';
  END IF;

  v_res := create_activity(repeat('n', 41), 'Descripcion', '10:00', 10, false);
  IF v_res->>'error' IS DISTINCT FROM 'El nombre debe tener entre 3 y 40 caracteres.' THEN
    RAISE EXCEPTION 'A 41-character name was answered with "%"', v_res->>'error';
  END IF;

  v_res := create_activity('Nombre valido', repeat('d', 101), '10:00', 10, false);
  IF v_res->>'error' IS DISTINCT FROM 'La descripción no puede superar los 100 caracteres.' THEN
    RAISE EXCEPTION 'A 101-character description was answered with "%"', v_res->>'error';
  END IF;

  v_res := create_activity('Nombre valido', 'Descripcion', '10:00', 0, false);
  IF v_res->>'error' IS NULL OR v_res->>'error' NOT LIKE '%duraci%' THEN
    RAISE EXCEPTION 'A duration of zero was answered with "%", which does not tell the stand what to fix',
      v_res->>'error';
  END IF;

  v_res := create_activity('Nombre valido', 'Descripcion', '10:00', 61, false);
  IF v_res->>'error' IS NULL OR v_res->>'error' NOT LIKE '%duraci%' THEN
    RAISE EXCEPTION 'A duration of 61 minutes was answered with "%": a mistyped duration would leave an activity open past the end of the fair',
      v_res->>'error';
  END IF;

  -- The exact boundaries are legal, and this stand is now full at three.
  PERFORM pg_temp.must_create('abc', repeat('d', 100), '11:00', 1, false);
  PERFORM pg_temp.must_create(repeat('n', 40), 'Descripcion', '12:00', 60, false);

  SELECT count(*) INTO v_count FROM activities WHERE community_id = v_stand;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'The stand ended up with % activities instead of 3: an invalid one got in',
      v_count;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Three per stand, for the whole event -- finished ones included (R1, R6).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0009-0000-4000-8000-000000000001';
  v_first UUID;
  v_res   JSONB;
  v_count INT;
  v_blocked BOOLEAN := false;
BEGIN
  PERFORM pg_temp.act_as(v_stand);

  v_first := pg_temp.must_create('Actividad uno', 'La primera', '10:00', 10, true);
  PERFORM pg_temp.must_create('Actividad dos', 'La segunda', '11:00', 10, false);
  PERFORM pg_temp.must_create('Actividad tres', 'La tercera', '12:00', 10, false);

  v_res := create_activity('Actividad cuatro', 'La cuarta', '13:00', 10, false);
  IF v_res->>'error' IS DISTINCT FROM 'Ya creaste el máximo de 3 actividades.' THEN
    RAISE EXCEPTION 'A fourth activity was answered with "%" instead of the limit message',
      v_res->>'error';
  END IF;

  -- Running one and closing it does not buy another slot. This is what stops a
  -- stand cycling through activities and handing out points all afternoon.
  PERFORM start_activity(v_first);
  PERFORM finish_activity(v_first);

  v_res := create_activity('Actividad cuatro', 'La cuarta', '13:00', 10, false);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'Finishing an activity freed its slot: a stand can cycle through activities and award points without limit';
  END IF;

  SELECT count(*) INTO v_count FROM activities WHERE community_id = v_stand;
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'The stand has % activities instead of 3', v_count;
  END IF;

  -- The gate is structural, so a caller that bypasses the RPC hits it too.
  BEGIN
    INSERT INTO activities (community_id, name, description, estimated_start, duration_min)
    VALUES (v_stand, 'Actividad cuatro', 'Directo a la tabla', '13:00', 10);
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A fourth activity was inserted directly: the limit lives only in the RPC, so two creations arriving together will both get in';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- One main event per stand (R4, and spec 020 R7: it is worth 20 extra points).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0009-0000-4000-8000-000000000004';
  v_other UUID;
  v_res   JSONB;
  v_count INT;
  v_blocked BOOLEAN := false;
BEGIN
  PERFORM pg_temp.act_as(v_stand);

  PERFORM pg_temp.must_create('Evento principal', 'El grande', '10:00', 30, true);
  v_other := pg_temp.must_create('Actividad menor', 'Una mas', '11:00', 10, false);

  v_res := create_activity('Otro principal', 'Tambien grande', '12:00', 30, true);
  IF v_res->>'error' IS DISTINCT FROM 'Ya tienes un evento principal.' THEN
    RAISE EXCEPTION 'A second main event was answered with "%": without the limit every stand marks all three as main events and the distinction is gone',
      v_res->>'error';
  END IF;

  -- Nor by promoting an existing one afterwards.
  v_res := update_activity(v_other, 'Actividad menor', 'Una mas', '11:00', 10, true);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An ordinary activity was promoted to main event while the stand already had one';
  END IF;

  SELECT count(*) INTO v_count FROM activities
  WHERE community_id = v_stand AND is_main_event;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'The stand has % main events instead of 1, so its activities are worth up to % points',
      v_count, v_count * 30;
  END IF;

  BEGIN
    INSERT INTO activities (community_id, name, description, estimated_start,
                            duration_min, is_main_event)
    VALUES (v_stand, 'Principal directo', 'Directo a la tabla', '13:00', 30, true);
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A second main event was inserted directly: the one-main-event rule is not an index, so two of them can be created at once';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Starting, finishing, and finishing by itself.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0009-0000-4000-8000-000000000002';
  v_one   UUID;
  v_two   UUID;
  v_three UUID;
  v_row   activities%ROWTYPE;
  v_res   JSONB;
  v_blocked BOOLEAN := false;
BEGIN
  PERFORM pg_temp.act_as(v_stand);

  -- An estimated start in the future must not gate anything: it is information
  -- for attendees, never a condition (R9, R27).
  v_one   := pg_temp.must_create('Primera', 'La primera', '23:59', 10, true);
  v_two   := pg_temp.must_create('Segunda', 'La segunda', '00:01', 10, false);
  v_three := pg_temp.must_create('Tercera', 'La tercera', '12:00', 10, false);

  -- The transitions only ever go scheduled to running to finished (R14), so
  -- there is nothing to close before it has started.
  v_res := finish_activity(v_one);
  IF v_res->>'error' IS DISTINCT FROM 'Esta actividad todavía no ha iniciado.' THEN
    RAISE EXCEPTION 'Finishing an activity that never started was answered with "%"',
      v_res->>'error';
  END IF;

  v_res := start_activity(v_one);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A scheduled activity could not be started: %. The estimated time is a hint, not a gate',
      v_res->>'error';
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = v_one;
  IF activity_state(v_row) <> 'running' THEN
    RAISE EXCEPTION 'A just-started activity is %, not running', activity_state(v_row);
  END IF;
  IF v_row.started_at IS NULL THEN
    RAISE EXCEPTION 'A started activity has no start time, so nothing can ever end it';
  END IF;

  -- Only one at a time (R13): a stand projects one code and attends one thing.
  v_res := start_activity(v_two);
  IF v_res->>'error' IS DISTINCT FROM 'Termina la actividad en curso antes de iniciar otra.' THEN
    RAISE EXCEPTION 'Starting a second activity while one was running was answered with "%"',
      v_res->>'error';
  END IF;

  -- And structurally, for two taps arriving together.
  BEGIN
    UPDATE activities SET started_at = now() WHERE id = v_two;
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Two activities of the same stand can be running at once: "happening now" stops meaning anything and two codes award points at the same time';
  END IF;

  -- Finishing early stops it immediately (R11), and the record says when.
  v_res := finish_activity(v_one);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A running activity could not be finished early: %', v_res->>'error';
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = v_one;
  IF activity_state(v_row) <> 'finished' THEN
    RAISE EXCEPTION 'An activity closed by its stand is still %', activity_state(v_row);
  END IF;
  IF v_row.finished_at IS NULL THEN
    RAISE EXCEPTION 'A finished activity has no end time on record';
  END IF;

  -- There is no reopening (R12). An attendee told they were too late must not
  -- find out they were not.
  v_res := start_activity(v_one);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A finished activity was started again: everyone who was turned away can come back and be awarded after all';
  END IF;
  SELECT * INTO v_row FROM activities WHERE id = v_one;
  IF activity_state(v_row) <> 'finished' THEN
    RAISE EXCEPTION 'A finished activity went back to %', activity_state(v_row);
  END IF;

  -- Closing the first one frees the slot for the second.
  v_res := start_activity(v_two);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The next activity could not be started after the previous one closed: %',
      v_res->>'error';
  END IF;

  -- It now ends by itself once its ten minutes are up, with nobody's screen
  -- open and nothing running in the background (R10). Time is moved by
  -- rewinding the start, not by waiting.
  UPDATE activities SET started_at = now() - INTERVAL '10 minutes 1 second' WHERE id = v_two;
  SELECT * INTO v_row FROM activities WHERE id = v_two;
  IF activity_state(v_row) <> 'finished' THEN
    RAISE EXCEPTION 'An activity whose ten minutes ran out is still %: nothing in this stack runs in the background, so an activity nobody closes would keep awarding points all day',
      activity_state(v_row);
  END IF;
  IF v_row.finished_at IS NOT NULL THEN
    RAISE EXCEPTION 'The expired activity was closed by a write rather than derived, so the state depends on something having run';
  END IF;

  -- One second before the duration is up it is still running: the boundary is
  -- the duration, not "roughly".
  UPDATE activities SET started_at = now() - INTERVAL '9 minutes 59 seconds' WHERE id = v_two;
  SELECT * INTO v_row FROM activities WHERE id = v_two;
  IF activity_state(v_row) <> 'running' THEN
    RAISE EXCEPTION 'An activity is % one second before its duration is up: attendees still in the room are being refused',
      activity_state(v_row);
  END IF;

  -- An expired activity no longer holds the stand's one running slot, or a
  -- stand whose activity ran out could never open another one.
  UPDATE activities SET started_at = now() - INTERVAL '10 minutes 1 second' WHERE id = v_two;
  v_res := start_activity(v_three);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A stand could not start its next activity after the previous one ran out of time: %',
      v_res->>'error';
  END IF;

  -- And closing something that already expired must not extend it past the
  -- duration its attendees were promised.
  SELECT * INTO v_row FROM activities WHERE id = v_two;
  IF v_row.finished_at IS NOT NULL
     AND v_row.finished_at > v_row.started_at + make_interval(mins => v_row.duration_min) THEN
    RAISE EXCEPTION 'An expired activity was recorded as ending after its duration, at %',
      v_row.finished_at;
  END IF;

  -- Something already closed cannot be closed a second time.
  v_res := finish_activity(v_one);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An activity that was already finished was finished again';
  END IF;
END;
$test$;

-- Nothing may skip the middle state either: an end with no start is refused by
-- the table itself.
DO $test$
DECLARE
  v_scheduled UUID;
  v_blocked BOOLEAN := false;
BEGIN
  SELECT id INTO v_scheduled FROM activities
  WHERE community_id = 'aaaa0009-0000-4000-8000-000000000005' AND started_at IS NULL
  LIMIT 1;
  IF v_scheduled IS NULL THEN
    RAISE EXCEPTION 'This assertion needs a scheduled activity and there is none left to use';
  END IF;

  BEGIN
    UPDATE activities SET finished_at = now() WHERE id = v_scheduled;
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'An activity was finished without ever having started: the state can jump from scheduled straight to finished';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Editable only while scheduled (R20, R21, R22).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0009-0000-4000-8000-000000000003';
  v_id    UUID;
  v_row   activities%ROWTYPE;
  v_res   JSONB;
BEGIN
  PERFORM pg_temp.act_as(v_stand);
  v_id := pg_temp.must_create('Nombre inicial', 'Descripcion inicial', '10:00', 10, false);

  v_res := update_activity(v_id, 'Nombre corregido', 'Descripcion corregida', '10:30', 20, true);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A scheduled activity could not be edited: %', v_res->>'error';
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = v_id;
  IF v_row.name <> 'Nombre corregido' OR v_row.duration_min <> 20 OR NOT v_row.is_main_event THEN
    RAISE EXCEPTION 'The edit did not take: name %, duration %, main event %',
      v_row.name, v_row.duration_min, v_row.is_main_event;
  END IF;

  -- The limits apply to an edit as well.
  v_res := update_activity(v_id, 'ab', 'Descripcion corregida', '10:30', 20, true);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A two-character name got in through the edit path';
  END IF;

  -- From the moment it starts, every field is frozen. The one that matters is
  -- is_main_event, worth 20 points: without this, the attendee who took part at
  -- the start and the one who took part at the end are awarded differently for
  -- the same activity.
  PERFORM start_activity(v_id);
  v_res := update_activity(v_id, 'Otro nombre', 'Otra descripcion', '11:00', 30, false);
  IF v_res->>'error' IS DISTINCT FROM 'No puedes editar una actividad que ya inició.' THEN
    RAISE EXCEPTION 'Editing a running activity was answered with "%"', v_res->>'error';
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = v_id;
  IF v_row.name <> 'Nombre corregido' OR NOT v_row.is_main_event THEN
    RAISE EXCEPTION 'A running activity was edited anyway: it is now "%" and main event %, so two attendees can be awarded different amounts for the same thing',
      v_row.name, v_row.is_main_event;
  END IF;

  -- And once finished it stays frozen.
  PERFORM finish_activity(v_id);
  v_res := update_activity(v_id, 'Otro nombre', 'Otra descripcion', '11:00', 30, false);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A finished activity was edited';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A stand may only ever act on its own activities (constitution IV).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_owner    UUID := 'aaaa0009-0000-4000-8000-000000000006';
  v_intruder UUID := 'aaaa0009-0000-4000-8000-000000000007';
  v_id       UUID;
  v_row      activities%ROWTYPE;
  v_res      JSONB;
  v_count    INT;
BEGIN
  PERFORM pg_temp.act_as(v_owner);
  v_id := pg_temp.must_create('Actividad propia', 'Del stand seis', '10:00', 30, true);

  -- A stand with no activities of its own is a perfectly normal stand (R3).
  PERFORM pg_temp.act_as(v_intruder);
  SELECT count(*) INTO v_count FROM activities WHERE community_id = v_intruder;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'A stand that created nothing has % activities', v_count;
  END IF;

  v_res := start_activity(v_id);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'One stand started another stand''s activity, which is the moment its code starts awarding points';
  END IF;

  v_res := update_activity(v_id, 'Secuestrada', 'Editada por otro', '10:00', 30, true);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'One stand edited another stand''s activity';
  END IF;

  PERFORM pg_temp.act_as(v_owner);
  PERFORM start_activity(v_id);

  PERFORM pg_temp.act_as(v_intruder);
  v_res := finish_activity(v_id);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'One stand closed another stand''s running activity, cutting off its attendees';
  END IF;

  SELECT * INTO v_row FROM activities WHERE id = v_id;
  IF activity_state(v_row) <> 'running' OR v_row.name <> 'Actividad propia' THEN
    RAISE EXCEPTION 'The victim activity is now % and named "%"',
      activity_state(v_row), v_row.name;
  END IF;

  -- The intruder's own creation lands under the intruder, never under the id
  -- it was aiming at: the owner is resolved from the session, not from input.
  PERFORM pg_temp.must_create('Actividad ajena', 'Del stand siete', '10:00', 10, false);
  SELECT count(*) INTO v_count FROM activities WHERE community_id = v_owner;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'The victim stand now has % activities', v_count;
  END IF;
END;
$test$;

ROLLBACK;
