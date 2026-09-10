-- A stand registering and restocking its own prizes (spec 021).
--
-- The two rules worth protecting are directional: a stand may never raise a
-- price attendees are saving towards, and never take away units they can
-- already see. Both are enforced where the write happens, because a stand admin
-- holds a session and can call the API directly -- the absence of a button
-- proves nothing.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO communities (id, username, name, auth_user_id)
VALUES ('aaaa0011-0000-4000-8000-000000000001', 'test_rw_a', 'Rewards Stand A',
        'aaaa0011-0000-4000-8000-000000000001'),
       ('aaaa0011-0000-4000-8000-000000000002', 'test_rw_b', 'Rewards Stand B',
        'aaaa0011-0000-4000-8000-000000000002');

CREATE FUNCTION pg_temp.act_as(p_uid UUID) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
END;
$fn$;

-- Registering
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID;
BEGIN
  PERFORM pg_temp.act_as('aaaa0011-0000-4000-8000-000000000001');

  v_res := create_reward('Polera Community Day', 200, 3, 'Shirt', 'Talla XL');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A stand could not register its own prize: %', v_res->>'error';
  END IF;
  v_id := (v_res->'reward'->>'id')::uuid;

  IF (v_res->'reward'->>'community_id')::uuid <> 'aaaa0011-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'A registered prize was attributed to the wrong stand';
  END IF;

  -- A description is optional: a prize name usually explains itself, and
  -- demanding a paragraph for a keyring is friction with no benefit.
  v_res := create_reward('Llavero', 20, 10, 'Key');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A prize without a description was refused: %', v_res->>'error';
  END IF;

  -- The ceiling. Above what a diligent attendee can earn, a prize is claimed by
  -- nobody, and the stand has no way to discover that during the fair.
  v_res := create_reward('Alcanzable', 300, 1, 'Gift');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A prize costing exactly 300 was refused: %', v_res->>'error';
  END IF;

  v_res := create_reward('Inalcanzable', 301, 1, 'Gift');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A prize costing 301 was accepted: the ceiling is advice, not a rule';
  END IF;

  -- An icon is how the prize appears in the catalogue; without one the card is
  -- broken for every attendee.
  v_res := create_reward('Sin icono', 50, 1, '');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A prize with no icon was accepted';
  END IF;

  v_res := create_reward('ab', 50, 1, 'Gift');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A two-character prize name was accepted; the limit is 3 to 40';
  END IF;

  v_res := create_reward(repeat('x', 41), 50, 1, 'Gift');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A 41-character prize name was accepted; it will not fit a card';
  END IF;

  v_res := create_reward('Descripcion larga', 50, 1, 'Gift', repeat('x', 101));
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A 101-character description was accepted';
  END IF;
END;
$test$;

-- Stock moves one way only, for the stand
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID;
  v_stock INT;
BEGIN
  PERFORM pg_temp.act_as('aaaa0011-0000-4000-8000-000000000001');
  SELECT id INTO v_id FROM rewards WHERE name = 'Polera Community Day';

  v_res := increase_reward_stock(v_id, 4);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A stand could not add stock to its own prize: %', v_res->>'error';
  END IF;
  SELECT stock INTO v_stock FROM rewards WHERE id = v_id;
  IF v_stock <> 7 THEN
    RAISE EXCEPTION 'Stock is % after adding 4 to 3', v_stock;
  END IF;

  -- Reducing takes away something attendees can already see and may be walking
  -- towards. It belongs to the organiser (spec 023).
  v_res := increase_reward_stock(v_id, -2);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand reduced its own stock by passing a negative amount';
  END IF;
  SELECT stock INTO v_stock FROM rewards WHERE id = v_id;
  IF v_stock <> 7 THEN
    RAISE EXCEPTION 'A refused reduction still changed the stock, now %', v_stock;
  END IF;

  v_res := increase_reward_stock(v_id, 0);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'Adding zero was accepted; it is not an addition';
  END IF;
END;
$test$;

-- A stand can only touch its own prizes
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID;
  v_stock INT;
BEGIN
  SELECT id, stock INTO v_id, v_stock FROM rewards WHERE name = 'Polera Community Day';

  PERFORM pg_temp.act_as('aaaa0011-0000-4000-8000-000000000002');
  v_res := increase_reward_stock(v_id, 5);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand added stock to another stand''s prize';
  END IF;

  IF (SELECT stock FROM rewards WHERE id = v_id) <> v_stock THEN
    RAISE EXCEPTION 'Another stand changed the stock of a prize it does not own';
  END IF;
END;
$test$;

-- No session, no writing
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  v_res := create_reward('Anonimo', 10, 1, 'Gift');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A caller with no session registered a prize';
  END IF;
END;
$test$;

-- The client has no write path of its own: every change goes through the RPC,
-- exactly as it does for scans.
DO $test$
DECLARE
  v_policies INT;
BEGIN
  SELECT count(*) INTO v_policies FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'rewards'
    AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL');
  IF v_policies <> 0 THEN
    RAISE EXCEPTION 'rewards has % write policies. A stand could then change a price or a stock directly, bypassing the rules that make those directional', v_policies;
  END IF;
END;
$test$;

ROLLBACK;
