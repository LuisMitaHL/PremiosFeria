-- Registering, and coming back (spec 001).
--
-- The nickname is the only thing an attendee gives and also their way back, so
-- two things carry weight: it identifies exactly one person, and returning to a
-- profile needs the device as well. Without the second, anyone types a nickname
-- and takes the points.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.as_session(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

-- A new attendee
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.as_session('cccc0014-0000-4000-8000-000000000001');
  v_res := register_or_recover('Zorro', 'device-a');

  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A first registration was refused: %', v_res->>'error';
  END IF;
  IF (v_res->'participant'->>'points')::int <> 0 THEN
    RAISE EXCEPTION 'A new profile started with % points instead of zero',
      v_res->'participant'->>'points';
  END IF;
  IF (v_res->>'recovered')::boolean THEN
    RAISE EXCEPTION 'A brand new registration was reported as a recovery';
  END IF;

  -- The device identity is theirs, and is not handed back to the screen.
  IF v_res->'participant' ? 'fingerprint' THEN
    RAISE EXCEPTION 'The response carried the device identity back to the client';
  END IF;
END;
$test$;

-- Coming back on the same device
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID;
  v_count INT;
BEGIN
  SELECT id INTO v_id FROM participants WHERE name = 'Zorro';
  UPDATE participants SET points = 70 WHERE id = v_id;

  -- A different anonymous session, the same phone.
  PERFORM pg_temp.as_session('cccc0014-0000-4000-8000-000000000002');
  v_res := register_or_recover('  zorro  ', 'device-a');

  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'An attendee could not return to their own profile: %', v_res->>'error';
  END IF;
  IF NOT (v_res->>'recovered')::boolean THEN
    RAISE EXCEPTION 'Returning to an existing profile was reported as a new registration';
  END IF;
  IF (v_res->'participant'->>'id')::uuid <> v_id THEN
    RAISE EXCEPTION 'Returning produced a different profile';
  END IF;
  IF (v_res->'participant'->>'points')::int <> 70 THEN
    RAISE EXCEPTION 'The recovered profile has % points instead of the 70 it had',
      v_res->'participant'->>'points';
  END IF;

  SELECT count(*) INTO v_count FROM participants WHERE lower(btrim(name)) = 'zorro';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Returning created a second profile; there are now %', v_count;
  END IF;

  -- The session it was re-attached to is the one that asked.
  IF (SELECT auth_user_id FROM participants WHERE id = v_id)
     <> 'cccc0014-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'The recovered profile was not re-attached to the session that recovered it';
  END IF;
END;
$test$;

-- Somebody else's nickname, on another device
DO $test$
DECLARE
  v_res JSONB;
  v_points INT;
  v_owner UUID;
BEGIN
  SELECT id, points INTO v_owner, v_points FROM participants WHERE name = 'Zorro';

  PERFORM pg_temp.as_session('cccc0014-0000-4000-8000-000000000003');
  v_res := register_or_recover('ZORRO', 'device-b');

  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A different device took over an existing profile by typing its nickname';
  END IF;

  IF (SELECT points FROM participants WHERE id = v_owner) <> v_points THEN
    RAISE EXCEPTION 'A refused registration changed the existing profile';
  END IF;
  IF (SELECT auth_user_id FROM participants WHERE id = v_owner)
     = 'cccc0014-0000-4000-8000-000000000003' THEN
    RAISE EXCEPTION 'A refused registration still re-attached the profile to the new session';
  END IF;
END;
$test$;

-- Length, enforced where the data lives
DO $test$
DECLARE
  v_res JSONB;
  v_blocked BOOLEAN;
BEGIN
  PERFORM pg_temp.as_session('cccc0014-0000-4000-8000-000000000004');

  v_res := register_or_recover('a', 'device-c');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A one-character nickname was accepted';
  END IF;

  v_res := register_or_recover(repeat('x', 25), 'device-c');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A 25-character nickname was accepted; it will not fit a projected leaderboard';
  END IF;

  v_res := register_or_recover(repeat('x', 24), 'device-c');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A 24-character nickname was refused: %', v_res->>'error';
  END IF;

  -- And the same limit binds a caller that skips the function entirely.
  v_blocked := false;
  BEGIN
    INSERT INTO participants (name) VALUES (repeat('y', 25));
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'An over-length nickname was stored by a direct insert';
  END IF;
END;
$test$;

-- Uniqueness is structural, not a check before the write
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO participants (name) VALUES ('  ZoRRo ');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A duplicate nickname differing only in case and spacing was stored directly. Two attendees would then share the key that returns a profile';
  END IF;
END;
$test$;

-- There is no client insert path left
DO $test$
DECLARE
  v_policies INT;
BEGIN
  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'participants'
    AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');
  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'participants has % write policies. Registration could then bypass the nickname uniqueness and the device check', v_policies;
  END IF;
END;
$test$;

-- No session, no registration
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  v_res := register_or_recover('Anonimo', 'device-z');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A caller with no session registered a profile';
  END IF;
END;
$test$;

ROLLBACK;
