-- The system decides the amount. Always.
--
-- There are no configurable ceilings any more, because there are no
-- configurable values: a visit is worth 10 everywhere, a main event 30 and any
-- other activity 10 (spec 020, R1 to R3, R6, R10). A stand cannot raise its own
-- rate, so the old test -- that a stand could not set itself above a cap -- is
-- testing a control that no longer has anything to control.
--
-- What is left is the rule that actually protects the economy: the client is
-- public, so the payload it presents is untrusted input, and whatever numbers
-- arrive in it, the amount written is the one the rule says. That defence stays
-- even though the payload no longer carries an amount at all -- removing a
-- defence because the current caller is trusted is exactly how audit finding F3
-- happened (constitution VI).
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0004-0000-4000-8000-000000000001', 'test_award', 'Award Stand',
        'aaaa0004-0000-4000-8000-000000000001');

INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at)
VALUES ('dddd0004-0000-4000-8000-000000000001',
        'aaaa0004-0000-4000-8000-000000000001',
        'Evento principal', 'La actividad grande del stand', '10:00', 60, true, now());

INSERT INTO participants (id, name, points, auth_user_id)
SELECT ('bbbb0004-0000-4000-8000-00000000000' || n)::uuid,
       'Award Tester ' || n, 0,
       ('bbbb0004-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 4) AS n;

-- A tampered payload has to be signed to get past the HMAC check at all, so
-- this models the worst case: an attacker who has somehow obtained the secret.
-- The extra fields it carries are the ones an old client used to send, plus
-- whatever else a forger might try. None of them is signed, and none of them is
-- read.
CREATE FUNCTION pg_temp.tampered_payload(p_sid UUID, p_act UUID, p_ts BIGINT,
                                         p_type TEXT, p_extra JSONB)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT (jsonb_build_object(
    'sid', p_sid, 'act', p_act, 'ts', p_ts, 'type', p_type,
    'tok', scan_signature(p_sid, p_act, p_ts, p_type,
                          (SELECT value FROM settings WHERE key = 'hmac_secret'))
  ) || p_extra)::text
$fn$;

-- The constants themselves. Reward costs and the whole leaderboard were set
-- against these four numbers, so a change here is a change to the economy and
-- has to be a deliberate deployment, not a surprise.
DO $test$
DECLARE
  v_cfg JSONB := points_config();
BEGIN
  IF (v_cfg->>'visit')::int <> 10
     OR (v_cfg->>'activity_main')::int <> 30
     OR (v_cfg->>'activity_other')::int <> 10
     OR (v_cfg->>'visit_cooldown_minutes')::int <> 30 THEN
    RAISE EXCEPTION 'points_config() is %, not the visit 10 / main event 30 / other activity 10 / cooldown 30 the fair was priced with',
      v_cfg::text;
  END IF;
END;
$test$;

-- No stand may hold an award value. The columns that used to carry them are
-- gone, and a stand admin has nothing left to raise.
DO $test$
DECLARE
  v_cols TEXT;
BEGIN
  SELECT string_agg(column_name, ', ') INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'communities'
    AND column_name IN ('visit_points', 'activity_points');

  IF v_cols IS NOT NULL THEN
    RAISE EXCEPTION 'communities still carries %: a stand can mint its own rate again, and the leaderboard goes back to measuring which stands you happened to visit',
      v_cols;
  END IF;
END;
$test$;

-- scan_award() is the single place the amount comes from, for both the signing
-- side and the awarding side. If those two ever disagree, a stand advertises
-- one number and the attendee receives another.
DO $test$
DECLARE
  v_main  UUID := 'dddd0004-0000-4000-8000-000000000001';
BEGIN
  IF scan_award('visit', NULL) <> 10 THEN
    RAISE EXCEPTION 'A visit is computed as % points instead of 10', scan_award('visit', NULL);
  END IF;
  IF scan_award('activity', v_main) <> 30 THEN
    RAISE EXCEPTION 'A main event is computed as % points instead of 30',
      scan_award('activity', v_main);
  END IF;
  -- An activity that is not the main event, and an activity id that names
  -- nothing at all, both fall to the ordinary rate rather than the higher one.
  IF scan_award('activity', '00000000-0000-4000-8000-00000000dead') <> 10 THEN
    RAISE EXCEPTION 'An unknown activity is computed as % points instead of the ordinary 10',
      scan_award('activity', '00000000-0000-4000-8000-00000000dead');
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_stand UUID := 'aaaa0004-0000-4000-8000-000000000001';
  v_main  UUID := 'dddd0004-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_points INT;
  v_stored INT;
BEGIN
  -- A payload asking for 9999 points is awarded the rule's value instead. The
  -- request is not an error and the attendee sees the correct award; they may
  -- not even know their client was tampered with.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000001","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.tampered_payload(
    v_stand, NULL, v_now, 'visit', '{"pts": 9999, "points": 9999}'::jsonb));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A payload with inflated points was rejected outright; expected the rule''s value to be awarded instead: %',
      v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'A payload asking for 9999 points awarded %: the amount is being read from the client, so anyone can mint points',
      v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = 'bbbb0004-0000-4000-8000-000000000001';
  SELECT points INTO v_stored FROM scans
  WHERE participant_id = 'bbbb0004-0000-4000-8000-000000000001' AND type = 'visit';
  IF v_points <> 10 OR v_stored <> 10 THEN
    RAISE EXCEPTION 'The balance is % and the recorded scan is worth %, after an award that should have been 10',
      v_points, v_stored;
  END IF;

  -- Negative points never subtract. A scan is a credit or nothing (spec 020,
  -- section 7): no path through a scan may reduce a balance.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000002","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.tampered_payload(
    v_stand, NULL, v_now, 'visit', '{"pts": -500}'::jsonb));
  IF COALESCE((v_res->>'points')::int, 0) < 0 THEN
    RAISE EXCEPTION 'A scan awarded % points: a QR can drain a balance', v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = 'bbbb0004-0000-4000-8000-000000000002';
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'A visit with a negative amount in the payload left the balance at % instead of 10',
      v_points;
  END IF;

  -- The same for an activity: the main event pays 30 whatever is asked for.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000003","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.tampered_payload(
    v_stand, v_main, v_now, 'activity', '{"pts": 9999}'::jsonb));
  IF (v_res->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'An inflated main event awarded % instead of 30', v_res->>'points';
  END IF;

  -- And a payload that claims a lower value does not get to undersell either:
  -- the amount is not negotiable in any direction.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000004","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.tampered_payload(
    v_stand, v_main, v_now, 'activity', '{"pts": 1}'::jsonb));
  IF (v_res->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'A main event awarded % because the payload said so', v_res->>'points';
  END IF;
END;
$test$;

-- A balance can never be stored negative, whatever writes it, and neither can
-- an individual scan.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    UPDATE participants SET points = -1 WHERE id = 'bbbb0004-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A negative balance was stored: the CHECK on participants.points is gone';
  END IF;

  v_blocked := false;
  BEGIN
    INSERT INTO scans (participant_id, community_id, points, type)
    VALUES ('bbbb0004-0000-4000-8000-000000000001',
            'aaaa0004-0000-4000-8000-000000000001', -30, 'visit');
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A scan worth -30 points was recorded: a scan must be a credit or nothing';
  END IF;
END;
$test$;

ROLLBACK;
