-- An activity counts once per ACTIVITY, for good (spec 020, R8).
--
-- This rule changed. It used to be one activity per stand, which meant a stand
-- running three things could only ever award one of them. Now a stand publishes
-- up to three activities and an attendee may complete each of them once: the
-- guarantee moved from the stand to the activity, and the file is named after
-- the rule rather than after the old one.
--
-- The gate is the partial unique index scans_one_completion_per_activity on
-- (participant_id, activity_id), not the IF in the RPC. The IF only writes the
-- friendly message; the index is what holds when two scans race
-- (constitution VI).
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.activity_payload(p_sid UUID, p_act UUID, p_ts BIGINT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid, 'act', p_act, 'ts', p_ts, 'type', 'activity',
    'tok', scan_signature(p_sid, p_act, p_ts, 'activity',
                          (SELECT value FROM settings WHERE key = 'hmac_secret'))
  )::text
$fn$;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0003-0000-4000-8000-000000000001', 'test_activity_a', 'Activity Stand A',
        'aaaa0003-0000-4000-8000-000000000001'),
       ('aaaa0003-0000-4000-8000-000000000002', 'test_activity_b', 'Activity Stand B',
        'aaaa0003-0000-4000-8000-000000000002');

-- Stand A runs two things; only one of them may be in progress at a time, so
-- the first is started here and the second is started once the first is closed.
INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at)
VALUES ('dddd0003-0000-4000-8000-000000000001',
        'aaaa0003-0000-4000-8000-000000000001',
        'Taller principal', 'El evento grande del stand', '10:00', 45, true, now()),
       ('dddd0003-0000-4000-8000-000000000002',
        'aaaa0003-0000-4000-8000-000000000001',
        'Demostracion corta', 'Una demo de diez minutos', '12:00', 10, false, NULL),
       ('dddd0003-0000-4000-8000-000000000003',
        'aaaa0003-0000-4000-8000-000000000002',
        'Charla del stand B', 'Charla abierta', '11:00', 30, false, now());

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0003-0000-4000-8000-000000000001', 'Activity Tester', 0,
        'bbbb0003-0000-4000-8000-000000000001');

DO $act$ BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0003-0000-4000-8000-000000000001","role":"authenticated"}', true);
END; $act$;

DO $test$
DECLARE
  v_a      UUID := 'aaaa0003-0000-4000-8000-000000000001';
  v_b      UUID := 'aaaa0003-0000-4000-8000-000000000002';
  v_main   UUID := 'dddd0003-0000-4000-8000-000000000001';
  v_second UUID := 'dddd0003-0000-4000-8000-000000000002';
  v_other  UUID := 'dddd0003-0000-4000-8000-000000000003';
  v_who    UUID := 'bbbb0003-0000-4000-8000-000000000001';
  v_now    BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res    JSONB;
  v_points INT;
  v_count  INT;
BEGIN
  -- The first completion is awarded.
  v_res := validate_and_scan(pg_temp.activity_payload(v_a, v_main, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The first completion of a running activity was rejected: %',
      v_res->>'reason';
  END IF;

  -- A second attempt at the SAME activity is refused, and the attendee is told
  -- why in those words: they did nothing wrong (spec 020, R9).
  v_res := validate_and_scan(pg_temp.activity_payload(v_a, v_main, v_now));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The same activity was completed twice: an attendee can stand at one stand and repeat its main event for 30 points a time';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Ya participaste en esta actividad.' THEN
    RAISE EXCEPTION 'The refusal for a repeated activity reads "%", which is not what spec 020 R9 says the attendee must be told',
      v_res->>'reason';
  END IF;

  -- Unlike a visit there is no cooldown that eventually lets it through: three
  -- hours later it is still the same activity.
  UPDATE scans SET created_at = now() - INTERVAL '3 hours'
  WHERE participant_id = v_who AND activity_id = v_main;

  v_res := validate_and_scan(pg_temp.activity_payload(v_a, v_main, v_now));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity was completed again three hours later: it is behaving like a visit, and the whole event is farmable at one stand';
  END IF;

  -- A DIFFERENT activity of the SAME stand is awarded. This is the rule that
  -- changed: under the old one-per-stand index the stand's other two activities
  -- were worth nothing to anyone who had already completed one.
  UPDATE activities SET finished_at = now() WHERE id = v_main;
  UPDATE activities SET started_at = now() WHERE id = v_second;

  v_res := validate_and_scan(pg_temp.activity_payload(v_a, v_second, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A second, different activity at the same stand was rejected: %. The limit is one completion per activity, not per stand',
      v_res->>'reason';
  END IF;

  -- A different stand is unaffected.
  v_res := validate_and_scan(pg_temp.activity_payload(v_b, v_other, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity at a second stand was rejected: %', v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 50 THEN
    RAISE EXCEPTION 'The balance is % after a main event (30) and two ordinary activities (10 each)',
      v_points;
  END IF;

  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = v_who AND type = 'activity';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'There are % activity scans on record instead of 3', v_count;
  END IF;

  -- Every one of them names the activity it belongs to. Without that the rows
  -- are indistinguishable and the unique index has nothing to hold onto.
  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = v_who AND type = 'activity' AND activity_id IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION '% activity scans do not name their activity', v_count;
  END IF;
END;
$test$;

-- The structural gate, tested directly: even a caller that bypasses the RPC
-- entirely cannot record a second completion of the same activity.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO scans (participant_id, community_id, activity_id, points, type)
    VALUES ('bbbb0003-0000-4000-8000-000000000001',
            'aaaa0003-0000-4000-8000-000000000001',
            'dddd0003-0000-4000-8000-000000000001', 30, 'activity');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A duplicate completion was inserted directly: the partial unique index is gone, so the rule now depends entirely on the RPC and two scans arriving together will both be awarded';
  END IF;
END;
$test$;

-- And the gate cannot be walked around by omitting the activity id: an activity
-- scan must always name one, or it would fall outside the partial index and be
-- repeatable forever.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO scans (participant_id, community_id, activity_id, points, type)
    VALUES ('bbbb0003-0000-4000-8000-000000000001',
            'aaaa0003-0000-4000-8000-000000000001', NULL, 30, 'activity');
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'An activity scan with no activity id was accepted: such a row sits outside the one-completion index, so the same activity can be recorded again and again';
  END IF;

  v_blocked := false;
  BEGIN
    INSERT INTO scans (participant_id, community_id, activity_id, points, type)
    VALUES ('bbbb0003-0000-4000-8000-000000000001',
            'aaaa0003-0000-4000-8000-000000000001',
            'dddd0003-0000-4000-8000-000000000002', 10, 'visit');
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A visit was recorded against an activity: visits are repeatable, so this row would let an activity be completed once every cooldown';
  END IF;
END;
$test$;

-- Two different activities may of course coexist for the same attendee: the
-- index is on the pair, not on the participant.
DO $test$
DECLARE
  v_count INT;
BEGIN
  SELECT count(DISTINCT activity_id) INTO v_count FROM scans
  WHERE participant_id = 'bbbb0003-0000-4000-8000-000000000001' AND type = 'activity';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'The attendee has completions for % distinct activities instead of 3',
      v_count;
  END IF;
END;
$test$;

ROLLBACK;
