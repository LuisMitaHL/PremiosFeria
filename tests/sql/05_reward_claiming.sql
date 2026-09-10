-- Reward claiming, as it happens at the stand (spec 018).
--
-- The exchange moved to where the prize actually changes hands: the student
-- shows a one-use code, the stand picks one of its own prizes and confirms, and
-- only then are points spent and stock reduced. Two things carry the weight:
--
--   * The claim code is the only identifier the system accepts as "who". Every
--     safeguard sits on it -- single use, one live at a time, short life,
--     unguessable -- because a readable or reusable code is the ability to
--     spend somebody else's points.
--   * The exchange is one indivisible step. The real gates are the conditional
--     writes -- UPDATE ... WHERE stock > 0, WHERE points >= cost, WHERE
--     closed_at IS NULL -- so a prize is never handed over unpaid and points
--     are never taken for a prize that stayed on the table (constitution VI).
--
-- Nothing here waits on the clock. Expiry is exercised by moving last_seen_at
-- into the past, which is what a phone that stopped asking looks like.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0005-0000-4000-8000-000000000001', 'test_fulfil_a', 'Fulfilment Stand A',
        'aaaa0005-0000-4000-8000-000000000001'),
       ('aaaa0005-0000-4000-8000-000000000002', 'test_fulfil_b', 'Fulfilment Stand B',
        'aaaa0005-0000-4000-8000-000000000002');

INSERT INTO rewards (id, community_id, name, cost, stock, is_withdrawn)
VALUES ('cccc0005-0000-4000-8000-000000000001', 'aaaa0005-0000-4000-8000-000000000001',
        'Polera', 100, 2, false),
       ('cccc0005-0000-4000-8000-000000000002', 'aaaa0005-0000-4000-8000-000000000001',
        'Agotado', 50, 0, false),
       ('cccc0005-0000-4000-8000-000000000003', 'aaaa0005-0000-4000-8000-000000000001',
        'Caro', 300, 5, false),
       ('cccc0005-0000-4000-8000-000000000004', 'aaaa0005-0000-4000-8000-000000000001',
        'Retirado', 10, 5, true),
       ('cccc0005-0000-4000-8000-000000000005', 'aaaa0005-0000-4000-8000-000000000001',
        'Barato', 10, 1, false),
       ('cccc0005-0000-4000-8000-000000000006', 'aaaa0005-0000-4000-8000-000000000002',
        'Ajeno', 10, 5, false),
       ('cccc0005-0000-4000-8000-000000000007', 'aaaa0005-0000-4000-8000-000000000001',
        'Taza', 20, 3, false);

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0005-0000-4000-8000-000000000001', 'Rich Tester', 300,
        'bbbb0005-0000-4000-8000-000000000001'),
       ('bbbb0005-0000-4000-8000-000000000002', 'Poor Tester', 10,
        'bbbb0005-0000-4000-8000-000000000002');

-- Identity is never a parameter (constitution IV), so acting as somebody means
-- setting the claims PostgREST would have set.
CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

-- Obtain a code as a given student and hand back the code itself.
--
-- The backdating is a fixture detail, not a rule: now() is frozen for the whole
-- transaction, so every code issued in this file would share one issued_at and
-- "the student's latest code" would be a coin toss. Pushing the earlier rows
-- back reproduces the ordering that real elapsed time gives in production.
CREATE FUNCTION pg_temp.issue_for(p_uid UUID) RETURNS TEXT LANGUAGE plpgsql AS $fn$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as(p_uid);

  UPDATE claim_codes SET issued_at = issued_at - INTERVAL '1 minute'
  WHERE participant_id = (SELECT id FROM participants WHERE auth_user_id = p_uid);

  v_res := issue_claim_code();
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A student could not obtain a claim code, so nobody can collect a prize at all: %',
      v_res->>'error';
  END IF;
  RETURN v_res->>'code';
END;
$fn$;

CREATE FUNCTION pg_temp.code_is_live(p_code TEXT) RETURNS BOOLEAN LANGUAGE sql AS $fn$
  SELECT COALESCE((SELECT claim_code_is_live(c) FROM claim_codes c
                   WHERE c.code = p_code ORDER BY c.issued_at DESC LIMIT 1), false)
$fn$;

-- Move a code's screen into the past: this is a phone that locked, an app that
-- was closed, or a network that dropped. No test ever waits.
CREATE FUNCTION pg_temp.last_seen_ago(p_code TEXT, p_ago INTERVAL) RETURNS void
LANGUAGE sql AS $fn$
  UPDATE claim_codes SET last_seen_at = now() - p_ago
  WHERE code = p_code AND closed_at IS NULL
$fn$;

-- ---------------------------------------------------------------------------
-- Asking for a code commits nothing (R6, R16). Browsing and showing a code are
-- free; charging before the prize is in the student's hands is the failure this
-- whole spec exists to remove.
DO $test$
DECLARE
  v_code TEXT;
  v_points INT;
  v_stock INT;
  v_claims INT;
BEGIN
  v_code := pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000001');

  SELECT points INTO v_points FROM participants
  WHERE id = 'bbbb0005-0000-4000-8000-000000000001';
  SELECT stock INTO v_stock FROM rewards
  WHERE id = 'cccc0005-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_claims FROM claimed_rewards;

  IF v_points <> 300 THEN
    RAISE EXCEPTION 'Generating a claim code moved the balance from 300 to %. Points must only be spent when the prize is handed over',
      v_points;
  END IF;
  IF v_stock <> 2 THEN
    RAISE EXCEPTION 'Generating a claim code moved the stock of Polera from 2 to %. A code reserves nothing, or a student who never arrives makes a prize unavailable to the one standing there',
      v_stock;
  END IF;
  IF v_claims <> 0 THEN
    RAISE EXCEPTION 'Generating a claim code recorded % claim(s). Nothing has been handed over yet',
      v_claims;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The code is readable across a table and typed on another phone (R2). Six
-- characters, and none of the pairs people get wrong: O/0 and I/1/L. Every
-- ambiguity costs a failed attempt in front of a queue.
DO $test$
DECLARE
  v_code TEXT;
  v_codes TEXT[] := '{}';
  v_distinct INT;
BEGIN
  FOR i IN 1..200 LOOP
    v_code := generate_claim_code();

    IF char_length(v_code) <> 6 THEN
      RAISE EXCEPTION 'A claim code is % characters long ("%"), not 6. The stands are used to typing six',
        char_length(v_code), v_code;
    END IF;
    IF v_code ~ '[O0I1L]' THEN
      RAISE EXCEPTION 'The claim code "%" contains one of O, 0, I, 1 or L. Those are the characters people misread off a screen, and each one is a failed handover in front of a queue',
        v_code;
    END IF;
    IF v_code !~ '^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$' THEN
      RAISE EXCEPTION 'The claim code "%" is outside the agreed alphabet of uppercase letters and digits',
        v_code;
    END IF;

    v_codes := v_codes || v_code;
  END LOOP;

  SELECT count(DISTINCT c) INTO v_distinct FROM unnest(v_codes) AS c;
  IF v_distinct <> 200 THEN
    RAISE EXCEPTION '200 generated codes produced only % distinct values. Codes that collide let one student spend another student''s points',
      v_distinct;
  END IF;
END;
$test$;

-- Two students never share a code, and a code is not derived from who asked for
-- it (R7): a code guessable from an identity lets a stand spend the points of
-- somebody who never came to it.
DO $test$
DECLARE
  v_rich TEXT;
  v_poor TEXT;
BEGIN
  SELECT code INTO v_rich FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;
  v_poor := pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000002');

  IF v_rich = v_poor THEN
    RAISE EXCEPTION 'Two students hold the same live claim code ("%"). Either one can spend the other''s points',
      v_rich;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The student's own screen. It asks about its own code, resolved from the
-- session, and each question renews the tolerance that keeps the code alive.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
  v_seen TIMESTAMPTZ;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('bbbb0005-0000-4000-8000-000000000001');
  v_res := poll_my_claim_code();

  IF v_res->>'state' <> 'live' THEN
    RAISE EXCEPTION 'A freshly issued code polls as "%", not "live". The student is holding up a code the stand will refuse',
      v_res->>'state';
  END IF;
  IF v_res->>'code' <> v_code THEN
    RAISE EXCEPTION 'The claim screen shows "%" while the live code is "%". The student would read out a code that does not work',
      v_res->>'code', v_code;
  END IF;
  IF (v_res->>'points')::int <> 300 THEN
    RAISE EXCEPTION 'The claim screen reports % points against a balance of 300',
      (v_res->>'points')::int;
  END IF;

  -- A screen still asking, 30 seconds inside the grace period, keeps its code.
  PERFORM pg_temp.last_seen_ago(v_code, INTERVAL '30 seconds');
  v_res := poll_my_claim_code();
  IF v_res->>'state' <> 'live' THEN
    RAISE EXCEPTION 'A code polled 30 seconds after the last poll came back "%". The grace period is 60 seconds, so a phone that locks briefly must not lose its code',
      v_res->>'state';
  END IF;

  SELECT last_seen_at INTO v_seen FROM claim_codes WHERE code = v_code AND closed_at IS NULL;
  IF v_seen < now() THEN
    RAISE EXCEPTION 'Polling did not renew last_seen_at, so a code dies 60 seconds after it is issued even while the student is staring at it';
  END IF;
END;
$test$;

-- The screen never says who is asking. If poll_my_claim_code took an argument,
-- anyone could read anyone's live code and spend their points.
DO $test$
DECLARE
  v_bad INT;
  v_res JSONB;
  v_rich TEXT;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('poll_my_claim_code', 'issue_claim_code')
    AND p.pronargs > 0;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '% overload(s) of issue_claim_code/poll_my_claim_code take an argument. Identity is resolved from the session, never passed in: a student id parameter is a way to read somebody else''s live code',
      v_bad;
  END IF;

  SELECT code INTO v_rich FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('bbbb0005-0000-4000-8000-000000000002');
  v_res := poll_my_claim_code();
  IF v_res->>'code' = v_rich THEN
    RAISE EXCEPTION 'One student''s claim screen showed another student''s code';
  END IF;

  -- Somebody with a session but no profile has nothing to poll.
  PERFORM pg_temp.act_as('dddd0005-0000-4000-8000-00000000dead');
  v_res := poll_my_claim_code();
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A caller with no participant profile got a claim state back: %', v_res::text;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A stand may only give away what is on its own table (R11, R12). The absence
-- of a button proves nothing: a stand admin holds a session and can call the
-- RPC directly.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  -- Stand B reaching for a prize that sits on Stand A's table.
  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000002');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000001');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A stand confirmed the handover of another stand''s prize. It just deducted points for something it cannot hand over';
  END IF;

  -- And the same in the other direction.
  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000006');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A stand confirmed the handover of another stand''s prize. It just deducted points for something it cannot hand over';
  END IF;
  IF v_res->>'reason' NOT LIKE '%premios de tu stand%' THEN
    RAISE EXCEPTION 'The stand was refused with "%" instead of being told the prize is not theirs. A refusal nobody can act on stalls the queue',
      v_res->>'reason';
  END IF;

  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 300
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000001') <> 2
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000006') <> 5
     OR (SELECT count(*) FROM claimed_rewards) <> 0 THEN
    RAISE EXCEPTION 'A handover refused for belonging to another stand still moved points, stock or claims';
  END IF;

  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A refusal burned the student''s code. The student did nothing wrong and must not have to generate a new one';
  END IF;

  -- No session, no handover.
  PERFORM set_config('request.jwt.claims', '', true);
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000001');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A caller with no session confirmed a handover and spent a student''s points';
  END IF;
END;
$test$;

-- A withdrawn prize is off the table. It still exists, so a claim already
-- confirmed keeps pointing at something real, but it cannot be handed over.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000004');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A withdrawn prize was handed over even though the organiser pulled it from the display';
  END IF;

  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 300
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000004') <> 5
     OR (SELECT count(*) FROM claimed_rewards) <> 0 THEN
    RAISE EXCEPTION 'A refused handover of a withdrawn prize still moved points, stock or claims';
  END IF;
  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A refusal on a withdrawn prize burned the student''s code';
  END IF;
END;
$test$;

-- Out of stock is a refusal that changes nothing (R15).
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
  v_stock INT;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000002');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A prize with zero stock was handed over. There is nothing on the table to give';
  END IF;
  IF v_res->>'reason' NOT LIKE '%No quedan unidades%' AND v_res->>'reason' NOT LIKE '%Ya no quedan unidades%' THEN
    RAISE EXCEPTION 'An out-of-stock refusal read "%" instead of saying the prize has run out. The stand cannot act on it',
      v_res->>'reason';
  END IF;

  SELECT stock INTO v_stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000002';
  IF v_stock <> 0 THEN
    RAISE EXCEPTION 'The stock of an out-of-stock prize is % after a refused handover', v_stock;
  END IF;
  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 300
     OR (SELECT count(*) FROM claimed_rewards) <> 0 THEN
    RAISE EXCEPTION 'A handover refused for lack of stock still moved points or recorded a claim';
  END IF;
  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A refusal for lack of stock burned the student''s code';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Short of points: a refusal that is the student's situation, not a mistake.
-- Nothing moves and the code stays usable -- they can walk to a cheaper prize
-- with the code already on their screen.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
  v_points INT;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000002' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000003');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A 300-point prize was handed over against a 10-point balance';
  END IF;
  -- A shortfall is the student's situation, not a fault, and the stand has to
  -- be able to say how far off they are. A raw database error here means the
  -- friendly gate in front of the conditional write is gone.
  IF v_res->>'reason' NOT LIKE '%290%' THEN
    RAISE EXCEPTION 'A student 290 points short was refused with "%", which does not name the shortfall. The stand cannot tell them how many points they still need',
      v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants
  WHERE id = 'bbbb0005-0000-4000-8000-000000000002';
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'A handover refused for lack of points still moved the balance, now %', v_points;
  END IF;
  IF (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000003') <> 5
     OR (SELECT count(*) FROM claimed_rewards) <> 0 THEN
    RAISE EXCEPTION 'A handover refused for lack of points still moved stock or recorded a claim';
  END IF;

  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A student short of points lost their code. They did nothing wrong, and the code has to still work for a prize they can afford';
  END IF;

  -- The same code, still on the same screen, buys something affordable. The
  -- stand types it by hand, so case and stray spaces must not matter.
  v_res := confirm_handover('  ' || lower(v_code) || ' ', 'cccc0005-0000-4000-8000-000000000005');
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'The code that survived a shortfall refusal did not work on an affordable prize: %',
      v_res->>'reason';
  END IF;

  SELECT points INTO v_points FROM participants
  WHERE id = 'bbbb0005-0000-4000-8000-000000000002';
  IF v_points <> 0 THEN
    RAISE EXCEPTION 'A 10-point prize against a 10-point balance left % points', v_points;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The exchange itself (R14). Exactly the cost, exactly one unit, together, and
-- a record of which stand handed it over.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
  v_points INT;
  v_stock INT;
  v_by UUID;
  v_claims INT;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000001');
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A stand could not hand over its own prize to a student who could afford it: %',
      v_res->>'reason';
  END IF;

  IF v_res->>'reward' <> 'Polera' OR (v_res->>'cost')::int <> 100
     OR v_res->>'participant' <> 'Rich Tester' THEN
    RAISE EXCEPTION 'The confirmation did not describe what was handed over: %', v_res::text;
  END IF;
  IF (v_res->>'newPoints')::int <> 200 THEN
    RAISE EXCEPTION 'A 100-point handover against a 300-point balance reported % points back to the stand',
      (v_res->>'newPoints')::int;
  END IF;

  SELECT points INTO v_points FROM participants
  WHERE id = 'bbbb0005-0000-4000-8000-000000000001';
  SELECT stock INTO v_stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000001';
  IF v_points <> 200 THEN
    RAISE EXCEPTION 'The balance is % after a 100-point handover from 300. Points and stock move together or not at all',
      v_points;
  END IF;
  IF v_stock <> 1 THEN
    RAISE EXCEPTION 'The stock of Polera is % after one handover from 2. Points and stock move together or not at all',
      v_stock;
  END IF;

  SELECT count(*) INTO v_claims FROM claimed_rewards
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001'
    AND reward_id = 'cccc0005-0000-4000-8000-000000000001';
  SELECT confirmed_by INTO v_by FROM claimed_rewards
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001'
    AND reward_id = 'cccc0005-0000-4000-8000-000000000001';
  IF v_claims <> 1 THEN
    RAISE EXCEPTION 'One confirmed handover recorded % claim rows', v_claims;
  END IF;
  IF v_by IS DISTINCT FROM 'aaaa0005-0000-4000-8000-000000000001'::uuid THEN
    RAISE EXCEPTION 'The claim does not record the stand that handed the prize over (confirmed_by is %). Nobody can say afterwards who gave it away',
      COALESCE(v_by::text, 'null');
  END IF;

  -- The code is consumed in the same step.
  IF pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'The code is still live after the prize was handed over. A photograph of that screen is now worth a second prize';
  END IF;
  IF (SELECT closed_reason FROM claim_codes WHERE code = v_code) <> 'used' THEN
    RAISE EXCEPTION 'A consumed code was not closed as "used", so the student''s screen cannot tell them what they received';
  END IF;
END;
$test$;

-- A code is good for exactly one exchange (R3). The retry below picks a prize
-- that is affordable, in stock, owned by this stand and never claimed: the only
-- thing wrong with it is the code.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_reason = 'used';

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000007');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A used code bought a second prize. Anyone who photographed that screen can spend the student''s points';
  END IF;
  IF v_res->>'reason' NOT LIKE '%digo inv%' THEN
    RAISE EXCEPTION 'A used code was refused with "%" instead of telling the stand the code is no longer valid',
      v_res->>'reason';
  END IF;

  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 200
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000007') <> 3 THEN
    RAISE EXCEPTION 'A handover refused for a used code still moved points or stock';
  END IF;
END;
$test$;

-- The student's screen learns what happened without being told by the stand.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as('bbbb0005-0000-4000-8000-000000000001');
  v_res := poll_my_claim_code();

  IF v_res->>'state' <> 'used' THEN
    RAISE EXCEPTION 'After the handover the claim screen polls as "%", not "used". It would sit there showing a dead code',
      v_res->>'state';
  END IF;
  IF v_res->>'reward' <> 'Polera' THEN
    RAISE EXCEPTION 'The claim screen closed on "%" instead of the prize that was handed over',
      COALESCE(v_res->>'reward', 'nothing');
  END IF;
  IF (v_res->>'points')::int <> 200 THEN
    RAISE EXCEPTION 'The claim screen reports % points after a 100-point handover from 300',
      (v_res->>'points')::int;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The same prize twice, to the same student (R17). Stock is limited so that
-- prizes spread across people.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  v_code := pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000001');

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000001');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'The same student collected the same prize twice, taking a unit meant for somebody else';
  END IF;
  IF v_res->>'reason' NOT LIKE '%ya canj%' THEN
    RAISE EXCEPTION 'A duplicate claim was refused with "%" instead of saying the student already collected this prize',
      v_res->>'reason';
  END IF;

  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 200
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000001') <> 1
     OR (SELECT count(*) FROM claimed_rewards
         WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001'
           AND reward_id = 'cccc0005-0000-4000-8000-000000000001') <> 1 THEN
    RAISE EXCEPTION 'A refused duplicate handover still moved points, stock or claims';
  END IF;
  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A duplicate refusal burned the code. The student can still collect something else with it';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- One live code per student (R4), and asking again does not create a second one
-- (R4a). Two live codes let a student stand at two stands and have both
-- confirmed against a balance that only covers one -- and a screen that
-- remounts, or a double tap, is exactly how a second one gets issued. Returning
-- the code already on screen is what keeps the one the student is showing the
-- one the stand will accept.
DO $test$
DECLARE
  v_first TEXT;
  v_again TEXT;
  v_rows INT;
  v_open INT;
  v_seen TIMESTAMPTZ;
BEGIN
  SELECT code INTO v_first FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;
  SELECT count(*) INTO v_rows FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001';

  -- The screen remounts and asks again while the student is holding the phone
  -- up at the counter.
  v_again := pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000001');
  IF v_again <> v_first THEN
    RAISE EXCEPTION 'Asking again while a code was live returned a different code ("%" then "%"). The student is showing the stand the old one, which no longer works',
      v_first, v_again;
  END IF;

  IF (SELECT count(*) FROM claim_codes
      WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001') <> v_rows THEN
    RAISE EXCEPTION 'Asking again while a code was live issued a second code. Whichever one ends up open is then not necessarily the one on the screen';
  END IF;

  SELECT count(*) INTO v_open FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;
  IF v_open <> 1 THEN
    RAISE EXCEPTION 'A student holds % open claim codes. Two live codes let one balance pay for two prizes at two stands',
      v_open;
  END IF;

  -- Asking again also counts as the screen still being there.
  PERFORM pg_temp.last_seen_ago(v_first, INTERVAL '30 seconds');
  PERFORM pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000001');
  SELECT last_seen_at INTO v_seen FROM claim_codes WHERE code = v_first AND closed_at IS NULL;
  IF v_seen < now() THEN
    RAISE EXCEPTION 'Reopening the claim screen did not renew the tolerance, so a code can die under a student who is actively looking at it';
  END IF;
END;
$test$;

-- A code that is no longer live IS replaced, and the dead one does not come
-- back (R4b). This is the branch that ends a code somebody photographed.
DO $test$
DECLARE
  v_old TEXT;
  v_new TEXT;
  v_open INT;
  v_res JSONB;
BEGIN
  SELECT code INTO v_old FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  -- The student closed the app; the screen stopped asking a minute ago.
  PERFORM pg_temp.last_seen_ago(v_old, INTERVAL '61 seconds');

  v_new := pg_temp.issue_for('bbbb0005-0000-4000-8000-000000000001');
  IF v_new = v_old THEN
    RAISE EXCEPTION 'Asking for a code after the previous one expired handed back the expired one. A code somebody photographed would start working again';
  END IF;

  SELECT count(*) INTO v_open FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;
  IF v_open <> 1 THEN
    RAISE EXCEPTION 'A student holds % open claim codes after a replacement. Two live codes let one balance pay for two prizes at two stands',
      v_open;
  END IF;

  IF (SELECT closed_reason FROM claim_codes WHERE code = v_old) <> 'replaced' THEN
    RAISE EXCEPTION 'The superseded code was not closed as "replaced", so nothing records why it stopped working';
  END IF;
  IF pg_temp.code_is_live(v_old) THEN
    RAISE EXCEPTION 'The previous code is still live after a new one was issued';
  END IF;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_old, 'cccc0005-0000-4000-8000-000000000007');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A replaced code was still accepted at a stand';
  END IF;
  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 200
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000007') <> 3 THEN
    RAISE EXCEPTION 'A handover refused for a replaced code still moved points or stock';
  END IF;

  -- And the screen showing the new code is the one that works.
  PERFORM pg_temp.act_as('bbbb0005-0000-4000-8000-000000000001');
  IF (poll_my_claim_code())->>'code' <> v_new THEN
    RAISE EXCEPTION 'The claim screen is not showing the only live code';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A code dies with the screen that shows it (R5). Closing the app, locking the
-- phone and losing signal are none of "used" or "closed", so liveness is tied
-- to the screen still asking: 60 seconds of tolerance, then the code is gone.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  SELECT code INTO v_code FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_at IS NULL;

  -- Inside the grace period: a phone that locked and woke keeps its code.
  PERFORM pg_temp.last_seen_ago(v_code, INTERVAL '59 seconds');
  IF NOT pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A code went dead 59 seconds after its last poll. The tolerance is 60 seconds, so a phone that locks mid-queue loses its code';
  END IF;

  -- Past it: the screen stopped asking, so the code somebody photographed is
  -- worthless.
  PERFORM pg_temp.last_seen_ago(v_code, INTERVAL '61 seconds');
  IF pg_temp.code_is_live(v_code) THEN
    RAISE EXCEPTION 'A code whose screen stopped asking 61 seconds ago is still live. A closed app leaves a usable code behind';
  END IF;

  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover(v_code, 'cccc0005-0000-4000-8000-000000000007');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'An expired code was accepted at a stand';
  END IF;
  IF v_res->>'reason' NOT LIKE '%digo inv%' THEN
    RAISE EXCEPTION 'An expired code was refused with "%" instead of telling the stand to have the student generate a new one',
      v_res->>'reason';
  END IF;
  IF (SELECT points FROM participants WHERE id = 'bbbb0005-0000-4000-8000-000000000001') <> 200
     OR (SELECT stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000007') <> 3 THEN
    RAISE EXCEPTION 'A handover refused for an expired code still moved points or stock';
  END IF;

  PERFORM pg_temp.act_as('bbbb0005-0000-4000-8000-000000000001');
  v_res := poll_my_claim_code();
  IF v_res->>'state' <> 'expired' THEN
    RAISE EXCEPTION 'An expired code polls as "%", not "expired". The screen would keep showing a code no stand will take',
      v_res->>'state';
  END IF;
END;
$test$;

-- A code that never existed is refused like any other dead code.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as('aaaa0005-0000-4000-8000-000000000001');
  v_res := confirm_handover('ZZZZZZ', 'cccc0005-0000-4000-8000-000000000007');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A code that was never issued was accepted at a stand';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The structural gates, tested directly. These are what hold when two stands
-- confirm in the same instant; the friendly pre-checks in the RPC cannot be
-- relied on for that.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
  v_rows INT;
  v_used UUID;
BEGIN
  BEGIN
    UPDATE rewards SET stock = -1 WHERE id = 'cccc0005-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'Stock was set negative: the CHECK on rewards.stock is gone, so the last unit can be oversold';
  END IF;

  v_blocked := false;
  BEGIN
    UPDATE participants SET points = -1 WHERE id = 'bbbb0005-0000-4000-8000-000000000001';
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A balance was set negative: the CHECK on participants.points is gone, so a handover can spend points that do not exist';
  END IF;

  v_blocked := false;
  BEGIN
    INSERT INTO claimed_rewards (participant_id, reward_id)
    VALUES ('bbbb0005-0000-4000-8000-000000000001', 'cccc0005-0000-4000-8000-000000000001');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A duplicate claim was inserted directly: the UNIQUE on (participant_id, reward_id) is gone';
  END IF;

  -- Two issuances that cross are serialised by the FOR UPDATE on the student,
  -- and this partial unique index is what holds if that ever slips: a second
  -- open code for one student cannot be stored at all.
  v_blocked := false;
  BEGIN
    INSERT INTO claim_codes (participant_id, code)
    VALUES ('bbbb0005-0000-4000-8000-000000000001', 'ZZZZZ9');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A second open claim code was stored for one student: the partial UNIQUE on claim_codes (participant_id) WHERE closed_at IS NULL is gone, so a student could have two codes confirmed against a balance covering one';
  END IF;

  -- The conditional write on stock: at zero it matches nothing, which is what
  -- the loser of a race for the last unit sees.
  UPDATE rewards SET stock = stock - 1
  WHERE id = 'cccc0005-0000-4000-8000-000000000002' AND stock > 0;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'UPDATE rewards ... WHERE stock > 0 matched a row at zero stock, so two confirmations can both take the last unit';
  END IF;

  -- The same for the code: closing an already-closed code matches nothing, so
  -- two confirmations racing on one code produce exactly one handover.
  SELECT id INTO v_used FROM claim_codes
  WHERE participant_id = 'bbbb0005-0000-4000-8000-000000000001' AND closed_reason = 'used';
  UPDATE claim_codes SET closed_at = now(), closed_reason = 'used'
  WHERE id = v_used AND closed_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'UPDATE claim_codes ... WHERE closed_at IS NULL matched an already-used code, so two stands racing on one code could both hand over a prize';
  END IF;
END;
$test$;

-- Nothing anywhere ended up below zero.
DO $test$
DECLARE
  v_bad INT;
BEGIN
  SELECT count(*) INTO v_bad FROM participants WHERE points < 0;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '% student(s) ended this run with a negative balance', v_bad;
  END IF;

  SELECT count(*) INTO v_bad FROM rewards WHERE stock < 0;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '% prize(s) ended this run with negative stock, meaning more units were handed over than existed',
      v_bad;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Claim codes are readable by nobody. RLS on and not one policy: a client that
-- can read claim_codes can read every live code in the fair, and a live code is
-- the ability to spend somebody else's points at any stand.
DO $test$
DECLARE
  v_rls BOOLEAN;
  v_policies INT;
BEGIN
  SELECT relrowsecurity INTO v_rls FROM pg_class
  WHERE oid = 'public.claim_codes'::regclass;
  IF NOT COALESCE(v_rls, false) THEN
    RAISE EXCEPTION 'claim_codes has row level security disabled, and 30_grants.sql grants SELECT on every table to anon and authenticated. Any client holding the publishable key can list every live claim code and spend other students'' points';
  END IF;

  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'claim_codes';
  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'claim_codes has % polic(ies). It must have none: the codes are read only by SECURITY DEFINER functions, and a readable code is a code somebody else can spend',
      v_policies;
  END IF;
END;
$test$;

-- The old attendee-side claim is gone, not merely unused. Leaving it would
-- leave a second way to spend points with no stand and no prize handed over.
DO $test$
DECLARE
  v_found INT;
BEGIN
  SELECT count(*) INTO v_found
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'claim_reward';
  IF v_found <> 0 THEN
    RAISE EXCEPTION 'claim_reward still exists. It spends points from the catalogue with no stand and no handover, which is exactly what spec 018 removed';
  END IF;
END;
$test$;

ROLLBACK;
