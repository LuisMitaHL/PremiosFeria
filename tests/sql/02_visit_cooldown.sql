-- Visit cooldown: a visit to the same stand is repeatable, but only after
-- thirty minutes (spec 020, R4). Without it an attendee could stand in front of
-- one QR and farm it as fast as the code rotates; with a hard limit of one, an
-- attendee who genuinely passes the stand again later would be punished for it.
--
-- The interval used to be five minutes, which made camping viable. Six minutes
-- is asserted below precisely so a regression to the old value fails here
-- rather than at the fair.
--
-- The participant row is locked with FOR UPDATE before the cooldown is
-- evaluated (audit finding F8), so two concurrent scans cannot both read a
-- pre-scan state and both pass.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.visit_payload(p_sid UUID, p_ts BIGINT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid, 'act', NULL::uuid, 'ts', p_ts, 'type', 'visit',
    'tok', scan_signature(p_sid, NULL, p_ts, 'visit',
                          (SELECT value FROM settings WHERE key = 'hmac_secret'))
  )::text
$fn$;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0002-0000-4000-8000-000000000001', 'test_cooldown', 'Cooldown Stand',
        'aaaa0002-0000-4000-8000-000000000001'),
       ('aaaa0002-0000-4000-8000-000000000002', 'test_cooldown_b', 'Neighbour Stand',
        'aaaa0002-0000-4000-8000-000000000002');

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0002-0000-4000-8000-000000000001', 'Cooldown Tester', 0,
        'bbbb0002-0000-4000-8000-000000000001');

DO $act$ BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0002-0000-4000-8000-000000000001","role":"authenticated"}', true);
END; $act$;

-- The interval is a constant of the event, not a stand setting. Everything
-- below is written against these two numbers.
DO $test$
DECLARE
  v_cfg JSONB := points_config();
BEGIN
  IF (v_cfg->>'visit_cooldown_minutes')::int <> 30 THEN
    RAISE EXCEPTION 'The visit cooldown is % minutes, not the 30 the fair was priced with (spec 020)',
      v_cfg->>'visit_cooldown_minutes';
  END IF;
  IF (v_cfg->>'visit')::int <> 10 THEN
    RAISE EXCEPTION 'A visit is worth % points, not 10: every reward cost was set against 10',
      v_cfg->>'visit';
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_stand UUID := 'aaaa0002-0000-4000-8000-000000000001';
  v_other UUID := 'aaaa0002-0000-4000-8000-000000000002';
  v_who   UUID := 'bbbb0002-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_res   JSONB;
  v_points INT;
  v_reason TEXT;
BEGIN
  -- The first visit is awarded, at the one rate there is.
  v_res := validate_and_scan(pg_temp.visit_payload(v_stand, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The first visit to a stand was rejected: %', v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'The first visit awarded % points instead of the fixed 10',
      v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'The balance is % after one 10-point visit', v_points;
  END IF;

  -- A second visit straight away is refused, and the balance does not move.
  v_res := validate_and_scan(pg_temp.visit_payload(v_stand, v_now));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A second visit within the cooldown was accepted: the stand can be farmed';
  END IF;

  -- The attendee did nothing wrong, so the refusal has to tell them when they
  -- can come back (spec 020, R13). A bare "no" sends them to the help desk.
  v_reason := v_res->>'reason';
  IF v_reason IS NULL OR v_reason NOT LIKE '%minuto%' THEN
    RAISE EXCEPTION 'The cooldown refusal does not say how long is left: %', v_reason;
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'A rejected visit still changed the balance, now %', v_points;
  END IF;

  -- Six minutes in it is still refused. Under the old five-minute rule this
  -- would have been awarded, so this assertion is the one that catches the
  -- interval being put back.
  UPDATE scans SET created_at = now() - INTERVAL '6 minutes'
  WHERE participant_id = v_who AND community_id = v_stand;

  v_res := validate_and_scan(pg_temp.visit_payload(v_stand, v_now));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit was accepted six minutes in: the cooldown is back to the old five minutes, and camping in front of one stand pays again';
  END IF;

  -- Twenty-nine minutes in, still refused: the window is thirty, not "a while".
  UPDATE scans SET created_at = now() - INTERVAL '29 minutes'
  WHERE participant_id = v_who AND community_id = v_stand;

  v_res := validate_and_scan(pg_temp.visit_payload(v_stand, v_now));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit was accepted twenty-nine minutes in, so the cooldown is shorter than thirty';
  END IF;

  -- Exactly thirty minutes is awarded: the boundary belongs to the attendee.
  -- now() is fixed for the whole transaction, so this is exact, not a race.
  UPDATE scans SET created_at = now() - INTERVAL '30 minutes'
  WHERE participant_id = v_who AND community_id = v_stand;

  v_res := validate_and_scan(pg_temp.visit_payload(v_stand, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit was refused at exactly thirty minutes: the attendee waited the whole cooldown and still got nothing (%)',
      v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 20 THEN
    RAISE EXCEPTION 'The balance is % after two awarded visits of 10', v_points;
  END IF;

  -- The cooldown is per stand. Being inside it at one stand must not stop the
  -- attendee walking to the next one.
  v_res := validate_and_scan(pg_temp.visit_payload(v_other, v_now));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A visit to a different stand was refused while the first stand was in cooldown: %',
      v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_who;
  IF v_points <> 30 THEN
    RAISE EXCEPTION 'The balance is % after three awarded visits of 10', v_points;
  END IF;
END;
$test$;

-- Nothing caps the number of visits beyond the interval (spec 020, R5), and a
-- visit never carries an activity.
DO $test$
DECLARE
  v_count INT;
  v_bad   BOOLEAN := false;
BEGIN
  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = 'bbbb0002-0000-4000-8000-000000000001' AND type = 'visit';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'There are % visit scans on record instead of 3', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = 'bbbb0002-0000-4000-8000-000000000001'
    AND type = 'visit' AND activity_id IS NOT NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION '% visit scans carry an activity id, so the one-completion-per-activity index applies to visits too and repeat visits will start being refused',
      v_count;
  END IF;

  -- Repeat visits stay possible at the storage level: the uniqueness rule is
  -- partial on purpose and must not reach visits.
  BEGIN
    INSERT INTO scans (participant_id, community_id, points, type)
    VALUES ('bbbb0002-0000-4000-8000-000000000001',
            'aaaa0002-0000-4000-8000-000000000001', 10, 'visit');
  EXCEPTION WHEN unique_violation THEN
    v_bad := true;
  END;
  IF v_bad THEN
    RAISE EXCEPTION 'A repeat visit is blocked by a unique index: the per-activity rule has leaked onto visits, which are meant to be repeatable';
  END IF;
END;
$test$;

ROLLBACK;
