-- Stand identity: who may log in as a stand, and who may sign that stand's QR
-- codes. A stand admin who could sign another stand's codes could mint points
-- for a stand they do not run.
--
-- Since spec 019 a code also names an activity, so signing carries a second
-- authority: which of the stand's activities the code is for, and whether that
-- activity is open at all. A code for something that is not running awards
-- nothing, and projecting one only produces a queue of people being refused.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, password_hash, auth_user_id)
VALUES ('aaaa0007-0000-4000-8000-000000000001', 'MiStand', 'Mi Stand',
        crypt('Secreta2026*', gen_salt('bf')),
        'aaaa0007-0000-4000-8000-000000000001'),
       ('aaaa0007-0000-4000-8000-000000000002', 'otro', 'Otro Stand',
        NULL,
        'aaaa0007-0000-4000-8000-000000000002');

-- Mi Stand runs a main event, currently open, and has a second activity that
-- has not started. Otro Stand has one of its own, which Mi Stand must not be
-- able to sign for.
INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at)
VALUES ('dddd0007-0000-4000-8000-000000000001',
        'aaaa0007-0000-4000-8000-000000000001',
        'Taller principal', 'El evento grande del stand', '10:00', 45, true, now()),
       ('dddd0007-0000-4000-8000-000000000002',
        'aaaa0007-0000-4000-8000-000000000001',
        'Charla posterior', 'Todavia no empieza', '15:00', 20, false, NULL),
       ('dddd0007-0000-4000-8000-000000000003',
        'aaaa0007-0000-4000-8000-000000000002',
        'Actividad ajena', 'Del otro stand', '11:00', 30, false, now());

-- Passwords are compared as bcrypt hashes inside the database; the hash itself
-- is never returned.
DO $test$
DECLARE
  v_rows INT;
  v_cols TEXT;
BEGIN
  SELECT count(*) INTO v_rows FROM stand_login('MiStand', 'Secreta2026*');
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A correct stand password did not authenticate';
  END IF;

  -- The login name is case-insensitive and tolerates stray whitespace: it is
  -- typed off a printed slip, on a phone, during an event.
  SELECT count(*) INTO v_rows FROM stand_login('  mistand  ', 'Secreta2026*');
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'A stand login failed on case or surrounding whitespace';
  END IF;

  -- The password is not.
  SELECT count(*) INTO v_rows FROM stand_login('MiStand', 'secreta2026*');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A password matched with the wrong case';
  END IF;

  SELECT count(*) INTO v_rows FROM stand_login('MiStand', 'incorrecta');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A wrong password authenticated';
  END IF;

  -- An unknown user and a wrong password are indistinguishable: both return no
  -- rows, so the caller cannot enumerate stand names.
  SELECT count(*) INTO v_rows FROM stand_login('no_existe', 'cualquiera');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'An unknown username authenticated';
  END IF;

  -- A stand with no hash set stays locked rather than accepting anything.
  SELECT count(*) INTO v_rows FROM stand_login('otro', '');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A stand with a NULL password hash authenticated with an empty password';
  END IF;

  -- The hash never leaves the database.
  SELECT string_agg(a.attname, ', ') INTO v_cols
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN LATERAL unnest(p.proargnames) AS a(attname) ON true
  WHERE n.nspname = 'public' AND p.proname = 'stand_login'
    AND a.attname ILIKE '%hash%';
  IF v_cols IS NOT NULL THEN
    RAISE EXCEPTION 'stand_login exposes a hash column: %', v_cols;
  END IF;
END;
$test$;

-- Only the stand that owns a QR may have it signed.
DO $test$
DECLARE
  v_mine    UUID := 'aaaa0007-0000-4000-8000-000000000001';
  v_theirs  UUID := 'aaaa0007-0000-4000-8000-000000000002';
  v_running UUID := 'dddd0007-0000-4000-8000-000000000001';
  v_theirs_act UUID := 'dddd0007-0000-4000-8000-000000000003';
  v_res     JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"aaaa0007-0000-4000-8000-000000000001","role":"authenticated"}', true);

  v_res := sign_scan_code(v_mine, 'visit');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A stand could not sign its own QR: %', v_res->>'error';
  END IF;
  IF (v_res->'payload'->>'tok') IS NULL THEN
    RAISE EXCEPTION 'A signed payload came back without a token';
  END IF;
  IF length(v_res->>'shortCode') <> 6 THEN
    RAISE EXCEPTION 'The manual code is % characters long instead of 6', length(v_res->>'shortCode');
  END IF;

  -- Signing someone else's QR is refused. This is the whole reason the secret
  -- stays in the database.
  v_res := sign_scan_code(v_theirs, 'visit');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand signed another stand''s QR code';
  END IF;

  -- Nor another stand's activity, even presented under its own community id.
  v_res := sign_scan_code(v_mine, 'activity', v_theirs_act);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand signed a code for an activity belonging to another stand';
  END IF;

  -- An unknown scan type is refused rather than signed as something else.
  v_res := sign_scan_code(v_mine, 'jackpot');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An unknown scan type was signed';
  END IF;

  -- An activity code has to say which activity. Without one there is nothing to
  -- award and nothing to bind the signature to.
  v_res := sign_scan_code(v_mine, 'activity');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An activity code was signed without naming an activity';
  END IF;

  -- And a visit code must not carry one: a visit is a visit at every stand.
  v_res := sign_scan_code(v_mine, 'visit', v_running);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A visit code was signed with an activity attached to it';
  END IF;
END;
$test$;

-- What a signed activity code contains, and when it may exist at all.
DO $test$
DECLARE
  v_mine      UUID := 'aaaa0007-0000-4000-8000-000000000001';
  v_running   UUID := 'dddd0007-0000-4000-8000-000000000001';
  v_scheduled UUID := 'dddd0007-0000-4000-8000-000000000002';
  v_res       JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"aaaa0007-0000-4000-8000-000000000001","role":"authenticated"}', true);

  v_res := sign_scan_code(v_mine, 'activity', v_running);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Signing the code of a running activity failed: %', v_res->>'error';
  END IF;
  IF (v_res->'payload'->>'act')::uuid IS DISTINCT FROM v_running THEN
    RAISE EXCEPTION 'The signed payload names activity % instead of the one that was asked for',
      v_res->'payload'->>'act';
  END IF;

  -- The amount is no longer part of what is signed or sent (spec 020). It comes
  -- back alongside the payload only so the stand can tell people what the code
  -- is worth; putting it back inside the payload would hand the client a number
  -- the award could be read from.
  IF v_res->'payload' ? 'pts' THEN
    RAISE EXCEPTION 'The signed payload still carries an amount: the award must be recomputed from the rule, never read from the code';
  END IF;
  IF (v_res->>'points')::int <> 30 THEN
    RAISE EXCEPTION 'A main event code was advertised as % points instead of 30',
      v_res->>'points';
  END IF;

  -- A code for something that has not started must not exist. Projecting one
  -- produces a queue of attendees being refused, and the stand finds out from
  -- the complaints.
  v_res := sign_scan_code(v_mine, 'activity', v_scheduled);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A code was signed for an activity that has not started: every attendee who scans it is refused';
  END IF;

  -- Nor for one that is over. This is the same check as the award side, so a
  -- stand cannot keep handing out points after closing.
  UPDATE activities SET finished_at = now() WHERE id = v_running;
  v_res := sign_scan_code(v_mine, 'activity', v_running);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A code was signed for an activity that has already finished';
  END IF;

  -- Including one that finished by itself, with nobody closing it: the state is
  -- derived, so an expired activity is over whether or not anyone said so.
  UPDATE activities
  SET started_at = now() - INTERVAL '46 minutes', finished_at = NULL
  WHERE id = v_running;
  v_res := sign_scan_code(v_mine, 'activity', v_running);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A code was signed for an activity whose duration ran out 1 minute ago: an activity nobody closed keeps awarding points all day';
  END IF;
END;
$test$;

-- A caller with no stand session signs nothing at all.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  v_res := sign_scan_code('aaaa0007-0000-4000-8000-000000000001', 'visit');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An unauthenticated caller signed a stand''s QR code, which is the ability to mint points anywhere in the fair';
  END IF;
END;
$test$;

ROLLBACK;
