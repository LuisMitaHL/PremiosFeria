-- Column privileges: what a browser holding the publishable key may read.
--
-- participants and communities are world-readable by design, so the leaderboard
-- and the stand list can be public. Row level security is row level only, which
-- means "readable" defaults to "every column readable". These assertions are the
-- boundary: the columns below must not be reachable by any client role, whatever
-- query is sent.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, password_hash, auth_user_id)
VALUES ('aaaa0008-0000-4000-8000-000000000001', 'test_columns', 'Column Stand',
        crypt('Secreta2026*', gen_salt('bf', 12)), 'aaaa0008-0000-4000-8000-000000000001');

INSERT INTO participants (id, name, points, fingerprint, auth_user_id)
VALUES ('bbbb0008-0000-4000-8000-000000000001', 'Column Tester', 10, 'device-fingerprint',
        'bbbb0008-0000-4000-8000-000000000001');

CREATE FUNCTION pg_temp.must_be_denied(p_role TEXT, p_sql TEXT, p_what TEXT)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'The % role can read %. Anyone holding the publishable key can read it too.',
      p_role, p_what;
  EXCEPTION
    WHEN insufficient_privilege THEN
      EXECUTE 'RESET ROLE';
  END;
END;
$fn$;

DO $test$
BEGIN
  -- A stand's password hash. Readable, it can be cracked offline and used to
  -- sign in as that stand -- which is the ability to award points and confirm
  -- handovers (spec 010, R5).
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT password_hash FROM communities', 'communities.password_hash');
  PERFORM pg_temp.must_be_denied('authenticated',
    'SELECT password_hash FROM communities', 'communities.password_hash');

  -- Filtering on it must be refused as well: a WHERE clause reads the column
  -- just as surely as a select list does, and would allow confirming a guess.
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT id FROM communities WHERE password_hash IS NOT NULL',
    'communities.password_hash through a filter');

  -- The device a participant registered from. Spec 001 makes it half of the key
  -- that recovers a profile, so publishing it publishes half a credential
  -- (spec 007, R12).
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT fingerprint FROM participants', 'participants.fingerprint');
  PERFORM pg_temp.must_be_denied('authenticated',
    'SELECT fingerprint FROM participants', 'participants.fingerprint');
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT id FROM participants WHERE fingerprint = ''device-fingerprint''',
    'participants.fingerprint through a filter');

  -- And the blunt instrument: selecting everything must not be a way around it.
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT * FROM participants', 'every participant column at once');
  PERFORM pg_temp.must_be_denied('anon',
    'SELECT * FROM communities', 'every community column at once');
END;
$test$;

-- What the application actually needs must still work.
DO $test$
DECLARE
  v_count INT;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_count
  FROM (SELECT id, name, points FROM participants ORDER BY points DESC) x;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'The leaderboard query returns nothing: the column grants are too narrow';
  END IF;

  SELECT count(*) INTO v_count FROM (
    SELECT id, username, name, emoji, stand_number, description FROM communities
  ) x;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'The stand list query returns nothing: the column grants are too narrow';
  END IF;

  -- The stand console resolves its own community by session identity, and a
  -- participant resolves their own profile the same way. Both must keep working.
  PERFORM 1 FROM communities WHERE auth_user_id = 'aaaa0008-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_count FROM (
    SELECT id, name, points FROM participants
    WHERE auth_user_id = 'bbbb0008-0000-4000-8000-000000000001'
  ) x;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'A participant can no longer resolve their own profile by session identity';
  END IF;
  RESET ROLE;
END;
$test$;

-- Sign-in still works: it runs SECURITY DEFINER and is unaffected by client grants.
DO $test$
DECLARE
  v_rows INT;
BEGIN
  SELECT count(*) INTO v_rows FROM stand_login('test_columns', 'Secreta2026*');
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Sign-in broke: the column grants reached a SECURITY DEFINER function';
  END IF;
END;
$test$;

-- Password hashes are stored at a cost that is not trivially crackable.
DO $test$
DECLARE
  v_cost TEXT;
BEGIN
  SELECT substring(password_hash from 5 for 2) INTO v_cost
  FROM communities WHERE id = 'aaaa0008-0000-4000-8000-000000000001';
  IF v_cost::int < 10 THEN
    RAISE EXCEPTION 'Password hashes use bcrypt cost %, which is crackable offline in minutes. Use 12.', v_cost;
  END IF;
END;
$test$;

ROLLBACK;
