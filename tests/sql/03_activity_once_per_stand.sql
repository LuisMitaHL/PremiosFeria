-- An activity counts once per stand, for good. Visits are the repeatable
-- currency; activities are the reward for actually doing the thing the stand
-- runs, so a second one is meaningless.
--
-- The gate is the partial unique index scans_one_activity_per_stand, not the IF
-- in the RPC. The IF only writes the friendly message; the index is what holds
-- when two scans race (constitution VI).
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.signed_payload(p_sid UUID, p_ts BIGINT, p_pts INT, p_type TEXT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid, 'ts', p_ts, 'pts', p_pts, 'type', p_type,
    'tok', encode(
      hmac(p_sid || '|' || p_ts || '|' || p_pts || '|' || p_type,
           (SELECT value FROM settings WHERE key = 'hmac_secret'), 'sha256'),
      'hex')
  )::text
$fn$;

INSERT INTO communities (id, username, name, visit_points, activity_points, auth_user_id)
VALUES ('aaaa0003-0000-4000-8000-000000000001', 'test_activity_a', 'Activity Stand A', 10, 25,
        'aaaa0003-0000-4000-8000-000000000001'),
       ('aaaa0003-0000-4000-8000-000000000002', 'test_activity_b', 'Activity Stand B', 10, 30,
        'aaaa0003-0000-4000-8000-000000000002');

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0003-0000-4000-8000-000000000001', 'Activity Tester', 0,
        'bbbb0003-0000-4000-8000-000000000001');

DO $act$ BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0003-0000-4000-8000-000000000001","role":"authenticated"}', true);
END; $act$;

DO $test$
DECLARE
  v_a     UUID := 'aaaa0003-0000-4000-8000-000000000001';
  v_b     UUID := 'aaaa0003-0000-4000-8000-000000000002';
  v_who   UUID := 'bbbb0003-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_points INT;
  v_count INT;
BEGIN
  -- The first activity is awarded.
  v_res := validate_and_scan(pg_temp.signed_payload(v_a, v_now, 25, 'activity'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The first activity at a stand was rejected: %', v_res->>'reason';
  END IF;

  -- A second one at the same stand is refused, however long you wait: unlike a
  -- visit, there is no cooldown that eventually lets it through.
  v_res := validate_and_scan(pg_temp.signed_payload(v_a, v_now, 25, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A second activity at the same stand was accepted';
  END IF;

  UPDATE scans SET created_at = now() - INTERVAL '3 hours'
  WHERE participant_id = v_who AND community_id = v_a AND type = 'activity';

  v_res := validate_and_scan(pg_temp.signed_payload(v_a, v_now, 25, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity was accepted again three hours later: it is behaving like a visit';
  END IF;

  -- A different stand is unaffected. The rule is per stand, not per fair.
  v_res := validate_and_scan(pg_temp.signed_payload(v_b, v_now, 30, 'activity'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity at a second stand was rejected: %', v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 55 THEN
    RAISE EXCEPTION 'The balance is % after activities of 25 and 30', v_points;
  END IF;

  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = v_who AND type = 'activity';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'There are % activity scans on record instead of 2', v_count;
  END IF;
END;
$test$;

-- The structural gate, tested directly: even a caller that bypasses the RPC
-- entirely cannot record a second activity.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO scans (participant_id, community_id, points, type)
    VALUES ('bbbb0003-0000-4000-8000-000000000001',
            'aaaa0003-0000-4000-8000-000000000001', 25, 'activity');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A duplicate activity was inserted directly: the partial unique index is gone, so the rule now depends entirely on the RPC';
  END IF;
END;
$test$;

-- Visits must stay repeatable: the index is partial for a reason.
DO $test$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO scans (participant_id, community_id, points, type)
  VALUES ('bbbb0003-0000-4000-8000-000000000001',
          'aaaa0003-0000-4000-8000-000000000001', 10, 'visit');
  INSERT INTO scans (participant_id, community_id, points, type)
  VALUES ('bbbb0003-0000-4000-8000-000000000001',
          'aaaa0003-0000-4000-8000-000000000001', 10, 'visit');

  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = 'bbbb0003-0000-4000-8000-000000000001'
    AND community_id = 'aaaa0003-0000-4000-8000-000000000001'
    AND type = 'visit';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Repeat visits are being blocked: the uniqueness rule has leaked past activities';
  END IF;
END;
$test$;

ROLLBACK;
