-- The organiser owns who the stands are (spec 023).
--
-- Two rules carry the weight. Credentials: generated, stored only as a hash,
-- shown once. And withdrawal: never a deletion, because scans and handovers
-- reference a community, and deleting one would take the record of what
-- attendees did at it -- silently contradicting spec 020's promise that awarded
-- points are never withdrawn.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO organizers (username, password_hash)
VALUES ('test_org_mgmt', crypt('Organiza2026*', gen_salt('bf', 12)));

CREATE FUNCTION pg_temp.as_organizer() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', (SELECT auth_user_id FROM organizers WHERE username = 'test_org_mgmt'),
                      'role', 'authenticated')::text, true);
END;
$fn$;

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

-- Creating a community, and the credentials that come with it
DO $test$
DECLARE
  v_res JSONB;
  v_password TEXT;
  v_id UUID;
  v_rows INT;
BEGIN
  PERFORM pg_temp.as_organizer();

  v_res := create_community('Robotica UMSA', 'robotica', '7', 'Bot', 'Brazo robotico');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not create a community: %', v_res->>'error';
  END IF;

  v_password := v_res->>'password';
  v_id := (v_res->'community'->>'id')::uuid;

  IF v_password IS NULL OR length(v_password) < 10 THEN
    RAISE EXCEPTION 'The generated password is "%", which is not a password', v_password;
  END IF;

  -- Shown once, and only here. Anything recoverable is something stealable.
  IF v_res->'community' ? 'password_hash' THEN
    RAISE EXCEPTION 'The response carried the password hash back to the client';
  END IF;

  -- Confusable characters cost a failed sign-in in a noisy hall.
  IF v_password ~ '[O0Il1]' THEN
    RAISE EXCEPTION 'The generated password contains a confusable character: %', v_password;
  END IF;

  SELECT count(*) INTO v_rows FROM stand_login('robotica', v_password);
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'The stand cannot sign in with the credentials it was just given';
  END IF;

  IF (SELECT auth_user_id FROM communities WHERE id = v_id) <> v_id THEN
    RAISE EXCEPTION 'A created community is not linked to its own identity; nothing it does will resolve';
  END IF;

  v_res := create_community('Otra', 'ROBOTICA', '8', 'Bot');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A duplicate username was accepted, differing only in case';
  END IF;
END;
$test$;

-- Only the organiser. A stand cannot create stands, nor rename itself.
DO $test$
DECLARE
  v_res JSONB;
  v_stand UUID;
BEGIN
  SELECT auth_user_id INTO v_stand FROM communities WHERE username = 'robotica';
  PERFORM pg_temp.act_as(v_stand);

  v_res := create_community('Falsa', 'falsa', '9', 'Bot');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand created a community. One compromised stand could then fill the fair';
  END IF;

  v_res := update_community_profile(
    (SELECT id FROM communities WHERE username = 'robotica'), 'Renombrada', '1', 'Bot', NULL);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand renamed itself. Attendees would be looking for a name that is no longer on the map the organiser printed';
  END IF;

  v_res := reset_community_password((SELECT id FROM communities WHERE username = 'robotica'));
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand reset its own password';
  END IF;
END;
$test$;

-- Resetting a password: the new one works, the old one stops
DO $test$
DECLARE
  v_res JSONB;
  v_old TEXT;
  v_new TEXT;
  v_rows INT;
BEGIN
  PERFORM pg_temp.as_organizer();
  v_res := create_community('Fotografia', 'fotos', '3', 'Camera');
  v_old := v_res->>'password';

  v_res := reset_community_password((SELECT id FROM communities WHERE username = 'fotos'));
  v_new := v_res->>'password';

  IF v_new IS NULL OR v_new = v_old THEN
    RAISE EXCEPTION 'The reset returned the same password';
  END IF;

  SELECT count(*) INTO v_rows FROM stand_login('fotos', v_old);
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'The previous password still signs in after a reset';
  END IF;

  SELECT count(*) INTO v_rows FROM stand_login('fotos', v_new);
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'The new password does not sign in';
  END IF;
END;
$test$;

-- Withdrawal stops the community acting and keeps everything that happened
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID;
  v_auth UUID;
  v_participant UUID := 'bbbb0013-0000-4000-8000-000000000001';
  v_before INT;
  v_rows INT;
BEGIN
  PERFORM pg_temp.as_organizer();
  SELECT id, auth_user_id INTO v_id, v_auth FROM communities WHERE username = 'robotica';

  INSERT INTO participants (id, name, points, auth_user_id)
  VALUES (v_participant, 'Retiro Tester', 10, v_participant);
  INSERT INTO scans (participant_id, community_id, points, type)
  VALUES (v_participant, v_id, 10, 'visit');
  SELECT points INTO v_before FROM participants WHERE id = v_participant;

  v_res := set_community_withdrawn(v_id, true);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not withdraw a community: %', v_res->>'error';
  END IF;

  SELECT count(*) INTO v_rows FROM stand_login('robotica', 'irrelevant');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A withdrawn community signed in';
  END IF;

  -- And it cannot act, even holding a session issued before it was withdrawn.
  PERFORM pg_temp.act_as(v_auth);
  IF calling_community() IS NOT NULL THEN
    RAISE EXCEPTION 'A withdrawn community still resolves as a caller: with the token it already holds it could start activities and confirm handovers';
  END IF;

  v_res := create_activity('Actividad', 'De un stand retirado', '10:00', 10, false);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A withdrawn community created an activity';
  END IF;

  v_res := sign_scan_code(v_id, 'visit');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A withdrawn community produced a scan code; the room would keep earning points for a stand that is not there';
  END IF;

  IF (SELECT points FROM participants WHERE id = v_participant) <> v_before THEN
    RAISE EXCEPTION 'Withdrawing a community changed an attendee balance';
  END IF;
  IF (SELECT count(*) FROM scans WHERE community_id = v_id) = 0 THEN
    RAISE EXCEPTION 'Withdrawing a community erased its scans, and with them the record of what attendees did';
  END IF;

  PERFORM pg_temp.as_organizer();
  PERFORM set_community_withdrawn(v_id, false);
  PERFORM pg_temp.act_as(v_auth);
  IF calling_community() IS NULL THEN
    RAISE EXCEPTION 'A reinstated community still cannot act';
  END IF;
END;
$test$;

-- Nothing deletes a community that people passed through
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    DELETE FROM communities WHERE username = 'robotica';
  EXCEPTION WHEN foreign_key_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A community with scans was deleted, taking the record of what attendees did at it';
  END IF;
END;
$test$;

-- The organiser's reward powers, and their limits
DO $test$
DECLARE
  v_res JSONB;
  v_reward UUID;
  v_community UUID;
BEGIN
  PERFORM pg_temp.as_organizer();
  SELECT id INTO v_community FROM communities WHERE username = 'fotos';
  INSERT INTO rewards (community_id, name, cost, stock)
  VALUES (v_community, 'Impresion', 100, 3) RETURNING id INTO v_reward;

  v_res := set_reward_cost(v_reward, 250);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not correct a price: %', v_res->>'error';
  END IF;

  -- Authority to correct a price is not authority to break the economy.
  v_res := set_reward_cost(v_reward, 301);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The organiser set a price above the ceiling, putting a prize out of everyone reach';
  END IF;

  v_res := set_reward_stock(v_reward, 1);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not reduce stock: %', v_res->>'error';
  END IF;

  v_res := set_reward_stock(v_reward, -1);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'Stock was set below zero';
  END IF;

  v_res := set_reward_withdrawn(v_reward, true);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not withdraw a reward: %', v_res->>'error';
  END IF;
  IF (SELECT count(*) FROM rewards WHERE id = v_reward) <> 1 THEN
    RAISE EXCEPTION 'Withdrawing a reward deleted it; a confirmed handover would stop naming something real';
  END IF;
END;
$test$;

ROLLBACK;
