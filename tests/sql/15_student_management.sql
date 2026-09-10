-- The complaints desk (spec 022).
--
-- Everything here is an exception to a rule the rest of the system enforces,
-- which is why it is the set of tests that matters most. Recovery is an account
-- takeover performed on purpose: the safeguards all sit on the code, so a code
-- that survives its use, outlives its window, or is readable by anybody is the
-- ability to walk off with somebody else's afternoon. An adjustment is the one
-- change to a balance that did not happen in the hall, so it has to be bounded
-- and recorded or the leaderboard stops being a consequence of anything.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures. Nothing here depends on seed data.
-- ---------------------------------------------------------------------------

INSERT INTO organizers (username, password_hash)
VALUES ('test_org_students', crypt('Organiza2026*', gen_salt('bf', 12)));

INSERT INTO communities (id, username, name, auth_user_id) VALUES
  ('aaaa0015-0000-4000-8000-00000000000a', 'quest_a', 'Stand A', 'aaaa0015-0000-4000-8000-00000000000a'),
  ('aaaa0015-0000-4000-8000-00000000000b', 'quest_b', 'Stand B', 'aaaa0015-0000-4000-8000-00000000000b'),
  ('aaaa0015-0000-4000-8000-00000000000c', 'quest_c', 'Stand C', 'aaaa0015-0000-4000-8000-00000000000c'),
  ('aaaa0015-0000-4000-8000-00000000000d', 'quest_d', 'Stand D', 'aaaa0015-0000-4000-8000-00000000000d');

INSERT INTO rewards (id, community_id, name, cost, stock) VALUES
  ('eeee0015-0000-4000-8000-000000000001', 'aaaa0015-0000-4000-8000-00000000000a', 'Sticker', 10, 5),
  ('eeee0015-0000-4000-8000-000000000002', 'aaaa0015-0000-4000-8000-00000000000a', 'Llavero', 10, 5),
  ('eeee0015-0000-4000-8000-000000000003', 'aaaa0015-0000-4000-8000-00000000000a', 'Gorra',   10, 5);

CREATE FUNCTION pg_temp.as_organizer() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', (SELECT auth_user_id FROM organizers WHERE username = 'test_org_students'),
                      'role', 'authenticated')::text, true);
END;
$fn$;

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

-- A visit code for a stand, signed the same way the stand's screen signs it.
CREATE FUNCTION pg_temp.visit_payload(p_stand UUID) RETURNS TEXT LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'sid', p_stand,
    'act', NULL::uuid,
    'ts',  EXTRACT(EPOCH FROM NOW())::BIGINT / 15,
    'type', 'visit',
    'tok', scan_signature(p_stand, NULL, EXTRACT(EPOCH FROM NOW())::BIGINT / 15, 'visit',
                          (SELECT value FROM settings WHERE key = 'hmac_secret'))
  )::text
$fn$;

-- The attendee this suite follows. Held by id rather than by nickname or by
-- session, because the point of the suite is that both of those move.
CREATE TEMP TABLE test_subject (id UUID);

CREATE FUNCTION pg_temp.zorro() RETURNS UUID LANGUAGE sql STABLE AS $fn$
  SELECT id FROM pg_temp.test_subject
$fn$;

-- ---------------------------------------------------------------------------
-- An afternoon worth losing: Zorro registers, earns, and takes a prize home.
-- Everything after this asks whether that afternoon survives.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_code TEXT;
BEGIN
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000001');
  v_res := register_or_recover('Zorro', 'device-a');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The fixture attendee could not register: %', v_res->>'error';
  END IF;
  INSERT INTO pg_temp.test_subject (id) VALUES ((v_res->'participant'->>'id')::uuid);

  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000a'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The fixture scan at stand A was refused: %', v_res->>'reason';
  END IF;
  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000b'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The fixture scan at stand B was refused: %', v_res->>'reason';
  END IF;

  -- A real handover, so the profile carries a claim as well as scans.
  v_res := issue_claim_code();
  v_code := v_res->>'code';
  PERFORM pg_temp.act_as('aaaa0015-0000-4000-8000-00000000000a');
  v_res := confirm_handover(v_code, 'eeee0015-0000-4000-8000-000000000001');
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'The fixture handover was refused: %', v_res->>'reason';
  END IF;

  IF (SELECT points FROM participants WHERE id = pg_temp.zorro()) <> 10 THEN
    RAISE EXCEPTION 'The fixture left % points instead of 10; every later balance assertion is built on this',
      (SELECT points FROM participants WHERE id = pg_temp.zorro());
  END IF;
END;
$test$;

-- A second attendee, for the nickname collision and for asking whether one
-- attendee can reach into another's profile.
DO $test$
DECLARE
  v_res JSONB;
BEGIN
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000003');
  v_res := register_or_recover('Lobo', 'device-l');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The second fixture attendee could not register: %', v_res->>'error';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R2, R6, R7, R8, R9: the profile moves to the new phone, and leaves the old.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_code TEXT;
  v_id UUID := pg_temp.zorro();
  v_scans INT;
  v_claims INT;
BEGIN
  SELECT count(*) INTO v_scans  FROM scans WHERE participant_id = v_id;
  SELECT count(*) INTO v_claims FROM claimed_rewards WHERE participant_id = v_id;

  PERFORM pg_temp.as_organizer();
  v_res := issue_recovery_code(v_id);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not issue a recovery code: %. Without it spec 001 refuses an attendee who changed phones and offers them nothing',
      v_res->>'error';
  END IF;

  v_code := v_res->>'code';
  IF v_code IS NULL OR char_length(v_code) < 6 THEN
    RAISE EXCEPTION 'The issued recovery code is "%", which is not a code somebody can dictate across a desk', v_code;
  END IF;

  -- Dictated out loud in a noisy hall and typed on a phone. Each confusable
  -- character is a failed attempt in front of a queue.
  IF v_code ~ '[O0I1L]' THEN
    RAISE EXCEPTION 'The recovery code "%" contains a character confused when read from a screen and typed into a phone (O/0, I/1/L)', v_code;
  END IF;

  -- The attendee, on the new phone, in a brand new anonymous session.
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000002');
  v_res := redeem_recovery_code(v_code, 'device-b');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A freshly issued recovery code was refused: %', v_res->>'error';
  END IF;

  IF (v_res->'participant'->>'id')::uuid <> v_id THEN
    RAISE EXCEPTION 'Recovery handed back a different profile. The attendee is looking at somebody else afternoon';
  END IF;
  IF v_res->'participant'->>'name' <> 'Zorro' THEN
    RAISE EXCEPTION 'Recovery changed the nickname to "%"; the leaderboard the attendee was on no longer names them',
      v_res->'participant'->>'name';
  END IF;
  -- The device identity is half of the key that returns a profile (spec 001).
  IF v_res->'participant' ? 'fingerprint' THEN
    RAISE EXCEPTION 'The recovery response carried the device identity back to the client';
  END IF;

  IF (SELECT points FROM participants WHERE id = v_id) <> 10 THEN
    RAISE EXCEPTION 'Recovery returned the profile with % points instead of the 10 it had earned',
      (SELECT points FROM participants WHERE id = v_id);
  END IF;
  IF (SELECT count(*) FROM scans WHERE participant_id = v_id) <> v_scans THEN
    RAISE EXCEPTION 'Recovery changed the scan history: % rows before, % after',
      v_scans, (SELECT count(*) FROM scans WHERE participant_id = v_id);
  END IF;
  IF (SELECT count(*) FROM claimed_rewards WHERE participant_id = v_id) <> v_claims THEN
    RAISE EXCEPTION 'Recovery changed the handover history: % rows before, % after',
      v_claims, (SELECT count(*) FROM claimed_rewards WHERE participant_id = v_id);
  END IF;

  -- R9: it moves a profile, it does not mint one.
  IF (SELECT count(*) FROM participants WHERE lower(btrim(name)) = 'zorro') <> 1 THEN
    RAISE EXCEPTION 'Recovery created a second profile; there are now % called Zorro',
      (SELECT count(*) FROM participants WHERE lower(btrim(name)) = 'zorro');
  END IF;

  -- R7: the old phone lets go. Two devices on one profile is two people
  -- earning into one balance with no way to tell whose it is.
  IF (SELECT auth_user_id FROM participants WHERE id = v_id)
     <> 'cccc0015-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'Recovery did not attach the profile to the phone that redeemed the code';
  END IF;
  IF EXISTS (SELECT 1 FROM participants
             WHERE auth_user_id = 'cccc0015-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'The original device still holds the profile after a recovery. Two people are now earning into one balance and neither can be shown to be the owner';
  END IF;
END;
$test$;

-- The old phone is treated as a stranger from here on -- including when the
-- person holding it types the nickname again, which is the whole of spec 001's
-- way back into a profile.
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
BEGIN
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000001');

  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000c'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'The device a profile was recovered away from still earns points into it';
  END IF;

  v_res := register_or_recover('Zorro', 'device-a');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The device a profile was recovered away from typed the nickname and took it straight back. Recovery is meant to move a profile, and it moved nothing';
  END IF;
  IF (SELECT auth_user_id FROM participants WHERE id = v_id)
     <> 'cccc0015-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'The old device pulled the profile back onto itself after a recovery';
  END IF;
END;
$test$;

-- R3: exactly once, and refused afterwards.
DO $test$
DECLARE
  v_res JSONB;
  v_code TEXT;
  v_before UUID;
BEGIN
  PERFORM pg_temp.as_organizer();
  v_code := issue_recovery_code(pg_temp.zorro())->>'code';

  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000004');
  v_res := redeem_recovery_code(v_code, 'device-c');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A valid recovery code was refused on its first use: %', v_res->>'error';
  END IF;
  SELECT auth_user_id INTO v_before FROM participants WHERE id = pg_temp.zorro();

  -- Somebody who overheard the code at the desk, a moment later.
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-00000000dead');
  v_res := redeem_recovery_code(v_code, 'device-thief');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A recovery code worked a second time. Anybody who overheard it at the desk walks away with the profile';
  END IF;
  IF (SELECT auth_user_id FROM participants WHERE id = pg_temp.zorro()) <> v_before THEN
    RAISE EXCEPTION 'A refused second redemption still moved the profile to the caller device';
  END IF;
END;
$test$;

-- R5: at most one live code. Issuing a second kills the first immediately.
DO $test$
DECLARE
  v_first TEXT;
  v_second TEXT;
  v_res JSONB;
  v_open INT;
BEGIN
  PERFORM pg_temp.as_organizer();
  v_first  := issue_recovery_code(pg_temp.zorro())->>'code';
  v_second := issue_recovery_code(pg_temp.zorro())->>'code';

  IF v_first = v_second THEN
    RAISE EXCEPTION 'Two consecutive recovery codes for the same attendee are identical; the code is predictable from the participant (R8)';
  END IF;

  SELECT count(*) INTO v_open FROM recovery_codes
  WHERE participant_id = pg_temp.zorro() AND closed_at IS NULL;
  IF v_open <> 1 THEN
    RAISE EXCEPTION 'There are % open recovery codes for one attendee; every extra one is a spare key left on the desk', v_open;
  END IF;

  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000005');
  v_res := redeem_recovery_code(v_first, 'device-d');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A superseded recovery code still worked. The one dictated to the wrong person a minute ago is still a live key';
  END IF;

  v_res := redeem_recovery_code(v_second, 'device-d');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The most recently issued recovery code was refused: %', v_res->>'error';
  END IF;
END;
$test$;

-- R4: it expires on its own, used or not. Ten minutes is the window, and it is
-- moved backwards rather than waited out.
DO $test$
DECLARE
  v_code TEXT;
  v_res JSONB;
BEGIN
  IF recovery_code_ttl() <> INTERVAL '10 minutes' THEN
    RAISE EXCEPTION 'A recovery code lives for % instead of the 10 minutes the spec allows', recovery_code_ttl();
  END IF;

  PERFORM pg_temp.as_organizer();
  v_code := issue_recovery_code(pg_temp.zorro())->>'code';
  UPDATE recovery_codes SET issued_at = now() - INTERVAL '11 minutes'
  WHERE code = v_code AND closed_at IS NULL;

  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000006');
  v_res := redeem_recovery_code(v_code, 'device-e');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A recovery code issued 11 minutes ago still worked. A code written on a slip of paper stays a live key to somebody profile for as long as the paper lasts';
  END IF;

  -- And it is still good inside the window: an expiry that fires early sends
  -- the attendee back to the queue.
  PERFORM pg_temp.as_organizer();
  v_code := issue_recovery_code(pg_temp.zorro())->>'code';
  UPDATE recovery_codes SET issued_at = now() - INTERVAL '9 minutes'
  WHERE code = v_code AND closed_at IS NULL;

  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000006');
  v_res := redeem_recovery_code(v_code, 'device-e');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A recovery code 9 minutes old was already refused: %. The window is meant to be 10 minutes', v_res->>'error';
  END IF;
END;
$test$;

-- Only the organiser issues one. A stand or an attendee producing a recovery
-- code is a self-service account takeover.
DO $test$
DECLARE
  v_res JSONB;
  v_zorro UUID := pg_temp.zorro();
  v_lobo UUID;
  v_before INT;
BEGIN
  SELECT id INTO v_lobo FROM participants WHERE name = 'Lobo';
  SELECT count(*) INTO v_before FROM recovery_codes;

  -- An attendee, for somebody else and for themselves.
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000003');
  v_res := issue_recovery_code(v_zorro);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An attendee issued a recovery code for another attendee, which is the whole leaderboard for the taking';
  END IF;
  v_res := issue_recovery_code(v_lobo);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An attendee issued a recovery code for their own profile. Whoever asks for one no longer needs an organiser to agree';
  END IF;

  -- A stand.
  PERFORM pg_temp.act_as('aaaa0015-0000-4000-8000-00000000000a');
  v_res := issue_recovery_code(v_zorro);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A stand issued a recovery code. One compromised stand phone then owns every profile at the fair';
  END IF;

  -- Nobody at all.
  PERFORM pg_temp.no_session();
  v_res := issue_recovery_code(v_zorro);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'A caller with no session issued a recovery code';
  END IF;

  IF (SELECT count(*) FROM recovery_codes) <> v_before THEN
    RAISE EXCEPTION 'A refused issue attempt still wrote a recovery code row; % existed before, % now',
      v_before, (SELECT count(*) FROM recovery_codes);
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R14 to R16: renaming, under every rule spec 001 places on a nickname.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_points INT;
  v_auth UUID;
  v_scans INT;
  v_claims INT;
BEGIN
  SELECT points, auth_user_id INTO v_points, v_auth FROM participants WHERE id = v_id;
  SELECT count(*) INTO v_scans  FROM scans WHERE participant_id = v_id;
  SELECT count(*) INTO v_claims FROM claimed_rewards WHERE participant_id = v_id;

  PERFORM pg_temp.as_organizer();
  v_res := organizer_rename_participant(v_id, '  Zorrito  ');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not rename an attendee: %. A nickname on a projected leaderboard could not be fixed', v_res->>'error';
  END IF;
  IF (SELECT name FROM participants WHERE id = v_id) <> 'Zorrito' THEN
    RAISE EXCEPTION 'The rename stored "%" instead of the trimmed "Zorrito"',
      (SELECT name FROM participants WHERE id = v_id);
  END IF;

  -- R16: a rename is a rename and nothing else.
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points THEN
    RAISE EXCEPTION 'Renaming an attendee changed their balance from % to %',
      v_points, (SELECT points FROM participants WHERE id = v_id);
  END IF;
  IF (SELECT auth_user_id FROM participants WHERE id = v_id) <> v_auth THEN
    RAISE EXCEPTION 'Renaming an attendee detached their phone; they would open the app to a registration screen';
  END IF;
  IF (SELECT count(*) FROM scans WHERE participant_id = v_id) <> v_scans
     OR (SELECT count(*) FROM claimed_rewards WHERE participant_id = v_id) <> v_claims THEN
    RAISE EXCEPTION 'Renaming an attendee changed their history';
  END IF;

  -- R15: uniqueness, case-insensitively, against a name already in the hall.
  v_res := organizer_rename_participant(v_id, 'LOBO');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The organiser renamed one attendee onto another nickname. Two people would share the key that returns a profile';
  END IF;
  IF (SELECT name FROM participants WHERE id = v_id) <> 'Zorrito' THEN
    RAISE EXCEPTION 'A refused rename changed the nickname anyway, to "%"',
      (SELECT name FROM participants WHERE id = v_id);
  END IF;

  -- R15: length. 24 fits a projected row; 25 does not.
  v_res := organizer_rename_participant(v_id, 'a');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The organiser set a one-character nickname, which spec 001 refuses at registration';
  END IF;

  v_res := organizer_rename_participant(v_id, repeat('x', 25));
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'The organiser set a 25-character nickname; it will not fit the leaderboard row the limit exists for';
  END IF;

  v_res := organizer_rename_participant(v_id, repeat('x', 24));
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A 24-character nickname was refused: %. That length is legal at registration', v_res->>'error';
  END IF;

  v_res := organizer_rename_participant(v_id, 'Zorrito');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Renaming back was refused: %', v_res->>'error';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R17 to R19: withholding a claim keeps someone playing and stops them
-- spending, and the stand is told the truth about why.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_code TEXT;
  v_points INT;
  v_stock INT;
  v_reason TEXT;
BEGIN
  PERFORM pg_temp.as_organizer();
  v_res := organizer_set_participant_flags(v_id, true, NULL::BOOLEAN);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not withhold claiming: %', v_res->>'error';
  END IF;

  -- R18: still earns.
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000006');
  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000c'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'An attendee barred from claiming could not scan: %. The sanction is meant to stop them spending, not playing', v_res->>'reason';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> 20 THEN
    RAISE EXCEPTION 'An attendee barred from claiming scanned but was credited nothing; they hold % points',
      (SELECT points FROM participants WHERE id = v_id);
  END IF;

  SELECT points INTO v_points FROM participants WHERE id = v_id;
  SELECT stock  INTO v_stock  FROM rewards WHERE id = 'eeee0015-0000-4000-8000-000000000002';

  v_res := issue_claim_code();
  v_code := v_res->>'code';

  PERFORM pg_temp.act_as('aaaa0015-0000-4000-8000-00000000000a');
  v_res := confirm_handover(v_code, 'eeee0015-0000-4000-8000-000000000002');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'An attendee barred from claiming took a prize. The sanction the registration screen warns about does nothing';
  END IF;

  -- R19: the real reason. The attendee has 20 points for a 10 point prize, so
  -- "short of points" is not merely unhelpful here, it is false, and it sends
  -- the stand to argue with the wrong person.
  v_reason := v_res->>'reason';
  IF v_reason ILIKE '%falta%' OR v_reason ILIKE '%punto%' OR v_reason ILIKE '%stock%'
     OR v_reason ILIKE '%unidad%' THEN
    RAISE EXCEPTION 'A withheld claim was refused with the wrong reason: "%". The stand is told to send the attendee away to earn points they already have',
      v_reason;
  END IF;
  IF v_reason NOT ILIKE '%canjear%' THEN
    RAISE EXCEPTION 'A withheld claim was refused with "%", which does not say the claim was withheld', v_reason;
  END IF;

  -- The refusal costs nothing: no points, no stock, and the code is not burned.
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points THEN
    RAISE EXCEPTION 'A refused handover charged the attendee anyway: % before, % after',
      v_points, (SELECT points FROM participants WHERE id = v_id);
  END IF;
  IF (SELECT stock FROM rewards WHERE id = 'eeee0015-0000-4000-8000-000000000002') <> v_stock THEN
    RAISE EXCEPTION 'A refused handover consumed a unit of stock';
  END IF;

  -- R17: and it is restored.
  PERFORM pg_temp.as_organizer();
  v_res := organizer_set_participant_flags(v_id, false, NULL::BOOLEAN);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not restore claiming: %', v_res->>'error';
  END IF;

  PERFORM pg_temp.act_as('aaaa0015-0000-4000-8000-00000000000a');
  v_res := confirm_handover(v_code, 'eeee0015-0000-4000-8000-000000000002');
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'An attendee whose claiming was restored still could not take a prize: %. The sanction cannot be lifted',
      v_res->>'reason';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R20 to R22: removal stops everything and erases nothing.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_points INT;
  v_scans INT;
  v_claims INT;
  v_code TEXT;
BEGIN
  SELECT points INTO v_points FROM participants WHERE id = v_id;
  SELECT count(*) INTO v_scans  FROM scans WHERE participant_id = v_id;
  SELECT count(*) INTO v_claims FROM claimed_rewards WHERE participant_id = v_id;

  PERFORM pg_temp.as_organizer();
  v_res := organizer_set_participant_flags(v_id, NULL::BOOLEAN, true);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not remove an attendee: %', v_res->>'error';
  END IF;

  -- R22: removal is a state, never a deletion.
  IF NOT EXISTS (SELECT 1 FROM participants WHERE id = v_id) THEN
    RAISE EXCEPTION 'Removing an attendee deleted the row. Every scan and handover that names them points at nothing';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points
     OR (SELECT count(*) FROM scans WHERE participant_id = v_id) <> v_scans
     OR (SELECT count(*) FROM claimed_rewards WHERE participant_id = v_id) <> v_claims THEN
    RAISE EXCEPTION 'Removing an attendee erased part of what happened to them';
  END IF;

  -- R21: earns nothing.
  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000006');
  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000d'));
  IF COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A removed attendee scanned a code and was credited. Removal did not remove them from the event';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points THEN
    RAISE EXCEPTION 'A refused scan by a removed attendee still moved their balance';
  END IF;
  IF (SELECT count(*) FROM scans WHERE participant_id = v_id) <> v_scans THEN
    RAISE EXCEPTION 'A refused scan by a removed attendee still recorded a scan';
  END IF;

  -- R21: and claims nothing.
  v_res := issue_claim_code();
  v_code := v_res->>'code';
  PERFORM pg_temp.act_as('aaaa0015-0000-4000-8000-00000000000a');
  v_res := confirm_handover(v_code, 'eeee0015-0000-4000-8000-000000000003');
  IF COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'A removed attendee took a prize off a stand table';
  END IF;
  IF (v_res->>'reason') ILIKE '%falta%' OR (v_res->>'reason') ILIKE '%punto%' THEN
    RAISE EXCEPTION 'A removed attendee claim was refused with "%", which sends the stand to argue about a balance',
      v_res->>'reason';
  END IF;

  -- R20: reinstatement restores them, and changes nothing else.
  PERFORM pg_temp.as_organizer();
  v_res := organizer_set_participant_flags(v_id, NULL::BOOLEAN, false);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not reinstate an attendee: %', v_res->>'error';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points
     OR (SELECT count(*) FROM scans WHERE participant_id = v_id) <> v_scans
     OR (SELECT count(*) FROM claimed_rewards WHERE participant_id = v_id) <> v_claims THEN
    RAISE EXCEPTION 'Reinstating an attendee changed their balance or history';
  END IF;
  IF (SELECT claims_barred FROM participants WHERE id = v_id) THEN
    RAISE EXCEPTION 'Reinstating an attendee also flipped the unrelated claim sanction';
  END IF;

  PERFORM pg_temp.act_as('cccc0015-0000-4000-8000-000000000006');
  v_res := validate_and_scan(pg_temp.visit_payload('aaaa0015-0000-4000-8000-00000000000d'));
  IF NOT COALESCE((v_res->>'valid')::boolean, false) THEN
    RAISE EXCEPTION 'A reinstated attendee still cannot earn: %', v_res->>'reason';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points + 10 THEN
    RAISE EXCEPTION 'A reinstated attendee scan credited % instead of 10 points',
      (SELECT points FROM participants WHERE id = v_id) - v_points;
  END IF;
END;
$test$;

-- R22 again, structurally: nothing deletes somebody who took part.
DO $test$
DECLARE
  v_blocked BOOLEAN := false;
BEGIN
  BEGIN
    DELETE FROM participants WHERE id = pg_temp.zorro();
  EXCEPTION WHEN foreign_key_violation THEN
    v_blocked := true;
  END;
  IF NOT v_blocked THEN
    RAISE EXCEPTION 'An attendee with scans and handovers was deleted. Removal is meant to be a state and never a deletion';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R23 to R27: the one sanctioned override, and its bounds.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_points INT;
  v_rows INT;
BEGIN
  PERFORM pg_temp.as_organizer();
  SELECT points INTO v_points FROM participants WHERE id = v_id;
  SELECT count(*) INTO v_rows FROM point_adjustments WHERE participant_id = v_id;

  -- R24: a reason, or nothing happens.
  FOREACH v_res IN ARRAY ARRAY[
    organizer_adjust_points(v_id, 10, NULL::TEXT),
    organizer_adjust_points(v_id, 10, ''),
    organizer_adjust_points(v_id, 10, '   '),
    organizer_adjust_points(v_id, 10, 'ok')
  ] LOOP
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION 'An adjustment was accepted with no usable reason. A number with no reason cannot be told apart from a favour, which is the only thing the log is for';
    END IF;
  END LOOP;

  -- R23 boundary: zero is not an adjustment, it is a log entry about nothing.
  IF NOT (organizer_adjust_points(v_id, 0, 'Nada que corregir') ? 'error') THEN
    RAISE EXCEPTION 'An adjustment of zero points was accepted';
  END IF;
  IF NOT (organizer_adjust_points(v_id, NULL::INT, 'Sin monto') ? 'error') THEN
    RAISE EXCEPTION 'An adjustment with no amount was accepted';
  END IF;

  IF (SELECT points FROM participants WHERE id = v_id) <> v_points THEN
    RAISE EXCEPTION 'A refused adjustment changed the balance anyway';
  END IF;
  IF (SELECT count(*) FROM point_adjustments WHERE participant_id = v_id) <> v_rows THEN
    RAISE EXCEPTION 'A refused adjustment was still written to the adjustment log';
  END IF;
END;
$test$;

-- R25: never below zero. Spec 020 R12 binds the organiser too.
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_points INT;
  v_rows INT;
BEGIN
  PERFORM pg_temp.as_organizer();
  SELECT points INTO v_points FROM participants WHERE id = v_id;
  SELECT count(*) INTO v_rows FROM point_adjustments WHERE participant_id = v_id;

  v_res := organizer_adjust_points(v_id, -(v_points + 1), 'Correccion excesiva');
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An adjustment took a balance of % below zero. Every prize price stops meaning anything once a balance can be negative', v_points;
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points THEN
    RAISE EXCEPTION 'A refused negative adjustment still moved the balance';
  END IF;
  IF (SELECT count(*) FROM point_adjustments WHERE participant_id = v_id) <> v_rows THEN
    RAISE EXCEPTION 'A refused negative adjustment was still logged as if it had happened';
  END IF;

  -- Exactly to zero is allowed; it is one point further that is not.
  v_res := organizer_adjust_points(v_id, -v_points, 'Saldo a cero');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'An adjustment down to exactly zero was refused: %', v_res->>'error';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> 0 THEN
    RAISE EXCEPTION 'An adjustment to zero left % points', (SELECT points FROM participants WHERE id = v_id);
  END IF;

  v_res := organizer_adjust_points(v_id, v_points, 'Restitucion');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The restoring adjustment was refused: %', v_res->>'error';
  END IF;
END;
$test$;

-- R26: recorded with amount, reason and moment, and told apart from earning.
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_points INT;
  v_row point_adjustments%ROWTYPE;
BEGIN
  PERFORM pg_temp.as_organizer();
  SELECT points INTO v_points FROM participants WHERE id = v_id;

  v_res := organizer_adjust_points(v_id, 30, 'El telefono del stand no leyo el codigo');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'A well formed adjustment was refused: %', v_res->>'error';
  END IF;
  IF (SELECT points FROM participants WHERE id = v_id) <> v_points + 30 THEN
    RAISE EXCEPTION 'A 30 point adjustment moved the balance by %',
      (SELECT points FROM participants WHERE id = v_id) - v_points;
  END IF;

  -- Found by its amount rather than by its moment: every adjustment written
  -- inside one transaction shares a timestamp.
  SELECT * INTO v_row FROM point_adjustments
  WHERE participant_id = v_id AND amount = 30;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'An adjustment changed a balance and left no record. Nobody reading that balance later can tell it apart from points earned in the hall';
  END IF;
  IF v_row.amount <> 30 THEN
    RAISE EXCEPTION 'The adjustment log recorded % points instead of the 30 that were granted', v_row.amount;
  END IF;
  IF v_row.reason <> 'El telefono del stand no leyo el codigo' THEN
    RAISE EXCEPTION 'The adjustment log recorded the reason as "%"', v_row.reason;
  END IF;
  IF v_row.adjusted_at IS NULL THEN
    RAISE EXCEPTION 'The adjustment log recorded no moment; the entry cannot be placed against anything else that happened';
  END IF;

  -- And it is not filed as a scan, which is what makes the two separable.
  IF EXISTS (SELECT 1 FROM scans WHERE participant_id = v_id AND points = 30) THEN
    RAISE EXCEPTION 'An adjustment was written as a scan. A granted balance would read as one earned at a stand';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The desk is a privilege, not a page. Nobody but the organiser reaches it.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_id UUID := pg_temp.zorro();
  v_name TEXT;
  v_points INT;
  v_barred BOOLEAN;
  v_removed BOOLEAN;
  v_adjustments INT;
  v_actor TEXT;
  v_uid UUID;
  v_res JSONB;
BEGIN
  SELECT name, points, claims_barred, is_removed
  INTO v_name, v_points, v_barred, v_removed
  FROM participants WHERE id = v_id;
  SELECT count(*) INTO v_adjustments FROM point_adjustments;

  FOREACH v_actor IN ARRAY ARRAY['An attendee', 'A stand', 'A caller with no session'] LOOP
    IF v_actor = 'An attendee' THEN
      v_uid := 'cccc0015-0000-4000-8000-000000000003';
      PERFORM pg_temp.act_as(v_uid);
    ELSIF v_actor = 'A stand' THEN
      v_uid := 'aaaa0015-0000-4000-8000-00000000000a';
      PERFORM pg_temp.act_as(v_uid);
    ELSE
      PERFORM pg_temp.no_session();
    END IF;

    -- Reading somebody history is reading their afternoon: where they went,
    -- when, and with whom.
    v_res := participant_detail(v_id);
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% read another attendee full history: every stand they visited and at what time', v_actor;
    END IF;

    v_res := organizer_rename_participant(v_id, 'Secuestrado');
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% renamed an attendee', v_actor;
    END IF;

    v_res := organizer_set_participant_flags(v_id, true, true);
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% removed an attendee from the event', v_actor;
    END IF;

    v_res := organizer_adjust_points(v_id, 500, 'Porque si');
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% granted points to a balance. The leaderboard stops being a consequence of anything that happened in the hall', v_actor;
    END IF;

    v_res := issue_recovery_code(v_id);
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% issued a recovery code', v_actor;
    END IF;
  END LOOP;

  IF (SELECT name FROM participants WHERE id = v_id) <> v_name
     OR (SELECT points FROM participants WHERE id = v_id) <> v_points
     OR (SELECT claims_barred FROM participants WHERE id = v_id) <> v_barred
     OR (SELECT is_removed FROM participants WHERE id = v_id) <> v_removed THEN
    RAISE EXCEPTION 'One of the refused calls changed the profile anyway';
  END IF;
  IF (SELECT count(*) FROM point_adjustments) <> v_adjustments THEN
    RAISE EXCEPTION 'A refused adjustment by a caller who is not the organiser was still logged';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Isolation. A readable recovery code is the ability to keep somebody else
-- profile; a writable adjustment log is the ability to grant yourself points.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_unprotected TEXT;
  v_policies TEXT;
BEGIN
  SELECT string_agg(relname, ', ') INTO v_unprotected
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname IN ('recovery_codes', 'point_adjustments')
    AND NOT c.relrowsecurity;
  IF v_unprotected IS NOT NULL THEN
    RAISE EXCEPTION 'Row level security is off on: %. The grants in 30_grants.sql are broad, so these tables are fully exposed to anyone holding the publishable key',
      v_unprotected;
  END IF;

  SELECT string_agg(tablename || '.' || policyname || ' (' || cmd || ')', ', ')
  INTO v_policies
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN ('recovery_codes', 'point_adjustments');
  IF v_policies IS NOT NULL THEN
    RAISE EXCEPTION 'A policy exists on a table that must have none: %. Any policy on recovery_codes is a route to a live key to somebody profile',
      v_policies;
  END IF;
END;
$test$;

-- And in practice, from a role a browser can actually hold, including the
-- attendee the rows are about.
DO $test$
DECLARE
  v_codes INT;
  v_adjustments INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM recovery_codes) OR NOT EXISTS (SELECT 1 FROM point_adjustments) THEN
    RAISE EXCEPTION 'The isolation check has nothing to read; it would pass against empty tables and prove nothing';
  END IF;

  BEGIN
    SET LOCAL ROLE anon;
    SELECT count(*) INTO v_codes FROM recovery_codes;
    SELECT count(*) INTO v_adjustments FROM point_adjustments;
    RESET ROLE;
  EXCEPTION WHEN insufficient_privilege THEN
    -- Denied outright is stronger than seeing nothing.
    RESET ROLE;
    v_codes := 0;
    v_adjustments := 0;
  END;
  IF v_codes <> 0 THEN
    RAISE EXCEPTION 'The anon role read % recovery codes. Anyone with the publishable key can redeem a live one and walk off with the profile it belongs to', v_codes;
  END IF;
  IF v_adjustments <> 0 THEN
    RAISE EXCEPTION 'The anon role read % adjustment rows', v_adjustments;
  END IF;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', 'cccc0015-0000-4000-8000-000000000006',
                        'role', 'authenticated')::text, true);
    SELECT count(*) INTO v_codes FROM recovery_codes;
    SELECT count(*) INTO v_adjustments FROM point_adjustments;
    RESET ROLE;
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    v_codes := 0;
    v_adjustments := 0;
  END;
  IF v_codes <> 0 THEN
    RAISE EXCEPTION 'A signed in attendee read % recovery codes, their own among them. Nobody needs to stand in front of the organiser any more', v_codes;
  END IF;
  IF v_adjustments <> 0 THEN
    RAISE EXCEPTION 'A signed in attendee read % adjustment rows', v_adjustments;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R11 to R13: what the organiser sees when somebody complains.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res JSONB;
  v_id UUID := pg_temp.zorro();
  v_scans INT;
  v_claims INT;
  v_adjustments INT;
  v_first JSONB;
BEGIN
  SELECT count(*) INTO v_scans  FROM scans WHERE participant_id = v_id;
  SELECT count(*) INTO v_claims FROM claimed_rewards WHERE participant_id = v_id;
  SELECT count(*) INTO v_adjustments FROM point_adjustments WHERE participant_id = v_id;

  PERFORM pg_temp.as_organizer();
  v_res := participant_detail(v_id);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'The organiser could not look up an attendee: %. A complaint at the desk cannot be answered', v_res->>'error';
  END IF;

  IF (v_res->'participant'->>'points')::int
     <> (SELECT points FROM participants WHERE id = v_id) THEN
    RAISE EXCEPTION 'The lookup shows a balance of % while the profile holds %',
      v_res->'participant'->>'points', (SELECT points FROM participants WHERE id = v_id);
  END IF;

  IF jsonb_array_length(v_res->'scans') <> v_scans THEN
    RAISE EXCEPTION 'The lookup shows % scans out of %. The organiser cannot tell the attendee whether the scan they are complaining about happened',
      jsonb_array_length(v_res->'scans'), v_scans;
  END IF;
  IF jsonb_array_length(v_res->'claims') <> v_claims THEN
    RAISE EXCEPTION 'The lookup shows % handovers out of %',
      jsonb_array_length(v_res->'claims'), v_claims;
  END IF;
  IF jsonb_array_length(v_res->'adjustments') <> v_adjustments THEN
    RAISE EXCEPTION 'The lookup shows % adjustments out of %; part of how this balance got here is invisible',
      jsonb_array_length(v_res->'adjustments'), v_adjustments;
  END IF;

  -- R12: which stand, what for, when, and how much.
  v_first := v_res->'scans'->0;
  IF v_first->>'stand' IS NULL OR v_first->>'at' IS NULL OR v_first->>'points' IS NULL THEN
    RAISE EXCEPTION 'A scan in the lookup is missing the stand, the moment or the points: %', v_first;
  END IF;

  -- R13: which prize, which stand, when.
  v_first := v_res->'claims'->0;
  IF v_first->>'reward' IS NULL OR v_first->>'stand' IS NULL OR v_first->>'at' IS NULL THEN
    RAISE EXCEPTION 'A handover in the lookup is missing the prize, the stand or the moment: %', v_first;
  END IF;

  -- R26: amount, reason and moment, so the balance can be read apart.
  v_first := v_res->'adjustments'->0;
  IF v_first->>'amount' IS NULL OR v_first->>'reason' IS NULL OR v_first->>'at' IS NULL THEN
    RAISE EXCEPTION 'An adjustment in the lookup is missing the amount, the reason or the moment: %', v_first;
  END IF;

  -- The device identity is half the key that returns a profile (spec 001), and
  -- the desk screen has no use for it.
  IF v_res->'participant' ? 'fingerprint' THEN
    RAISE EXCEPTION 'The lookup hands the attendee device identity to the desk screen';
  END IF;

  IF NOT (participant_detail('dddd0015-0000-4000-8000-0000000000ff') ? 'error') THEN
    RAISE EXCEPTION 'A lookup of an attendee who does not exist returned something other than an error';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- R27: earning, claiming and adjusting are the only three things that move a
-- balance. If the sum of them is not the balance, something else wrote to it.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_id UUID := pg_temp.zorro();
  v_earned INT;
  v_spent INT;
  v_granted INT;
  v_balance INT;
BEGIN
  SELECT COALESCE(SUM(points), 0) INTO v_earned FROM scans WHERE participant_id = v_id;
  SELECT COALESCE(SUM(r.cost), 0) INTO v_spent
  FROM claimed_rewards cr JOIN rewards r ON r.id = cr.reward_id
  WHERE cr.participant_id = v_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_granted FROM point_adjustments WHERE participant_id = v_id;
  SELECT points INTO v_balance FROM participants WHERE id = v_id;

  IF v_earned = 0 OR v_spent = 0 OR v_granted = 0 THEN
    RAISE EXCEPTION 'The decomposition check has nothing to decompose (earned %, spent %, granted %); it would pass by accident',
      v_earned, v_spent, v_granted;
  END IF;

  IF v_balance <> v_earned - v_spent + v_granted THEN
    RAISE EXCEPTION 'A balance of % cannot be decomposed: % earned at stands, % spent on prizes, % granted by the organiser. Some other writer moved these points and there is no record of it',
      v_balance, v_earned, v_spent, v_granted;
  END IF;
END;
$test$;

ROLLBACK;
