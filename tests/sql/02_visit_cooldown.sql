-- Visit cooldown: a visit to the same stand is repeatable, but only after five
-- minutes. Without it an attendee could stand in front of one QR and farm it as
-- fast as the code rotates.
--
-- The participant row is locked with FOR UPDATE before the cooldown is
-- evaluated (audit finding F8), so two concurrent scans cannot both read a
-- pre-scan state and both pass.
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
VALUES ('aaaa0002-0000-4000-8000-000000000001', 'test_cooldown', 'Cooldown Stand', 10, 25,
        'aaaa0002-0000-4000-8000-000000000001');

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0002-0000-4000-8000-000000000001', 'Cooldown Tester', 0,
        'bbbb0002-0000-4000-8000-000000000001');

DO $act$ BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0002-0000-4000-8000-000000000001","role":"authenticated"}', true);
END; $act$;

DO $test$
DECLARE
  v_stand UUID := 'aaaa0002-0000-4000-8000-000000000001';
  v_who   UUID := 'bbbb0002-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_points INT;
BEGIN
  -- The first visit is awarded, at the stand's configured rate.
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 10, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The first visit to a stand was rejected: %', v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'The first visit awarded % points instead of the stand rate of 10',
      v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'The balance is % after one 10-point visit', v_points;
  END IF;

  -- A second visit straight away is refused, and the balance does not move.
  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 10, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A second visit within the cooldown was accepted: the stand can be farmed';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'A rejected visit still changed the balance, now %', v_points;
  END IF;

  -- Four minutes in, it is still refused: the window is five, not "a while".
  UPDATE scans SET created_at = now() - INTERVAL '4 minutes'
  WHERE participant_id = v_who AND community_id = v_stand;

  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 10, 'visit'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit was accepted four minutes in, so the cooldown is shorter than five';
  END IF;

  -- Past five minutes it is awarded again.
  UPDATE scans SET created_at = now() - INTERVAL '5 minutes 1 second'
  WHERE participant_id = v_who AND community_id = v_stand;

  v_res := validate_and_scan(pg_temp.signed_payload(v_stand, v_now, 10, 'visit'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit was still refused after the cooldown expired: %', v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 20 THEN
    RAISE EXCEPTION 'The balance is % after two awarded visits of 10', v_points;
  END IF;
END;
$test$;

ROLLBACK;
