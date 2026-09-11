-- The home screen, in one read (spec 013).
--
-- The figure this suite exists for is the count of prizes within reach. It is
-- the one number on the screen that is not a count of something that already
-- happened: it is a promise about what the attendee could do right now, and it
-- is made out of four things that live in four different specs -- cost, stock,
-- two withdrawal flags -- plus what this attendee already took home. Every
-- filter dropped from it promises a prize the handover then refuses, which is
-- the one thing the spec says is worse than showing no count at all.
--
-- The rest asks the two questions that keep the screen honest: that each figure
-- belongs to the session that asked for it and to nobody else, and that asking
-- changes nothing.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures. Nothing here depends on seed data.
-- ---------------------------------------------------------------------------

INSERT INTO communities (id, username, name, stand_number, is_withdrawn) VALUES
  ('aaaa0017-0000-4000-8000-00000000000a', 'quest17_a', 'Stand A', '1', false),
  ('aaaa0017-0000-4000-8000-00000000000b', 'quest17_b', 'Stand B', '2', false),
  ('aaaa0017-0000-4000-8000-00000000000c', 'quest17_c', 'Stand C', '3', true);

-- The attendee this suite follows, and a second one to ask whether one screen
-- can ever show another person's figures.
INSERT INTO participants (id, name, points, auth_user_id) VALUES
  ('cccc0017-0000-4000-8000-000000000001', 'Tejon17', 40,
   'dddd0017-0000-4000-8000-000000000001'),
  ('cccc0017-0000-4000-8000-000000000002', 'Lobo17', 0,
   'dddd0017-0000-4000-8000-000000000002');

-- The catalogue, built so that every exclusion has exactly one prize behind it.
-- With 40 points only the sticker is within reach; each of the others is out
-- for a different, single reason.
INSERT INTO rewards (id, community_id, name, cost, stock, is_withdrawn) VALUES
  ('eeee0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   'Sticker',  10, 5, false),   -- within reach
  ('eeee0017-0000-4000-8000-000000000002', 'aaaa0017-0000-4000-8000-00000000000a',
   'Llavero',  10, 0, false),   -- out of stock
  ('eeee0017-0000-4000-8000-000000000003', 'aaaa0017-0000-4000-8000-00000000000a',
   'Gorra',   200, 5, false),   -- unaffordable
  ('eeee0017-0000-4000-8000-000000000004', 'aaaa0017-0000-4000-8000-00000000000a',
   'Retirado', 10, 5, true),    -- withdrawn prize
  ('eeee0017-0000-4000-8000-000000000005', 'aaaa0017-0000-4000-8000-00000000000c',
   'Fantasma', 10, 5, false),   -- prize of a withdrawn stand
  ('eeee0017-0000-4000-8000-000000000006', 'aaaa0017-0000-4000-8000-00000000000b',
   'Taza',     10, 5, false);   -- already claimed

INSERT INTO claimed_rewards (participant_id, reward_id, confirmed_by) VALUES
  ('cccc0017-0000-4000-8000-000000000001', 'eeee0017-0000-4000-8000-000000000006',
   'aaaa0017-0000-4000-8000-00000000000b');

-- Two activities at the same stand, so that "activities completed" can be told
-- apart from "stands where something was completed" (spec 019 allows three per
-- stand; before it, the two numbers were the same).
INSERT INTO activities (id, community_id, name, description, estimated_start,
                        duration_min, is_main_event, started_at, finished_at) VALUES
  ('ffff0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   'Taller en curso', 'Corriendo ahora', '10:00', 30, true, now() - INTERVAL '5 minutes', NULL),
  ('ffff0017-0000-4000-8000-000000000002', 'aaaa0017-0000-4000-8000-00000000000a',
   'Charla programada', 'Todavia no inicia', '12:00', 30, false, NULL, NULL),
  ('ffff0017-0000-4000-8000-000000000003', 'aaaa0017-0000-4000-8000-00000000000b',
   'Taller vencido', 'Nadie la cerro', '09:00', 30, false, now() - INTERVAL '90 minutes', NULL),
  ('ffff0017-0000-4000-8000-000000000004', 'aaaa0017-0000-4000-8000-00000000000c',
   'Taller retirado', 'De un stand retirado', '10:00', 30, false, now() - INTERVAL '5 minutes', NULL);

-- Tejon: one visit to stand A, one to stand B, and two completions at stand A.
INSERT INTO scans (participant_id, community_id, activity_id, points, type) VALUES
  ('cccc0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   NULL, 10, 'visit'),
  ('cccc0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   NULL, 10, 'visit'),
  ('cccc0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000b',
   NULL, 10, 'visit'),
  ('cccc0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   'ffff0017-0000-4000-8000-000000000001', 20, 'activity'),
  ('cccc0017-0000-4000-8000-000000000001', 'aaaa0017-0000-4000-8000-00000000000a',
   'ffff0017-0000-4000-8000-000000000002', 10, 'activity');

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

CREATE FUNCTION pg_temp.no_session() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$fn$;

CREATE FUNCTION pg_temp.as_tejon() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM pg_temp.act_as('dddd0017-0000-4000-8000-000000000001');
END;
$fn$;

-- The number the screen would print, for whoever is holding the session.
CREATE FUNCTION pg_temp.reachable() RETURNS INT LANGUAGE sql AS $fn$
  SELECT (participant_dashboard()->>'rewardsReachable')::int
$fn$;

-- ---------------------------------------------------------------------------
-- The count of prizes within reach, and every filter it is made of.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v JSONB;
BEGIN
  PERFORM pg_temp.as_tejon();
  v := participant_dashboard();

  IF v ? 'error' THEN
    RAISE EXCEPTION 'The dashboard refused a registered attendee: %', v->>'error';
  END IF;

  -- Six prizes exist; the withdrawn one and the one belonging to the withdrawn
  -- stand are not part of the fair any more, so the catalogue is four.
  IF (v->>'rewardsPublished')::int <> 4 THEN
    RAISE EXCEPTION 'The published catalogue counted %, expected 4 (a withdrawn prize or a withdrawn stand is being counted)',
      v->>'rewardsPublished';
  END IF;

  IF (v->>'rewardsReachable')::int <> 1 THEN
    RAISE EXCEPTION 'Prizes within reach counted %, expected 1: only the sticker is affordable, in stock, available and unclaimed',
      v->>'rewardsReachable';
  END IF;

  -- The shortfall is measured against the cheapest prize they could still take
  -- home, not against the cheapest prize in the catalogue.
  IF (v->>'pointsToNext')::int <> 160 THEN
    RAISE EXCEPTION 'The shortfall to the next prize was %, expected 160 (the cap, 200, minus 40 points)',
      v->>'pointsToNext';
  END IF;

  IF (v->>'rewardsClaimed')::int <> 1 THEN
    RAISE EXCEPTION 'Prizes already received counted %, expected 1', v->>'rewardsClaimed';
  END IF;

  IF v->>'reachState' <> 'reachable' THEN
    RAISE EXCEPTION 'With a prize in reach the screen was told "%", expected "reachable"',
      v->>'reachState';
  END IF;
END;
$test$;

-- Each exclusion, one at a time: lift it and the count must move by exactly the
-- one prize behind it. A filter that is not load-bearing shows up here as a
-- count that did not change.
DO $test$
DECLARE
  v_before INT;
BEGIN
  PERFORM pg_temp.as_tejon();
  v_before := pg_temp.reachable();

  UPDATE rewards SET stock = 1 WHERE id = 'eeee0017-0000-4000-8000-000000000002';
  IF pg_temp.reachable() <> v_before + 1 THEN
    RAISE EXCEPTION 'Restocking a prize did not put it within reach: an out-of-stock prize is being counted, or stock is not';
  END IF;
  UPDATE rewards SET stock = 0 WHERE id = 'eeee0017-0000-4000-8000-000000000002';

  UPDATE rewards SET is_withdrawn = false WHERE id = 'eeee0017-0000-4000-8000-000000000004';
  IF pg_temp.reachable() <> v_before + 1 THEN
    RAISE EXCEPTION 'Un-withdrawing a prize did not put it within reach: withdrawal is not being respected (spec 021, R19a)';
  END IF;
  UPDATE rewards SET is_withdrawn = true WHERE id = 'eeee0017-0000-4000-8000-000000000004';

  UPDATE communities SET is_withdrawn = false WHERE id = 'aaaa0017-0000-4000-8000-00000000000c';
  IF pg_temp.reachable() <> v_before + 1 THEN
    RAISE EXCEPTION 'A prize of a withdrawn stand is not counted back when the stand returns: the stand is not being looked at (spec 023, R15)';
  END IF;
  UPDATE communities SET is_withdrawn = true WHERE id = 'aaaa0017-0000-4000-8000-00000000000c';

  DELETE FROM claimed_rewards
  WHERE participant_id = 'cccc0017-0000-4000-8000-000000000001'
    AND reward_id = 'eeee0017-0000-4000-8000-000000000006';
  IF pg_temp.reachable() <> v_before + 1 THEN
    RAISE EXCEPTION 'Forgetting a claim did not put the prize back within reach: prizes already taken home are being offered again';
  END IF;
  INSERT INTO claimed_rewards (participant_id, reward_id, confirmed_by)
  VALUES ('cccc0017-0000-4000-8000-000000000001', 'eeee0017-0000-4000-8000-000000000006',
          'aaaa0017-0000-4000-8000-00000000000b');

  UPDATE participants SET points = 200 WHERE id = 'cccc0017-0000-4000-8000-000000000001';
  IF pg_temp.reachable() <> v_before + 1 THEN
    RAISE EXCEPTION 'Affording the 200-point prize did not put it within reach: the balance is not being compared to the cost';
  END IF;
  UPDATE participants SET points = 40 WHERE id = 'cccc0017-0000-4000-8000-000000000001';

  IF pg_temp.reachable() <> v_before THEN
    RAISE EXCEPTION 'The fixtures were not restored: every later assertion is built on this';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Zero within reach is four different pieces of news, and the screen is told
-- which (spec 013, section 6).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v JSONB;
BEGIN
  PERFORM pg_temp.as_tejon();

  -- Nothing affordable yet: the shortfall is to the cheapest one they could
  -- still take home.
  UPDATE participants SET points = 5 WHERE id = 'cccc0017-0000-4000-8000-000000000001';
  v := participant_dashboard();
  IF v->>'reachState' <> 'short' OR (v->>'pointsToNext')::int <> 5 THEN
    RAISE EXCEPTION 'With 5 points the screen was told "%" and a shortfall of %, expected "short" and 5',
      v->>'reachState', v->>'pointsToNext';
  END IF;
  UPDATE participants SET points = 40 WHERE id = 'cccc0017-0000-4000-8000-000000000001';

  -- Barred from claiming (spec 022): the count is never the answer to give
  -- them, whatever the balance says.
  UPDATE participants SET claims_barred = true WHERE id = 'cccc0017-0000-4000-8000-000000000001';
  v := participant_dashboard();
  IF v->>'reachState' <> 'barred' OR NOT (v->>'claimsBarred')::boolean THEN
    RAISE EXCEPTION 'A barred attendee was told "%", expected "barred"', v->>'reachState';
  END IF;
  UPDATE participants SET claims_barred = false WHERE id = 'cccc0017-0000-4000-8000-000000000001';

  -- Everything in the catalogue already taken home.
  INSERT INTO claimed_rewards (participant_id, reward_id, confirmed_by)
  SELECT 'cccc0017-0000-4000-8000-000000000001', id, 'aaaa0017-0000-4000-8000-00000000000a'
  FROM rewards WHERE id IN ('eeee0017-0000-4000-8000-000000000001',
                            'eeee0017-0000-4000-8000-000000000002',
                            'eeee0017-0000-4000-8000-000000000003');
  v := participant_dashboard();
  IF v->>'reachState' <> 'all_claimed' THEN
    RAISE EXCEPTION 'With the whole catalogue claimed the screen was told "%", expected "all_claimed"',
      v->>'reachState';
  END IF;
  DELETE FROM claimed_rewards
  WHERE participant_id = 'cccc0017-0000-4000-8000-000000000001'
    AND reward_id <> 'eeee0017-0000-4000-8000-000000000006';

  -- Nothing left on any table: not the same news as having claimed it all, and
  -- not a shortfall either.
  UPDATE rewards SET stock = 0 WHERE id IN ('eeee0017-0000-4000-8000-000000000001',
                                            'eeee0017-0000-4000-8000-000000000003');
  v := participant_dashboard();
  IF v->>'reachState' <> 'none_available' THEN
    RAISE EXCEPTION 'With every prize out of stock the screen was told "%", expected "none_available"',
      v->>'reachState';
  END IF;
  UPDATE rewards SET stock = 5 WHERE id IN ('eeee0017-0000-4000-8000-000000000001',
                                            'eeee0017-0000-4000-8000-000000000003');

  -- An empty catalogue says so, instead of a zero that looks like a real count
  -- (spec 013, R12).
  UPDATE rewards SET is_withdrawn = true;
  v := participant_dashboard();
  IF v->>'reachState' <> 'none_published' OR (v->>'rewardsPublished')::int <> 0 THEN
    RAISE EXCEPTION 'With nothing published the screen was told "%" over % prizes, expected "none_published" over 0',
      v->>'reachState', v->>'rewardsPublished';
  END IF;
  UPDATE rewards SET is_withdrawn = (id = 'eeee0017-0000-4000-8000-000000000004');
END;
$test$;

-- ---------------------------------------------------------------------------
-- What is running right now (spec 013, R6). The state is derived, never stored
-- (52_activities.sql), so this is also the test that nothing here reads a
-- column that would have to be kept up to date by somebody.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v JSONB;
  v_running JSONB;
BEGIN
  PERFORM pg_temp.as_tejon();
  v := participant_dashboard();
  v_running := v->'running';

  IF jsonb_array_length(v_running) <> 1 THEN
    RAISE EXCEPTION 'The summary listed % activities, expected 1: the scheduled one, the expired one and the withdrawn stand''s one do not belong in it',
      jsonb_array_length(v_running);
  END IF;

  IF v_running->0->>'id' <> 'ffff0017-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'The summary listed the wrong activity: %', v_running->0->>'name';
  END IF;

  IF v_running->0->>'stand' <> 'Stand A' OR v_running->0->>'standNumber' <> '1' THEN
    RAISE EXCEPTION 'A running activity must say where to walk; it said "% (stand %)"',
      v_running->0->>'stand', v_running->0->>'standNumber';
  END IF;

  IF NOT (v_running->0->>'completed')::boolean THEN
    RAISE EXCEPTION 'Tejon completed this activity and the summary says otherwise';
  END IF;

  -- The expired one is the point of deriving the state: nothing closed it, and
  -- it still has to drop out on its own.
  UPDATE activities SET started_at = now() - INTERVAL '5 minutes'
  WHERE id = 'ffff0017-0000-4000-8000-000000000003';
  IF jsonb_array_length(participant_dashboard()->'running') <> 2 THEN
    RAISE EXCEPTION 'Restarting the expired activity did not make it current: the summary is not reading the derived state';
  END IF;
  UPDATE activities SET started_at = now() - INTERVAL '90 minutes'
  WHERE id = 'ffff0017-0000-4000-8000-000000000003';

  -- Finishing early takes it out at once (spec 019, R12).
  UPDATE activities SET finished_at = now()
  WHERE id = 'ffff0017-0000-4000-8000-000000000001';
  IF jsonb_array_length(participant_dashboard()->'running') <> 0 THEN
    RAISE EXCEPTION 'A finished activity is still being summarised as running';
  END IF;
  UPDATE activities SET finished_at = NULL
  WHERE id = 'ffff0017-0000-4000-8000-000000000001';

  -- A stand that left the fair is not a place to walk to (spec 023, R15).
  UPDATE communities SET is_withdrawn = false WHERE id = 'aaaa0017-0000-4000-8000-00000000000c';
  IF jsonb_array_length(participant_dashboard()->'running') <> 2 THEN
    RAISE EXCEPTION 'The withdrawn stand''s running activity is not excluded by its stand';
  END IF;
  UPDATE communities SET is_withdrawn = true WHERE id = 'aaaa0017-0000-4000-8000-00000000000c';
END;
$test$;

-- ---------------------------------------------------------------------------
-- Progress: both figures against a total, and the activity figure counting
-- completions rather than stands (spec 019 allows three per stand).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v JSONB;
BEGIN
  PERFORM pg_temp.as_tejon();
  v := participant_dashboard();

  -- Three visit scans, two of them to the same stand.
  IF (v->>'standsVisited')::int <> 2 THEN
    RAISE EXCEPTION 'Stands visited counted %, expected 2: a second visit to the same stand is not a second stand',
      v->>'standsVisited';
  END IF;

  IF (v->>'standsTotal')::int <> 3 THEN
    RAISE EXCEPTION 'The fair counted % stands, expected 3', v->>'standsTotal';
  END IF;

  IF (v->>'activitiesCompleted')::int <> 2 THEN
    RAISE EXCEPTION 'Activities completed counted %, expected 2: both completions are at the same stand, and it is activities that are being counted',
      v->>'activitiesCompleted';
  END IF;

  IF (v->>'activitiesPublished')::int <> 4 THEN
    RAISE EXCEPTION 'Activities published counted %, expected 4', v->>'activitiesPublished';
  END IF;

  IF (v->>'points')::int <> 40 THEN
    RAISE EXCEPTION 'The balance came back as %, expected 40', v->>'points';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Whose figures these are is decided by the session and by nothing else
-- (constitution IV, spec 013 R11).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v JSONB;
BEGIN
  -- The strongest form of the rule: there is no argument to pass. A screen
  -- cannot ask for somebody else's figures because there is nowhere to put the
  -- request.
  IF (SELECT pronargs FROM pg_proc WHERE proname = 'participant_dashboard') <> 0 THEN
    RAISE EXCEPTION 'participant_dashboard takes arguments: identity is never a parameter';
  END IF;

  PERFORM pg_temp.act_as('dddd0017-0000-4000-8000-000000000002');
  v := participant_dashboard();

  IF (v->>'points')::int <> 0 OR (v->>'standsVisited')::int <> 0
     OR (v->>'activitiesCompleted')::int <> 0 OR (v->>'rewardsClaimed')::int <> 0 THEN
    RAISE EXCEPTION 'Lobo was shown somebody else''s afternoon: %', v::text;
  END IF;

  -- Same catalogue, different balance, so a different answer: the cheapest
  -- prize is ten points away and nothing is within reach yet.
  IF (v->>'rewardsReachable')::int <> 0 OR v->>'reachState' <> 'short'
     OR (v->>'pointsToNext')::int <> 10 THEN
    RAISE EXCEPTION 'Lobo, with no points, was told % prizes within reach ("%", % points short), expected 0, "short" and 10',
      v->>'rewardsReachable', v->>'reachState', v->>'pointsToNext';
  END IF;

  IF (v->'running'->0->>'completed')::boolean THEN
    RAISE EXCEPTION 'Lobo was shown Tejon''s completion of the running activity';
  END IF;

  PERFORM pg_temp.no_session();
  v := participant_dashboard();
  IF NOT v ? 'error' THEN
    RAISE EXCEPTION 'The dashboard answered a caller with no session: %', v::text;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The screen changes nothing (spec 013, R13).
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_points INT;
  v_stock INT;
  v_scans INT;
  v_claims INT;
BEGIN
  SELECT points INTO v_points FROM participants WHERE id = 'cccc0017-0000-4000-8000-000000000001';
  SELECT COALESCE(SUM(stock), 0) INTO v_stock FROM rewards;
  SELECT count(*) INTO v_scans FROM scans;
  SELECT count(*) INTO v_claims FROM claimed_rewards;

  PERFORM pg_temp.as_tejon();
  PERFORM participant_dashboard();
  PERFORM participant_dashboard();

  IF (SELECT points FROM participants WHERE id = 'cccc0017-0000-4000-8000-000000000001') <> v_points THEN
    RAISE EXCEPTION 'Looking at the home screen changed a balance';
  END IF;
  IF (SELECT COALESCE(SUM(stock), 0) FROM rewards) <> v_stock THEN
    RAISE EXCEPTION 'Looking at the home screen moved stock';
  END IF;
  IF (SELECT count(*) FROM scans) <> v_scans
     OR (SELECT count(*) FROM claimed_rewards) <> v_claims THEN
    RAISE EXCEPTION 'Looking at the home screen awarded or claimed something';
  END IF;
END;
$test$;

ROLLBACK;
