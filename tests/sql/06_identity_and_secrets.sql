-- Identity and secrets: constitution IV and V, and audit findings F3 and F4.
--
-- The HMAC secret is what makes a QR unforgeable, so no client role may read
-- it. And no RPC may accept a caller identity as an argument, or anyone could
-- award points to anyone.
\set ON_ERROR_STOP on
BEGIN;

-- Every application table has row level security switched on. A table without
-- it is wide open: the grants in 30_grants.sql are deliberately broad and RLS
-- is the only real filter.
DO $test$
DECLARE
  v_unprotected TEXT;
BEGIN
  SELECT string_agg(relname, ', ') INTO v_unprotected
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname IN ('participants', 'communities', 'scans', 'rewards',
                      'claimed_rewards', 'settings')
    AND NOT c.relrowsecurity;

  IF v_unprotected IS NOT NULL THEN
    RAISE EXCEPTION 'Row level security is off on: %. Grants are broad, so these tables are fully exposed', v_unprotected;
  END IF;
END;
$test$;

-- settings holds the HMAC secret and must have RLS on with no policy at all,
-- which makes it unreachable to every client role while SECURITY DEFINER
-- functions can still read it.
DO $test$
DECLARE
  v_policies INT;
BEGIN
  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'settings';

  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'settings has % policies. Any policy on it is a path to the HMAC secret, which would let anyone mint valid QR codes (audit F3)', v_policies;
  END IF;
END;
$test$;

INSERT INTO communities (id, username, name, visit_points, auth_user_id)
VALUES ('aaaa0006-0000-4000-8000-000000000001', 'test_identity', 'Identity Stand', 10,
        'aaaa0006-0000-4000-8000-000000000001');

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0006-0000-4000-8000-000000000001', 'Owner', 0,
        'bbbb0006-0000-4000-8000-000000000001'),
       ('bbbb0006-0000-4000-8000-000000000002', 'Victim', 0,
        'bbbb0006-0000-4000-8000-000000000002');

-- The secret is invisible to the roles a browser can hold, even though those
-- roles hold a SELECT grant on the table.
DO $test$
DECLARE
  v_rows INT;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_rows FROM settings;
  RESET ROLE;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'The anon role can read % rows from settings, including the HMAC secret', v_rows;
  END IF;

  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_rows FROM settings;
  RESET ROLE;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'The authenticated role can read % rows from settings, including the HMAC secret', v_rows;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  -- Being denied outright is an even stronger result than seeing zero rows.
  RESET ROLE;
END;
$test$;

-- No RPC takes a caller identity. If one ever does, an attacker stops needing a
-- session and only needs someone else's id (audit F4).
DO $test$
DECLARE
  v_offender TEXT;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_get_function_arguments(p.oid) || ')', '; ')
  INTO v_offender
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('validate_and_scan', 'claim_reward')
    AND pg_get_function_arguments(p.oid) ILIKE '%participant%';

  IF v_offender IS NOT NULL THEN
    RAISE EXCEPTION 'An RPC accepts a participant identity as a parameter: %', v_offender;
  END IF;
END;
$test$;

-- Acting as one participant credits that participant and nobody else.
DO $test$
DECLARE
  v_stand UUID := 'aaaa0006-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_payload TEXT;
  v_res   JSONB;
  v_owner INT;
  v_victim INT;
BEGIN
  v_payload := jsonb_build_object(
    'sid', v_stand, 'ts', v_now, 'pts', 10, 'type', 'visit',
    'tok', encode(hmac(v_stand || '|' || v_now || '|' || 10 || '|' || 'visit',
                       (SELECT value FROM settings WHERE key = 'hmac_secret'), 'sha256'), 'hex')
  )::text;

  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0006-0000-4000-8000-000000000001","role":"authenticated"}', true);
  v_res := validate_and_scan(v_payload);
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A valid scan was rejected: %', v_res->>'reason';
  END IF;

  SELECT points INTO v_owner  FROM participants WHERE id = 'bbbb0006-0000-4000-8000-000000000001';
  SELECT points INTO v_victim FROM participants WHERE id = 'bbbb0006-0000-4000-8000-000000000002';

  IF v_owner <> 10 THEN
    RAISE EXCEPTION 'The caller was credited % instead of 10', v_owner;
  END IF;
  IF v_victim <> 0 THEN
    RAISE EXCEPTION 'A scan credited an unrelated participant, whose balance is now %', v_victim;
  END IF;
END;
$test$;

-- A caller with no session, or with a session that matches no participant, is
-- refused rather than silently credited to someone.
DO $test$
DECLARE
  v_stand UUID := 'aaaa0006-0000-4000-8000-000000000001';
  v_now   BIGINT := EXTRACT(EPOCH FROM NOW())::BIGINT / 15;
  v_payload TEXT;
  v_res   JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'sid', v_stand, 'ts', v_now, 'pts', 10, 'type', 'visit',
    'tok', encode(hmac(v_stand || '|' || v_now || '|' || 10 || '|' || 'visit',
                       (SELECT value FROM settings WHERE key = 'hmac_secret'), 'sha256'), 'hex')
  )::text;

  PERFORM set_config('request.jwt.claims',
                     '{"sub":"dddd0006-0000-4000-8000-00000000dead","role":"authenticated"}', true);
  v_res := validate_and_scan(v_payload);
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A session with no matching participant was allowed to scan';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
  v_res := validate_and_scan(v_payload);
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An unauthenticated caller was allowed to scan';
  END IF;
END;
$test$;

ROLLBACK;
