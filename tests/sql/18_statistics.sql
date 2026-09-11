-- Event statistics (spec 031).
--
-- The whole feature is one read, so most of this file pins what that read says
-- and who is allowed to receive it. Two things carry the weight: a stand or a
-- participant asking directly gets nothing, and every figure agrees with the
-- data once the event is grouped in the fixed event timezone.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures. Nothing here depends on seed data.
-- ---------------------------------------------------------------------------

INSERT INTO organizers (id, username, password_hash, auth_user_id) VALUES
  ('0910031a-0000-4000-8000-000000000001', 'stats_org',
   crypt('Organiza2026*', gen_salt('bf', 12)), '0910031a-0000-4000-8000-000000000001');

INSERT INTO communities (id, username, password_hash, name, stand_number, is_withdrawn, auth_user_id) VALUES
  ('aaaa0031-0000-4000-8000-000000000001', 'stats_a', crypt('Stand2026*', gen_salt('bf', 12)), 'Stand Uno',  '1', false, 'aaaa0031-0000-4000-8000-000000000001'),
  ('aaaa0031-0000-4000-8000-000000000002', 'stats_b', crypt('Stand2026*', gen_salt('bf', 12)), 'Stand Dos',  '2', true,  'aaaa0031-0000-4000-8000-000000000002'),
  ('aaaa0031-0000-4000-8000-000000000003', 'stats_c', crypt('Stand2026*', gen_salt('bf', 12)), 'Stand Tres', '3', false, 'aaaa0031-0000-4000-8000-000000000003');

INSERT INTO participants (id, name, points, auth_user_id, is_removed, registered_at) VALUES
  ('cccc0031-0000-4000-8000-000000000001', 'Ana',  120, 'cccc0031-0000-4000-8000-000000000001', false, '2026-09-11 14:05:00+00'),
  ('cccc0031-0000-4000-8000-000000000002', 'Beto',   0, 'cccc0031-0000-4000-8000-000000000002', false, '2026-09-11 15:05:00+00'),
  ('cccc0031-0000-4000-8000-000000000003', 'Caro', 300, 'cccc0031-0000-4000-8000-000000000003', true,  '2026-09-11 14:30:00+00');

INSERT INTO activities (id, community_id, name, description, estimated_start, duration_min, is_main_event) VALUES
  ('ac100031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000001',
   'Taller', 'Taller de prueba', '10:00', 60, true);

INSERT INTO scans (id, participant_id, community_id, activity_id, points, type, created_at) VALUES
  ('51110031-0000-4000-8000-000000000001', 'cccc0031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000001', NULL, 30, 'visit',    '2026-09-11 14:10:00+00'),
  ('51110031-0000-4000-8000-000000000002', 'cccc0031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000001', 'ac100031-0000-4000-8000-000000000001', 100, 'activity', '2026-09-11 14:20:00+00'),
  ('51110031-0000-4000-8000-000000000003', 'cccc0031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000002', NULL, 30, 'visit',    '2026-09-11 15:10:00+00'),
  ('51110031-0000-4000-8000-000000000004', 'cccc0031-0000-4000-8000-000000000003', 'aaaa0031-0000-4000-8000-000000000001', NULL, 30, 'visit',    '2026-09-11 15:15:00+00'),
  ('51110031-0000-4000-8000-000000000005', 'cccc0031-0000-4000-8000-000000000003', 'aaaa0031-0000-4000-8000-000000000001', NULL, 30, 'visit',    '2026-09-11 15:20:00+00');

INSERT INTO rewards (id, community_id, name, cost, stock) VALUES
  ('eee10031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000001', 'Taza',  50, 3),
  ('eee10031-0000-4000-8000-000000000002', 'aaaa0031-0000-4000-8000-000000000001', 'Gorra', 200, 1),
  ('eee10031-0000-4000-8000-000000000003', 'aaaa0031-0000-4000-8000-000000000002', 'Libro', 30, 0);

INSERT INTO claimed_rewards (id, participant_id, reward_id, confirmed_by, claimed_at) VALUES
  ('c1a10031-0000-4000-8000-000000000001', 'cccc0031-0000-4000-8000-000000000001', 'eee10031-0000-4000-8000-000000000001', 'aaaa0031-0000-4000-8000-000000000001', '2026-09-11 16:10:00+00'),
  ('c1a10031-0000-4000-8000-000000000002', 'cccc0031-0000-4000-8000-000000000003', 'eee10031-0000-4000-8000-000000000002', 'aaaa0031-0000-4000-8000-000000000001', '2026-09-11 16:20:00+00');

INSERT INTO point_adjustments (participant_id, amount, reason, adjusted_at) VALUES
  ('cccc0031-0000-4000-8000-000000000002',  40, 'compensación', '2026-09-11 16:00:00+00'),
  ('cccc0031-0000-4000-8000-000000000002', -10, 'corrección',   '2026-09-11 16:05:00+00');

-- One code per closure state. The open one was last seen two hours ago, so it
-- is expired without needing to fake the clock.
INSERT INTO claim_codes (participant_id, code, issued_at, last_seen_at, closed_at, closed_reason) VALUES
  ('cccc0031-0000-4000-8000-000000000001', 'AAAAAA', '2026-09-11 14:00:00+00', now(), now(), 'used'),
  ('cccc0031-0000-4000-8000-000000000002', 'BBBBBB', '2026-09-11 14:30:00+00', now(), now(), 'replaced'),
  ('cccc0031-0000-4000-8000-000000000003', 'CCCCCC', '2026-09-11 15:00:00+00', now() - interval '2 hours', NULL, NULL);

-- Refusals, written the way the system writes them, so the grouping has
-- something real to group.
DO $fixture$
BEGIN
  PERFORM audit(p_action => 'scan.award', p_outcome => 'refused',
                p_actor_kind => 'participant', p_actor_id => 'cccc0031-0000-4000-8000-000000000001',
                p_reason => 'cooldown');
  PERFORM audit(p_action => 'scan.award', p_outcome => 'refused',
                p_actor_kind => 'participant', p_actor_id => 'cccc0031-0000-4000-8000-000000000001',
                p_reason => 'cooldown');
  PERFORM audit(p_action => 'claim.handover', p_outcome => 'refused',
                p_actor_kind => 'stand', p_actor_id => 'aaaa0031-0000-4000-8000-000000000001',
                p_reason => 'sin stock');
END;
$fixture$;

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

CREATE FUNCTION pg_temp.as_organizer() RETURNS void LANGUAGE sql AS $fn$
  SELECT pg_temp.act_as('0910031a-0000-4000-8000-000000000001')
$fn$;

-- ---------------------------------------------------------------------------
-- Only the organiser reads. Hiding the screen is not the control: the refusal
-- happens where the figures are served.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE r JSONB;
BEGIN
  PERFORM pg_temp.no_session();
  r := event_statistics();
  IF r->>'error' IS DISTINCT FROM 'No autorizado' THEN
    RAISE EXCEPTION 'Statistics was readable with no session: %', r;
  END IF;

  PERFORM pg_temp.act_as('cccc0031-0000-4000-8000-000000000001');
  r := event_statistics();
  IF r->>'error' IS DISTINCT FROM 'No autorizado' THEN
    RAISE EXCEPTION 'A participant read the whole event''s statistics: %', r;
  END IF;

  PERFORM pg_temp.act_as('aaaa0031-0000-4000-8000-000000000001');
  r := event_statistics();
  IF r->>'error' IS DISTINCT FROM 'No autorizado' THEN
    RAISE EXCEPTION 'A stand read every other stand''s statistics: %', r;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Every figure, against the fixtures.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  r JSONB;
  v JSONB;
  t JSONB;
BEGIN
  PERFORM pg_temp.as_organizer();
  r := event_statistics();

  IF r ? 'error' THEN
    RAISE EXCEPTION 'The organiser was refused: %', r;
  END IF;

  -- Timeline: three hourly buckets in America/La_Paz (UTC-4). 14:10Z -> 10:00.
  IF jsonb_array_length(r->'attendance'->'timeline') <> 3 THEN
    RAISE EXCEPTION 'Expected three hourly buckets, got %', r->'attendance'->'timeline';
  END IF;

  t := r->'attendance'->'timeline'->0;
  IF t->>'bucket' <> '2026-09-11T10:00'
     OR (t->>'visits')::int <> 1
     OR (t->>'activities')::int <> 1
     OR (t->>'activeParticipants')::int <> 1
     OR (t->>'registrations')::int <> 2 THEN
    RAISE EXCEPTION 'The 10:00 bucket is wrong: %', t;
  END IF;

  t := r->'attendance'->'timeline'->1;
  IF t->>'bucket' <> '2026-09-11T11:00'
     OR (t->>'visits')::int <> 3
     OR (t->>'activeParticipants')::int <> 2
     OR (t->>'cumulativePointsAwarded')::int <> 220 THEN
    RAISE EXCEPTION 'The 11:00 bucket is wrong: %', t;
  END IF;

  t := r->'attendance'->'timeline'->2;
  IF t->>'bucket' <> '2026-09-11T12:00'
     OR (t->>'visits')::int <> 0
     OR (t->>'pointsSpent')::int <> 250
     OR (t->>'cumulativePointsAwarded')::int <> 220 THEN
    RAISE EXCEPTION 'The 12:00 bucket is wrong: %', t;
  END IF;

  -- Bounds measure scans, not registrations or handovers.
  IF (r->'attendance'->'bounds'->>'firstScan')::timestamptz <> '2026-09-11 14:10:00+00'::timestamptz
     OR (r->'attendance'->'bounds'->>'durationMinutes')::int <> 70 THEN
    RAISE EXCEPTION 'The event bounds are wrong: %', r->'attendance'->'bounds';
  END IF;

  -- Stands, split by scan kind and ordered by points.
  IF r->'stands'->0->>'name' <> 'Stand Uno'
     OR (r->'stands'->0->>'totalPoints')::int <> 190
     OR (r->'stands'->0->>'visits')::int <> 3
     OR (r->'stands'->0->>'activities')::int <> 1
     OR (r->'stands'->0->>'avgPoints')::numeric <> 47.5 THEN
    RAISE EXCEPTION 'Stand Uno aggregated wrong: %', r->'stands'->0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(r->'stands') e
    WHERE e->>'name' = 'Stand Dos' AND (e->>'withdrawn')::boolean
      AND (e->>'totalPoints')::int = 30
  ) THEN
    RAISE EXCEPTION 'A withdrawn stand must still appear, labelled: %', r->'stands';
  END IF;

  -- Adjustments are their own figure, never folded into a stand.
  IF (r->'adjustments'->>'total')::int <> 30 OR (r->'adjustments'->>'count')::int <> 2 THEN
    RAISE EXCEPTION 'Manual adjustments aggregated wrong: %', r->'adjustments';
  END IF;
  IF (r->'stands'->0->>'totalPoints')::int <> 190 THEN
    RAISE EXCEPTION 'A manual adjustment leaked into a stand''s points: %', r->'stands'->0;
  END IF;

  -- Rewards: two handed over, and stock is what remains.
  IF (SELECT count(*) FROM jsonb_array_elements(r->'rewards') e WHERE (e->>'handedOver')::int > 0) <> 2 THEN
    RAISE EXCEPTION 'Reward handover counts are wrong: %', r->'rewards';
  END IF;
  SELECT e INTO v FROM jsonb_array_elements(r->'rewards') e WHERE e->>'id' = 'eee10031-0000-4000-8000-000000000001';
  IF (v->>'handedOver')::int <> 1 OR (v->>'pointsSpent')::int <> 50 OR (v->>'remaining')::int <> 3 THEN
    RAISE EXCEPTION 'Taza''s figures are wrong: %', v;
  END IF;
  SELECT e INTO v FROM jsonb_array_elements(r->'rewards') e WHERE e->>'id' = 'eee10031-0000-4000-8000-000000000003';
  IF (v->>'handedOver')::int <> 0 THEN
    RAISE EXCEPTION 'A never-claimed reward does not read as such: %', v;
  END IF;

  IF r->'handoversPerHour'->0->>'bucket' <> '2026-09-11T12:00'
     OR (r->'handoversPerHour'->0->>'count')::int <> 2 THEN
    RAISE EXCEPTION 'Handovers per hour is wrong: %', r->'handoversPerHour';
  END IF;

  -- Participants.
  SELECT e INTO v FROM jsonb_array_elements(r->'participants'->'balanceBands') e WHERE e->>'band' = '0';
  IF (v->>'count')::int <> 1 THEN RAISE EXCEPTION 'The 0-point band is wrong: %', r->'participants'->'balanceBands'; END IF;
  SELECT e INTO v FROM jsonb_array_elements(r->'participants'->'balanceBands') e WHERE e->>'band' = '100-149';
  IF (v->>'count')::int <> 1 THEN RAISE EXCEPTION 'The 100-149 band is wrong: %', r->'participants'->'balanceBands'; END IF;
  SELECT e INTO v FROM jsonb_array_elements(r->'participants'->'balanceBands') e WHERE e->>'band' = '300+';
  IF (v->>'count')::int <> 1 THEN RAISE EXCEPTION 'The 300+ band is wrong: %', r->'participants'->'balanceBands'; END IF;

  SELECT e INTO v FROM jsonb_array_elements(r->'participants'->'standsVisited') e WHERE (e->>'standsVisited')::int = 2;
  IF (v->>'count')::int <> 1 THEN RAISE EXCEPTION 'Stands-visited distribution is wrong: %', r->'participants'->'standsVisited'; END IF;

  IF (r->'participants'->>'registeredWithoutScan')::int <> 1 THEN
    RAISE EXCEPTION 'Registered-without-scan is wrong: %', r->'participants'->>'registeredWithoutScan';
  END IF;

  IF r->'participants'->'top'->0->>'name' <> 'Caro'
     OR NOT (r->'participants'->'top'->0->>'removed')::boolean THEN
    RAISE EXCEPTION 'The top table is wrong: %', r->'participants'->'top';
  END IF;

  -- Refusals grouped by reason.
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(r->'operations'->'refusals') e
    WHERE e->>'action' = 'scan.award' AND e->>'reason' = 'cooldown' AND (e->>'count')::int = 2
  ) THEN
    RAISE EXCEPTION 'Refusals grouped wrong: %', r->'operations'->'refusals';
  END IF;

  -- Claim codes, including the derived "expired".
  IF (r->'operations'->'claimCodes'->>'issued')::int <> 3
     OR (r->'operations'->'claimCodes'->>'used')::int <> 1
     OR (r->'operations'->'claimCodes'->>'replaced')::int <> 1
     OR (r->'operations'->'claimCodes'->>'expired')::int <> 1 THEN
    RAISE EXCEPTION 'Claim-code counts are wrong: %', r->'operations'->'claimCodes';
  END IF;

  -- Call-outs cover the same filtered data.
  IF r->'callouts'->'busiestHour'->>'bucket' <> '2026-09-11T11:00' THEN
    RAISE EXCEPTION 'Busiest hour is wrong: %', r->'callouts'->'busiestHour';
  END IF;
  IF r->'callouts'->'topStandByPoints'->>'stand' <> 'Stand Uno' THEN
    RAISE EXCEPTION 'Top stand is wrong: %', r->'callouts'->'topStandByPoints';
  END IF;
  IF r->'callouts'->'mostHandedOverReward'->>'reward' <> 'Gorra' THEN
    RAISE EXCEPTION 'Most-handed-over reward is wrong: %', r->'callouts'->'mostHandedOverReward';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(r->'callouts'->'standsWithoutScans') e
    WHERE e->>'stand' = 'Stand Tres'
  ) THEN
    RAISE EXCEPTION 'A stand with no scans is missing from the call-outs: %', r->'callouts'->'standsWithoutScans';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The filter moves every figure together.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE r JSONB;
BEGIN
  PERFORM pg_temp.as_organizer();
  r := event_statistics('2026-09-11 14:00:00+00', '2026-09-11 15:00:00+00');

  IF jsonb_array_length(r->'attendance'->'timeline') <> 1 THEN
    RAISE EXCEPTION 'The window should collapse to one hourly bucket: %', r->'attendance'->'timeline';
  END IF;

  IF (r->'attendance'->'timeline'->0->>'visits')::int <> 1
     OR (r->'attendance'->'timeline'->0->>'activities')::int <> 1
     OR (r->'attendance'->'timeline'->0->>'pointsSpent')::int <> 0 THEN
    RAISE EXCEPTION 'The windowed bucket is wrong: %', r->'attendance'->'timeline'->0;
  END IF;

  IF (SELECT COALESCE(sum((e->>'handedOver')::int), 0) FROM jsonb_array_elements(r->'rewards') e) <> 0 THEN
    RAISE EXCEPTION 'Handovers outside the window leaked in: %', r->'rewards';
  END IF;

  IF (r->'adjustments'->>'count')::int <> 0 THEN
    RAISE EXCEPTION 'Adjustments outside the window leaked in: %', r->'adjustments';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A window with nothing in it is empty, not broken.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE r JSONB;
BEGIN
  PERFORM pg_temp.as_organizer();
  r := event_statistics('2027-01-01 00:00:00+00', '2027-01-02 00:00:00+00');

  IF r ? 'error' THEN
    RAISE EXCEPTION 'An empty window produced an error: %', r;
  END IF;
  IF jsonb_array_length(r->'attendance'->'timeline') <> 0 THEN
    RAISE EXCEPTION 'An empty window has a timeline: %', r->'attendance'->'timeline';
  END IF;
  -- Every stand still appears, at zero: the screen must not lose a stand just
  -- because nothing happened in the chosen window.
  IF jsonb_array_length(r->'stands') <> 3 THEN
    RAISE EXCEPTION 'An empty window dropped the stands: %', r->'stands';
  END IF;
  IF r->'callouts'->'busiestHour' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'An empty window invented a busiest hour: %', r->'callouts'->'busiestHour';
  END IF;
  IF (r->'operations'->'claimCodes'->>'issued')::int <> 0 THEN
    RAISE EXCEPTION 'An empty window counted claim codes: %', r->'operations'->'claimCodes';
  END IF;
END;
$test$;

ROLLBACK;
