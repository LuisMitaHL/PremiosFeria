-- Rotation window and signature integrity for validate_and_scan.
--
-- A QR is valid for a 15-second window (epoch / 15) with one window of backward
-- tolerance for network latency. The token is an HMAC over the stand, the
-- activity, the window and the type, signed with a secret the client never
-- sees. The amount is no longer part of the payload at all (spec 020): the
-- system decides it, so there is nothing left to inflate. What the signature
-- still has to do is bind every field that selects WHICH award is computed --
-- otherwise a payload could be assembled out of parts of two valid codes.
--
-- Together these are what stop a code being photographed and reused, or forged
-- outright.
\set ON_ERROR_STOP on
BEGIN;

-- The signature is recomputed here by hand rather than by calling
-- scan_signature(), so that this file pins the canonical signed string. If the
-- signed fields ever change, these payloads stop verifying and this test says
-- so, instead of quietly following the change.
CREATE FUNCTION pg_temp.signed_payload(p_sid UUID, p_act UUID, p_ts BIGINT, p_type TEXT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid,
    'act', p_act,
    'ts', p_ts,
    'type', p_type,
    'tok', encode(
      hmac(p_sid || '|' || COALESCE(p_act::text, '') || '|' || p_ts || '|' || p_type,
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

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0001-0000-4000-8000-000000000001', 'test_qr_stand', 'QR Test Stand',
        'aaaa0001-0000-4000-8000-000000000001');

-- A running activity, so the activity path can be exercised through the same
-- window and signature checks the visit path uses.
INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at)
VALUES ('dddd0001-0000-4000-8000-000000000001',
        'aaaa0001-0000-4000-8000-000000000001',
        'Taller de robotica', 'Armado de un brazo robotico',
        '10:00', 45, true, now());

-- One participant per assertion: a successful scan starts a cooldown, which
-- would otherwise mask the result of the next one.
INSERT INTO participants (id, name, points, auth_user_id)
SELECT ('bbbb0001-0000-4000-8000-00000000000' || n)::uuid,
       'QR Tester ' || n, 0,
       ('bbbb0001-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 7) AS n;

DO $test$
DECLARE
  v_stand UUID := 'aaaa0001-0000-4000-8000-000000000001';
  v_act   UUID := 'dddd0001-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_bad   TEXT;
BEGIN
  -- The current window is accepted.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000001');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, NULL, v_now, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from the current window was rejected: %', v_res->>'reason';
  END IF;

  -- The previous window is accepted: a scan in flight when the code rotates
  -- must still count, or attendees lose points to their own latency.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000002');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, NULL, v_now - 1, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from the previous window was rejected, so the latency tolerance is gone: %',
      v_res->>'reason';
  END IF;

  -- Two windows back is expired. This is what stops a photographed code from
  -- being shared around the fair.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000003');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, NULL, v_now - 2, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR two windows old was accepted: an expired code can be replayed';
  END IF;

  -- A window in the future is refused too, so a clock skewed forward cannot
  -- mint codes that stay valid for longer.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000004');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, NULL, v_now + 1, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR from a future window was accepted';
  END IF;

  -- A forged signature is refused. Without this the payload is just text the
  -- client could write itself.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000005');
  v_bad := jsonb_build_object(
    'sid', v_stand, 'act', NULL::uuid, 'ts', v_now, 'type', 'visit',
    'tok', repeat('f', 64)
  )::text;
  v_res := validate_and_scan(v_bad);
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR with a forged HMAC was accepted: anyone could mint points';
  END IF;

  -- The activity path goes through the same window, so a code for a running
  -- activity is accepted in the current window.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000006');
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_act, v_now, 'activity'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A QR for a running activity was rejected in the current window: %',
      v_res->>'reason';
  END IF;

  -- The timestamp is part of the signed string, so a token minted for one
  -- window cannot be moved to another. This payload is refused for one reason
  -- only: the window it declares is still inside the tolerance and the activity
  -- is still running, so if it were accepted the signature would be decorative.
  PERFORM pg_temp.act_as('bbbb0001-0000-4000-8000-000000000007');
  v_bad := jsonb_set(
    pg_temp.signed_payload(v_stand, v_act, v_now, 'activity')::jsonb,
    '{ts}', to_jsonb(v_now - 1))::text;
  v_res := validate_and_scan(v_bad);
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A token signed for one window was accepted in another: the timestamp is not covered by the signature, so one photographed code lasts as long as the tolerance allows';
  END IF;
END;
$test$;

-- Every field that selects the award is signed together. Changing any one of
-- them must produce a different token, or a payload can be assembled out of
-- parts of two valid codes -- the visit code of a stand plus the activity id of
-- its 30-point main event, for instance.
DO $test$
DECLARE
  v_stand  UUID := 'aaaa0001-0000-4000-8000-000000000001';
  v_other  UUID := 'aaaa0001-0000-4000-8000-000000000002';
  v_act    UUID := 'dddd0001-0000-4000-8000-000000000001';
  v_act_b  UUID := 'dddd0001-0000-4000-8000-000000000002';
  v_now    BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_secret TEXT;
  v_base   TEXT;
BEGIN
  SELECT value INTO v_secret FROM settings WHERE key = 'hmac_secret';
  v_base := scan_signature(v_stand, v_act, v_now, 'activity', v_secret);

  IF v_base = scan_signature(v_other, v_act, v_now, 'activity', v_secret) THEN
    RAISE EXCEPTION 'The stand is not covered by the signature: one stand''s code would be valid at another';
  END IF;
  IF v_base = scan_signature(v_stand, v_act_b, v_now, 'activity', v_secret) THEN
    RAISE EXCEPTION 'The activity is not covered by the signature: a code for a 10-point activity could be presented as the 30-point main event';
  END IF;
  IF v_base = scan_signature(v_stand, v_act, v_now - 1, 'activity', v_secret) THEN
    RAISE EXCEPTION 'The window is not covered by the signature: a photographed code never expires';
  END IF;
  IF v_base = scan_signature(v_stand, v_act, v_now, 'visit', v_secret) THEN
    RAISE EXCEPTION 'The type is not covered by the signature: a visit code could be presented as an activity';
  END IF;
  IF scan_signature(v_stand, NULL, v_now, 'visit', v_secret)
     = scan_signature(v_stand, NULL, v_now, 'visit', v_secret || 'x') THEN
    RAISE EXCEPTION 'The secret does not change the signature: the token is not an HMAC at all';
  END IF;
END;
$test$;

ROLLBACK;
