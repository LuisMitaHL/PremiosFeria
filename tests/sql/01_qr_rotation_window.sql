-- Rotation window and signature integrity for validate_and_scan.
--
-- A QR is valid for a 15-second window (epoch / 15) with one window of backward
-- tolerance for network latency. The token is an HMAC over the stand, window,
-- points and type, signed with a secret the client never sees. Together these
-- are what stop a code being photographed and reused, or forged outright.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.signed_payload(p_sid UUID, p_ts BIGINT, p_pts INT, p_type TEXT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid,
    'ts', p_ts,
    'pts', p_pts,
    'type', p_type,
    'tok', encode(
      hmac(p_sid || '|' || p_ts || '|' || p_pts || '|' || p_type,
           (SELECT value FROM settings WHERE key = 'hmac_secret'), 'sha256'),
      'hex')
  )::text
$fn$;

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  -- The same way PostgREST hands the verified JWT to Postgres. Identity is
  -- never a parameter (constitution IV), so this is the only way to act as
  -- someone.
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text,
                     true);
END;
$fn$;

INSERT INTO communities (id, username, name, visit_points, activity_points, auth_user_id)
VALUES ('aaaa0001-0000-4000-8000-000000000001', 'test_qr_stand', 'QR Test Stand', 10, 25,
        'aaaa0001-0000-4000-8000-000000000001');

-- One participant per assertion: a successful scan starts a cooldown, which
-- would otherwise mask the result of the next one.
INSERT INTO participants (id, name, points, auth_user_id)
SELECT ('bbbb0001-0000-4000-8000-00000000000' || n)::uuid,
       'QR Tester ' || n, 0,
       ('bbbb0001-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 5) AS n;

DO $test$
DECLARE
  v_stand UUID := 'aaaa0001-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_bad   TEXT;
BEGIN
  -- The current window is accepted.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000001');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 10, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from the current window was rejected: %', v_res->>'reason';
  END IF;

  -- The previous window is accepted: a scan in flight when the code rotates
  -- must still count, or attendees lose points to their own latency.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000002');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now - 1, 10, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from the previous window was rejected, so the latency tolerance is gone: %',
      v_res->>'reason';
  END IF;

  -- Two windows back is expired. This is what stops a photographed code from
  -- being shared around the fair.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000003');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now - 2, 10, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR two windows old was accepted: an expired code can be replayed';
  END IF;

  -- A window in the future is refused too, so a clock skewed forward cannot
  -- mint codes that stay valid for longer.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000004');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now + 1, 10, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from a future window was accepted';
  END IF;

  -- A forged signature is refused. Without this the payload is just text the
  -- client could write itself.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000005');
  v_bad := jsonb_build_object(
    'sid', v_stand, 'ts', v_now, 'pts', 10, 'type', 'visit',
    'tok', repeat('f', 64)
  )::text;
  v_res := validate_and_scan(v_bad);
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR with a forged HMAC was accepted: anyone could mint points';
  END IF;
END;
$test$;

ROLLBACK;
