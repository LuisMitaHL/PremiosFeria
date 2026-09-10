-- Reward claiming. Points buy physical prizes with finite stock, so this is the
-- one place where the system spends currency. The real gates are the
-- conditional writes -- UPDATE ... WHERE stock > 0 and UPDATE ... WHERE
-- points >= cost -- inside a subtransaction, so stock is never decremented
-- without the points being debited (constitution VI).
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0005-0000-4000-8000-000000000001', 'test_rewards', 'Rewards Stand',
        'aaaa0005-0000-4000-8000-000000000001');

INSERT INTO rewards (id, community_id, name, cost, stock)
VALUES ('cccc0005-0000-4000-8000-000000000001', 'aaaa0005-0000-4000-8000-000000000001',
        'Polera', 100, 2),
       ('cccc0005-0000-4000-8000-000000000002', 'aaaa0005-0000-4000-8000-000000000001',
        'Agotado', 50, 0),
       ('cccc0005-0000-4000-8000-000000000003', 'aaaa0005-0000-4000-8000-000000000001',
        'Caro', 300, 5);

INSERT INTO participants (id, name, points, auth_user_id)
VALUES ('bbbb0005-0000-4000-8000-000000000001', 'Rich Tester', 300,
        'bbbb0005-0000-4000-8000-000000000001'),
       ('bbbb0005-0000-4000-8000-000000000002', 'Poor Tester', 10,
        'bbbb0005-0000-4000-8000-000000000002');

DO $test$
DECLARE
  v_rich  UUID := 'bbbb0005-0000-4000-8000-000000000001';
  v_poor  UUID := 'bbbb0005-0000-4000-8000-000000000002';
  v_shirt UUID := 'cccc0005-0000-4000-8000-000000000001';
  v_res   JSONB;
  v_points INT;
  v_stock INT;
  v_claims INT;
BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0005-0000-4000-8000-000000000001","role":"authenticated"}', true);

  -- A claim within budget debits the cost and decrements the stock, together.
  v_res := claim_reward(v_shirt);
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A claim that was affordable and in stock failed: %', v_res->>'reason';
  END IF;
  IF (v_res->>'newPoints')::int <> 200 THEN
    RAISE EXCEPTION 'A 100-point claim against a 300-point balance returned %',
      v_res->>'newPoints';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_rich;
  SELECT stock  INTO v_stock  FROM rewards      WHERE id = v_shirt;
  IF v_points <> 200 THEN
    RAISE EXCEPTION 'The balance is % after a 100-point claim from 300', v_points;
  END IF;
  IF v_stock <> 1 THEN
    RAISE EXCEPTION 'The stock is % after one claim from 2', v_stock;
  END IF;

  -- The same person cannot claim the same reward twice, and neither balance nor
  -- stock moves on the refusal.
  v_res := claim_reward(v_shirt);
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'The same reward was claimed twice by the same participant';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_rich;
  SELECT stock  INTO v_stock  FROM rewards      WHERE id = v_shirt;
  IF v_points <> 200 OR v_stock <> 1 THEN
    RAISE EXCEPTION 'A refused duplicate claim still moved state: balance %, stock %',
      v_points, v_stock;
  END IF;

  -- Out of stock is refused.
  v_res := claim_reward('cccc0005-0000-4000-8000-000000000002');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A reward with zero stock was claimed';
  END IF;

  SELECT stock INTO v_stock FROM rewards WHERE id = 'cccc0005-0000-4000-8000-000000000002';
  IF v_stock < 0 THEN
    RAISE EXCEPTION 'Stock went negative, to %', v_stock;
  END IF;

  -- Not enough points is refused, and nothing is debited.
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0005-0000-4000-8000-000000000002","role":"authenticated"}', true);
  v_res := claim_reward('cccc0005-0000-4000-8000-000000000003');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A 300-point reward was claimed on a 10-point balance';
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_poor;
  IF v_points <> 10 THEN
    RAISE EXCEPTION 'A refused claim changed the balance, now %', v_points;
  END IF;

  SELECT count(*) INTO v_claims FROM claimed_rewards WHERE participant_id = v_poor;
  IF v_claims <> 0 THEN
    RAISE EXCEPTION 'A refused claim was still recorded';
  END IF;
END;
$test$;

-- The structural gates, tested directly. These are what hold when two people
-- claim the last unit in the same instant; the friendly pre-checks in the RPC
-- cannot be relied on for that.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
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
    INSERT INTO claimed_rewards (participant_id, reward_id)
    VALUES ('bbbb0005-0000-4000-8000-000000000001', 'cccc0005-0000-4000-8000-000000000001');
  EXCEPTION WHEN unique_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A duplicate claim was inserted directly: the UNIQUE on (participant_id, reward_id) is gone';
  END IF;
END;
$test$;

-- A withdrawn reward still exists -- so a confirmed handover always names
-- something real -- but it cannot be claimed (spec 021, R19a).
DO $test$
DECLARE
  v_res JSONB;
  v_points INT;
BEGIN
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"bbbb0005-0000-4000-8000-000000000001","role":"authenticated"}', true);

  UPDATE rewards SET is_withdrawn = true
  WHERE id = 'cccc0005-0000-4000-8000-000000000002';
  UPDATE rewards SET stock = 5
  WHERE id = 'cccc0005-0000-4000-8000-000000000002';

  v_res := claim_reward('cccc0005-0000-4000-8000-000000000002');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A withdrawn reward was claimed even though it is in stock';
  END IF;

  SELECT points INTO v_points FROM participants
  WHERE id = 'bbbb0005-0000-4000-8000-000000000001';
  IF v_points <> 200 THEN
    RAISE EXCEPTION 'A refused claim on a withdrawn reward moved the balance, now %', v_points;
  END IF;
END;
$test$;

-- The ceiling binds every writer, including a direct insert.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    INSERT INTO rewards (community_id, name, cost, stock)
    VALUES ('aaaa0005-0000-4000-8000-000000000001', 'Inalcanzable', 301, 1);
  EXCEPTION WHEN check_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A reward costing 301 was stored: the 300-point ceiling is not enforced, so a stand can publish a prize nobody can reach';
  END IF;
END;
$test$;

ROLLBACK;
