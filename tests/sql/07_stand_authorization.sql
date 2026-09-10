-- Stand identity: who may log in as a stand, and who may sign that stand's QR
-- codes. A stand admin who could sign another stand's codes could mint points
-- for a stand they do not run.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, password_hash, visit_points, activity_points, auth_user_id)
VALUES ('aaaa0007-0000-4000-8000-000000000001', 'MiStand', 'Mi Stand',
        crypt('Secreta2026*', gen_salt('bf')), 10, 25,
        'aaaa0007-0000-4000-8000-000000000001'),
       ('aaaa0007-0000-4000-8000-000000000002', 'otro', 'Otro Stand',
        NULL, 10, 25,
        'aaaa0007-0000-4000-8000-000000000002');

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
  v_mine   UUID := 'aaaa0007-0000-4000-8000-000000000001';
  v_theirs UUID := 'aaaa0007-0000-4000-8000-000000000002';
  v_res    JSONB;
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

  -- An unknown scan type is refused rather than signed as something else.
  v_res := sign_scan_code(v_mine, 'jackpot');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An unknown scan type was signed';
  END IF;

  -- The signed points follow the stand's configuration, not the caller.
  v_res := sign_scan_code(v_mine, 'activity');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Signing an activity code failed: %', v_res->>'error';
  END IF;
  IF (v_res->'payload'->>'pts')::int <> 25 THEN
    RAISE EXCEPTION 'An activity code was signed for % points instead of the stand rate of 25',
      v_res->'payload'->>'pts';
  END IF;
END;
$test$;

ROLLBACK;
