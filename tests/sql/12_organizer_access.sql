-- The organiser identity and who may use it (spec 017).
--
-- This is the most powerful credential in the system and it is shared by a
-- team, so what matters is not what the organiser can do but what everybody
-- else cannot. Hiding a route is not a control: these assertions are.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO organizers (username, password_hash)
VALUES ('test_organizer', crypt('Organiza2026*', gen_salt('bf', 12)));

INSERT INTO communities (id, username, name, password_hash, auth_user_id)
VALUES ('aaaa0012-0000-4000-8000-000000000001', 'test_org_stand', 'Org Stand',
        crypt('Stand2026*', gen_salt('bf', 12)), 'aaaa0012-0000-4000-8000-000000000001');

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0012-0000-4000-8000-000000000001', 'Org Tester', 10,
        'bbbb0012-0000-4000-8000-000000000001');

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

-- The two login paths are separate tables and separate functions. That is what
-- stops a stand ever authenticating as an organiser, or the reverse.
DO $test$
DECLARE
  v_rows INT;
BEGIN
  SELECT count(*) INTO v_rows FROM organizer_login('test_organizer', 'Organiza2026*');
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'The organiser could not sign in with correct credentials';
  END IF;

  SELECT count(*) INTO v_rows FROM organizer_login('  TEST_ORGANIZER  ', 'Organiza2026*');
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'The organiser username is case or whitespace sensitive; it is typed off a slip';
  END IF;

  SELECT count(*) INTO v_rows FROM organizer_login('test_organizer', 'organiza2026*');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A password matched with the wrong case';
  END IF;

  -- A stand's credentials must not open the panel.
  SELECT count(*) INTO v_rows FROM organizer_login('test_org_stand', 'Stand2026*');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'A stand authenticated as the organiser. One compromised stand would then be able to create stands';
  END IF;

  -- And the organiser's must not open a stand console.
  SELECT count(*) INTO v_rows FROM stand_login('test_organizer', 'Organiza2026*');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'The organiser authenticated as a stand';
  END IF;

  -- An unknown user and a wrong password are indistinguishable.
  SELECT count(*) INTO v_rows FROM organizer_login('no_existe', 'cualquiera');
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'An unknown organiser username authenticated';
  END IF;
END;
$test$;

-- The hash never leaves the database, and no client role can reach the table.
DO $test$
DECLARE
  v_policies INT;
  v_rls BOOLEAN;
BEGIN
  SELECT relrowsecurity INTO v_rls FROM pg_class WHERE relname = 'organizers';
  IF NOT v_rls THEN
    RAISE EXCEPTION 'organizers has no row level security. The grants are broad, so the table -- and the hash of the most powerful credential in the system -- would be readable by anyone holding the publishable key';
  END IF;

  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'organizers';
  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'organizers has % policies. Any policy on it is a path to the organiser hash', v_policies;
  END IF;
END;
$test$;

-- Nobody but the organiser gets the event overview.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as('aaaa0012-0000-4000-8000-000000000001');
  v_res := event_overview();
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand read the whole event overview: every participant, every balance, every prize';
  END IF;

  PERFORM pg_temp.act_as('bbbb0012-0000-4000-8000-000000000001');
  v_res := event_overview();
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A participant read the event overview';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
  v_res := event_overview();
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A caller with no session read the event overview';
  END IF;

  -- And the organiser does.
  PERFORM pg_temp.act_as((SELECT auth_user_id FROM organizers WHERE username = 'test_organizer'));
  v_res := event_overview();
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not read the overview: %', v_res->>'error';
  END IF;
  IF (v_res->>'participants')::int < 1 THEN
    RAISE EXCEPTION 'The overview reports % participants with one registered', v_res->>'participants';
  END IF;
END;
$test$;

-- The figures have to be right, or the organiser makes decisions on fiction.
DO $test$
DECLARE
  v_res JSONB;
  v_stands INT;
BEGIN
  PERFORM pg_temp.act_as((SELECT auth_user_id FROM organizers WHERE username = 'test_organizer'));
  SELECT count(*) INTO v_stands FROM communities;

  v_res := event_overview();
  IF (v_res->>'stands')::int <> v_stands THEN
    RAISE EXCEPTION 'The overview reports % stands where there are %', v_res->>'stands', v_stands;
  END IF;

  -- With no activities published, a diligent attendee earns one visit per stand
  -- and nothing more. This is the number a reward cost is judged against.
  IF (v_res->>'maxReachable')::int <> v_stands * (points_config()->>'visit')::int THEN
    RAISE EXCEPTION 'The reachable maximum is % with % stands and no activities; it should be one visit each',
      v_res->>'maxReachable', v_stands;
  END IF;

  IF jsonb_array_length(v_res->'runningActivities') <> 0 THEN
    RAISE EXCEPTION 'The overview reports activities running when none were started';
  END IF;
END;
$test$;

-- The organiser is not a stand and not an attendee: they cannot award points or
-- hand over a prize. That holds because those functions resolve their caller
-- from their own tables, and the organiser is in neither.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as((SELECT auth_user_id FROM organizers WHERE username = 'test_organizer'));

  v_res := validate_and_scan('{"short_code":"ZZZZZZ"}');
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The organiser was awarded points; the leaderboard would stop being a consequence of the fair';
  END IF;

  v_res := confirm_handover('ZZZZZZ', (SELECT id FROM rewards LIMIT 1));
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'The organiser confirmed a handover in a stand''s name';
  END IF;

  v_res := create_activity('Actividad', 'Del organizador', '10:00', 10, false);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The organiser created an activity as if it were a stand';
  END IF;
END;
$test$;

ROLLBACK;
