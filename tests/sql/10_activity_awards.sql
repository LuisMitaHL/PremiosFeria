-- What completing an activity is worth, and when it is worth anything at all.
--
-- Two rules meet here. Spec 020 prices activities: the stand's main event is
-- worth 30 and everything else 10, decided by the system and never by the code
-- presented to it. Spec 019 decides when a completion can happen: only while
-- the activity is running, which is the entire difference between an activity
-- and a visit -- points go to the people who were actually there.
--
-- The state is checked where the award is decided, not where the button is
-- drawn (spec 019, R19), so a phone still showing an activity as open, or a
-- code photographed while it was, gets the same answer. Both entry points are
-- exercised: the camera and the six-character manual code, which must behave
-- identically (R18, and spec 020 R9).
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text,
                     true);
END;
$fn$;

CREATE FUNCTION pg_temp.qr(p_sid UUID, p_act UUID, p_type TEXT)
RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_sid, 'act', p_act,
    'ts', EXTRACT(EPOCH FROM NOW())::BIGINT / 15,
    'type', p_type,
    'tok', scan_signature(p_sid, p_act, EXTRACT(EPOCH FROM NOW())::BIGINT / 15, p_type,
                          (SELECT value FROM settings WHERE key = 'hmac_secret'))
  )::text
$fn$;

CREATE FUNCTION pg_temp.typed(p_code TEXT) RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object('short_code', p_code)::text
$fn$;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0010-0000-4000-8000-000000000001', 'test_awards_a', 'Awards Stand A',
        'aaaa0010-0000-4000-8000-000000000001'),
       ('aaaa0010-0000-4000-8000-000000000002', 'test_awards_b', 'Awards Stand B',
        'aaaa0010-0000-4000-8000-000000000002');

-- Stand A: its main event, plus two ordinary activities. Only the main event is
-- open to begin with; a stand runs one thing at a time.
INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at, finished_at)
VALUES ('dddd0010-0000-4000-8000-000000000001',
        'aaaa0010-0000-4000-8000-000000000001',
        'Evento principal', 'El taller grande del stand', '10:00', 30, true, now(), NULL),
       ('dddd0010-0000-4000-8000-000000000002',
        'aaaa0010-0000-4000-8000-000000000001',
        'Demostracion', 'Una demo corta', '11:00', 10, false, NULL, NULL),
       -- Stand B: one that never started, one whose time simply ran out with
       -- nobody closing it, and one the stand closed early.
       ('dddd0010-0000-4000-8000-000000000003',
        'aaaa0010-0000-4000-8000-000000000002',
        'Charla pendiente', 'Todavia no empieza', '16:00', 20, false, NULL, NULL),
       ('dddd0010-0000-4000-8000-000000000004',
        'aaaa0010-0000-4000-8000-000000000002',
        'Charla vencida', 'Nadie la cerro', '09:00', 10, false,
        now() - INTERVAL '11 minutes', NULL),
       ('dddd0010-0000-4000-8000-000000000005',
        'aaaa0010-0000-4000-8000-000000000002',
        'Charla cerrada', 'La cerro el stand', '09:30', 30, true,
        now() - INTERVAL '5 minutes', now() - INTERVAL '1 minute');

INSERT INTO participants (id, name, points, auth_user_id)
SELECT ('bbbb0010-0000-4000-8000-00000000000' || n)::uuid,
       'Award Tester ' || n, 0,
       ('bbbb0010-0000-4000-8000-00000000000' || n)::uuid
FROM generate_series(1, 5) AS n;

-- ---------------------------------------------------------------------------
-- A running main event is worth 30, by camera and by typed code alike.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0010-0000-4000-8000-000000000001';
  v_main  UUID := 'dddd0010-0000-4000-8000-000000000001';
  v_p1    UUID := 'bbbb0010-0000-4000-8000-000000000001';
  v_p2    UUID := 'bbbb0010-0000-4000-8000-000000000002';
  v_res   JSONB;
  v_signed JSONB;
  v_points INT;
BEGIN
  PERFORM pg_temp.act_as(v_p1);
  v_res := validate_and_scan(pg_temp.qr(v_stand, v_main, 'activity'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A running main event awarded nothing: %', v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'A main event awarded % points instead of 30: the headline activity is no longer worth crossing the fair for',
      v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_p1;
  IF v_points <> 30 THEN
    RAISE EXCEPTION 'The balance is % after completing a 30-point main event', v_points;
  END IF;

  -- Once per activity, for the whole event (spec 020, R8).
  v_res := validate_and_scan(pg_temp.qr(v_stand, v_main, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The same main event was completed twice: 30 points a scan, as fast as the code rotates';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Ya participaste en esta actividad.' THEN
    RAISE EXCEPTION 'A repeated activity was answered with "%"', v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_p1;
  IF v_points <> 30 THEN
    RAISE EXCEPTION 'A refused repeat still moved the balance, now %', v_points;
  END IF;

  -- The manual code is the same rule reached from the other door: it exists for
  -- the attendee whose camera will not focus, not as a way around anything.
  PERFORM pg_temp.act_as('aaaa0010-0000-4000-8000-000000000001');
  v_signed := sign_scan_code(v_stand, 'activity', v_main);
  IF v_signed ? 'error' THEN
    RAISE EXCEPTION 'The stand could not produce a code for its running main event: %',
      v_signed->>'error';
  END IF;
  IF (v_signed->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'The stand is advertising % points for its main event while the rule awards 30',
      v_signed->>'points';
  END IF;

  PERFORM pg_temp.act_as(v_p2);
  v_res := validate_and_scan(pg_temp.typed(v_signed->>'shortCode'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A typed code for a running main event was refused: %. The attendee whose camera fails is being turned away',
      v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'A typed code awarded % where the camera awards 30', v_res->>'points';
  END IF;

  -- Lower case is what people actually type on a phone.
  v_res := validate_and_scan(pg_temp.typed(lower(v_signed->>'shortCode')));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A typed code completed an activity a second time';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Ya participaste en esta actividad.' THEN
    RAISE EXCEPTION 'A repeat by typed code was answered with "%", which differs from what the camera path says',
      v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_p2;
  IF v_points <> 30 THEN
    RAISE EXCEPTION 'The typed-code balance is % after one 30-point main event', v_points;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Only while it is running: the three states, in one place.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand_a UUID := 'aaaa0010-0000-4000-8000-000000000001';
  v_stand_b UUID := 'aaaa0010-0000-4000-8000-000000000002';
  v_main    UUID := 'dddd0010-0000-4000-8000-000000000001';
  v_pending UUID := 'dddd0010-0000-4000-8000-000000000003';
  v_expired UUID := 'dddd0010-0000-4000-8000-000000000004';
  v_closed  UUID := 'dddd0010-0000-4000-8000-000000000005';
  v_p3      UUID := 'bbbb0010-0000-4000-8000-000000000003';
  v_res     JSONB;
  v_points  INT;
  v_scans   INT;
BEGIN
  PERFORM pg_temp.act_as(v_p3);

  -- Scheduled: it has not started, and the attendee is told exactly that so
  -- they can come back rather than assume it is broken.
  v_res := validate_and_scan(pg_temp.qr(v_stand_b, v_pending, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity that has not started awarded points: anyone can scan the code before the workshop begins and walk away';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Esta actividad todavía no ha iniciado.' THEN
    RAISE EXCEPTION 'A scheduled activity was answered with "%"', v_res->>'reason';
  END IF;

  -- Finished because its duration ran out, with nobody closing it and nothing
  -- running in the background. This is the state that would otherwise keep
  -- awarding points for the rest of the day.
  v_res := validate_and_scan(pg_temp.qr(v_stand_b, v_expired, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity whose duration ran out an hour ago still awarded points: nothing closes it, so its code is worth points until the fair ends';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Esta actividad ya terminó.' THEN
    RAISE EXCEPTION 'An expired activity was answered with "%"', v_res->>'reason';
  END IF;

  -- Finished because the stand closed it early. Scans stop being awarded from
  -- that moment; an attendee told they were too late must stay too late.
  v_res := validate_and_scan(pg_temp.qr(v_stand_b, v_closed, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An activity the stand closed early still awarded points';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Esta actividad ya terminó.' THEN
    RAISE EXCEPTION 'An activity closed early was answered with "%"', v_res->>'reason';
  END IF;

  -- None of those three refusals may leave anything behind.
  SELECT points INTO v_points FROM participants WHERE id = v_p3;
  SELECT count(*) INTO v_scans FROM scans WHERE participant_id = v_p3;
  IF v_points <> 0 OR v_scans <> 0 THEN
    RAISE EXCEPTION 'Three refused attempts left a balance of % and % scan rows',
      v_points, v_scans;
  END IF;

  -- Closing the main event closes the door on it too, even for a code that was
  -- signed while it was still open: the state is read when the award is
  -- decided, not when the code was made.
  UPDATE activities SET finished_at = now() WHERE id = v_main;
  v_res := validate_and_scan(pg_temp.qr(v_stand_a, v_main, 'activity'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A code for the main event still awarded points after the stand closed it';
  END IF;
  IF v_res->>'reason' IS DISTINCT FROM 'Esta actividad ya terminó.' THEN
    RAISE EXCEPTION 'A closed main event was answered with "%"', v_res->>'reason';
  END IF;

  -- And no typed code for it exists any more: the manual path only ever
  -- considers activities that are running.
  v_res := validate_and_scan(pg_temp.typed('ABC123'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A made-up manual code was accepted';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Two different activities at the same stand both count, and each is priced by
-- what it is, not by which stand it belongs to.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand UUID := 'aaaa0010-0000-4000-8000-000000000001';
  v_demo  UUID := 'dddd0010-0000-4000-8000-000000000002';
  v_p1    UUID := 'bbbb0010-0000-4000-8000-000000000001';
  v_p5    UUID := 'bbbb0010-0000-4000-8000-000000000005';
  v_res   JSONB;
  v_points INT;
  v_count INT;
BEGIN
  -- The main event is over, so the stand opens its second activity.
  PERFORM pg_temp.act_as('aaaa0010-0000-4000-8000-000000000001');
  v_res := start_activity(v_demo);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The stand could not open its next activity: %', v_res->>'error';
  END IF;

  PERFORM pg_temp.act_as(v_p1);
  v_res := validate_and_scan(pg_temp.qr(v_stand, v_demo, 'activity'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A second, different activity at the same stand awarded nothing: %. Completing one activity must not use up the stand',
      v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'An ordinary activity awarded % instead of 10', v_res->>'points';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_p1;
  IF v_points <> 40 THEN
    RAISE EXCEPTION 'The balance is % after a main event (30) and one ordinary activity (10)',
      v_points;
  END IF;

  SELECT count(*) INTO v_count FROM scans
  WHERE participant_id = v_p1 AND type = 'activity';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'There are % activity completions on record for one attendee instead of 2',
      v_count;
  END IF;

  -- Another attendee completes the same ordinary activity: what it is worth is
  -- a property of the activity, not of who arrives.
  PERFORM pg_temp.act_as(v_p5);
  v_res := validate_and_scan(pg_temp.qr(v_stand, v_demo, 'activity'));
  IF (v_res->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'The same activity awarded % to a second attendee, where the first got 10',
      v_res->>'points';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A visit is still a visit: the manual path prices it the same way.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand  UUID := 'aaaa0010-0000-4000-8000-000000000001';
  v_p4     UUID := 'bbbb0010-0000-4000-8000-000000000004';
  v_signed JSONB;
  v_res    JSONB;
  v_points INT;
BEGIN
  PERFORM pg_temp.act_as('aaaa0010-0000-4000-8000-000000000001');
  v_signed := sign_scan_code(v_stand, 'visit');
  IF v_signed ? 'error' THEN
    RAISE EXCEPTION 'A stand could not produce its visit code: %', v_signed->>'error';
  END IF;
  IF (v_signed->>'points')::int <> 10 THEN
    RAISE EXCEPTION 'A visit code is advertised as % points instead of 10', v_signed->>'points';
  END IF;

  PERFORM pg_temp.act_as(v_p4);
  v_res := validate_and_scan(pg_temp.typed(v_signed->>'shortCode'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A typed visit code was refused: %', v_res->>'reason';
  END IF;
  IF (v_res->>'points')::int <> 10 OR v_res->>'type' <> 'visit' THEN
    RAISE EXCEPTION 'A typed visit code awarded % points of type %',
      v_res->>'points', v_res->>'type';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_p4;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'The balance is % after one typed visit', v_points;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Points already awarded are never taken back (spec 020, R11). A leaderboard
-- that moves backwards destroys trust in it faster than any other failure, and
-- an attendee cannot tell a withdrawal from a bug.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_demo   UUID := 'dddd0010-0000-4000-8000-000000000002';
  v_p1     UUID := 'bbbb0010-0000-4000-8000-000000000001';
  v_p5     UUID := 'bbbb0010-0000-4000-8000-000000000005';
  v_before INT;
  v_after  INT;
BEGIN
  SELECT points INTO v_before FROM participants WHERE id = v_p1;

  -- Renaming is not possible while it runs, so this is the closest a stand can
  -- come to changing the thing people were awarded for.
  UPDATE activities SET finished_at = now() WHERE id = v_demo;
  SELECT points INTO v_after FROM participants WHERE id = v_p1;
  IF v_after <> v_before THEN
    RAISE EXCEPTION 'Closing an activity moved a balance from % to %', v_before, v_after;
  END IF;

  -- And the row cannot disappear at all. Spec 019 R5 says an activity is never
  -- deleted; the foreign key from scans is RESTRICT so that promise does not
  -- depend on nobody ever writing a DELETE. Deleting would take the completion
  -- history of everyone who did it, and spec 020 R11 says awarded points are
  -- never withdrawn.
  DECLARE
    v_blocked BOOLEAN := false;
  BEGIN
    BEGIN
      DELETE FROM activities WHERE id = v_demo;
    EXCEPTION WHEN foreign_key_violation THEN
      v_blocked := true;
    END;
    IF NOT v_blocked THEN
      RAISE EXCEPTION 'An activity with completions was deleted. The history of everyone who did it went with it, silently';
    END IF;
  END;

  SELECT points INTO v_after FROM participants WHERE id = v_p1;
  IF v_after <> 40 THEN
    RAISE EXCEPTION 'The attendee has % points instead of the 40 they earned', v_after;
  END IF;

  SELECT points INTO v_after FROM participants WHERE id = v_p5;
  IF v_after <> 10 THEN
    RAISE EXCEPTION 'A second attendee has % points instead of 10', v_after;
  END IF;

  IF (SELECT count(*) FROM scans WHERE activity_id = v_demo) = 0 THEN
    RAISE EXCEPTION 'The completion history for this activity is gone';
  END IF;
END;
$test$;

ROLLBACK;
