-- Point ceilings. A stand may award up to 30 for a visit and up to 100 for an
-- activity. The client is public, so the payload it sends is untrusted input:
-- the RPC re-clamps to the stand's own configured rate regardless of what
-- arrives, and a CHECK constraint stops a stand configuring itself above the
-- ceiling in the first place (constitution VI).
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, visit_points, activity_points, auth_user_id)
VALUES ('aaaa0004-0000-4000-8000-000000000001', 'test_ceiling', 'Ceiling Stand', 10, 25,
        'aaaa0004-0000-4000-8000-000000000001');

INSERT INTO participants (id, name, points, auth_user_id)
SELECT ('bbbb0004-0000-4000-8000-00000000000' || n)::uuid,
       'Ceiling Tester ' || n, 0,
       ('bbbb0004-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 3) AS n;

-- A tampered payload must be signed to get past the HMAC check at all, so this
-- models the worst case: an attacker who has somehow obtained the secret still
-- cannot exceed the stand's rate.
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

DO $test$
DECLARE
  v_stand UUID := 'aaaa0004-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_points INT;
BEGIN
  -- An inflated payload is clamped to the stand's rate, not to the global cap
  -- and not to what was asked for.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000001","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 9999, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A payload with inflated points was rejected outright; expected it to be clamped: %',
      v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'A request for 9999 points awarded % instead of the stand rate of 10',
      v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = 'bbbb0004-0000-4000-8000-000000000001';
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'The balance is % after a clamped award of 10', v_points;
  END IF;

  -- Negative points never subtract. A scan is always a credit or nothing.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000002","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, -500, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false)
     AND (v_res->>'points')::int < 0 THEN
    RAISE EXCEPTION 'A scan awarded % points: a QR can drain a balance', v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = 'bbbb0004-0000-4000-8000-000000000002';
  IF v_points < 0 THEN
    RAISE EXCEPTION 'A balance went negative, at %', v_points;
  END IF;

  -- The activity ceiling is enforced the same way.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0004-0000-4000-8000-000000000003","role":"authenticated"}', true);
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 9999, 'activity'));
  IF (v_res->>'points')::int <> 25 THEN
    RAISE EXCEPTION 'An inflated activity awarded % instead of the stand rate of 25',
      v_res->>'points';
  END IF;
END;
$test$;

-- A stand cannot configure itself above the ceiling: the constraint is what
-- makes the clamp above meaningful.
DO $test$
DECLARE
  v_blocked BOOLEAN;
BEGIN
  v_blocked := false;
  BEGIN
    UPDATE communities SET visit_points = 31 WHERE id = 'aaaa0004-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A stand set its visit rate to 31: the 30-point ceiling is not enforced';
  END IF;

  v_blocked := false;
  BEGIN
    UPDATE communities SET activity_points = 101 WHERE id = 'aaaa0004-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A stand set its activity rate to 101: the 100-point ceiling is not enforced';
  END IF;

  v_blocked := false;
  BEGIN
    UPDATE communities SET visit_points = -1 WHERE id = 'aaaa0004-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A stand set a negative visit rate';
  END IF;
END;
$test$;

-- A balance can never be stored negative, whatever writes it.
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
END;
$test$;

ROLLBACK;
