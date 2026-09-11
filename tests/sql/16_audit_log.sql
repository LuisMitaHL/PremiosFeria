-- The system audit log (spec 024).
--
-- A log is worth exactly what its weakest guarantee is worth, so most of this
-- file is about what the log REFUSES to do rather than what it records. Three
-- properties carry everything: an entry cannot be changed or removed by anyone
-- including the organiser, an entry cannot hold a secret, and an action and its
-- entry commit together. Break any one and the screen the organiser reads all
-- afternoon stops being evidence and becomes a rumour with timestamps.
\set ON_ERROR_STOP on
BEGIN;

-- ---------------------------------------------------------------------------
-- Fixtures. Nothing here depends on seed data.
-- ---------------------------------------------------------------------------

INSERT INTO organizers (id, username, password_hash, auth_user_id) VALUES
  ('0e9a0016-0000-4000-8000-00000000000a', 'audit_org',
   crypt('Organiza2026*', gen_salt('bf', 12)), '0e9a0016-0000-4000-8000-00000000000a');

INSERT INTO communities (id, username, password_hash, name, auth_user_id) VALUES
  ('aaaa0016-0000-4000-8000-00000000000a', 'audit_stand',
   crypt('Stand2026*', gen_salt('bf', 12)), 'Stand Auditoria',
   'aaaa0016-0000-4000-8000-00000000000a');

INSERT INTO participants (id, name, points, fingerprint, auth_user_id) VALUES
  ('cccc0016-0000-4000-8000-000000000001', 'zorro', 100, 'huella-zorro',
   'cccc0016-0000-4000-8000-000000000001');

INSERT INTO rewards (id, community_id, name, cost, stock) VALUES
  ('eeee0016-0000-4000-8000-000000000001', 'aaaa0016-0000-4000-8000-00000000000a',
   'Taza', 50, 1);

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

CREATE FUNCTION pg_temp.as_organizer() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  PERFORM pg_temp.act_as('0e9a0016-0000-4000-8000-00000000000a');
END;
$fn$;

CREATE FUNCTION pg_temp.zorro() RETURNS UUID LANGUAGE sql AS $fn$
  SELECT 'cccc0016-0000-4000-8000-000000000001'::UUID
$fn$;

-- ---------------------------------------------------------------------------
-- Append-only means append-only, and it also binds the owner.
--
-- Privileges and RLS stop a client. Neither stops a SECURITY DEFINER function,
-- and every rule in this system is one. This suite runs as the owner precisely
-- so that it tests the lock that matters.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE v_id BIGINT;
BEGIN
  PERFORM audit(p_action => 'scan.award', p_outcome => 'ok',
                p_actor_kind => 'participant', p_actor_id => pg_temp.zorro());
  SELECT max(id) INTO v_id FROM audit_log;

  BEGIN
    UPDATE audit_log SET reason = 'reescrito' WHERE id = v_id;
    RAISE EXCEPTION 'An entry was edited. The organiser is the only reader of this log, so an entry they can rewrite makes their own point adjustments deniable';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'An entry was edited%' THEN RAISE; END IF;
  END;

  BEGIN
    DELETE FROM audit_log WHERE id = v_id;
    RAISE EXCEPTION 'An entry was deleted. A log somebody can remove a line from records only what that somebody allows';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'An entry was deleted%' THEN RAISE; END IF;
  END;

  IF NOT EXISTS (SELECT 1 FROM audit_log WHERE id = v_id) THEN
    RAISE EXCEPTION 'The entry is gone even though the delete was refused';
  END IF;
END;
$test$;

-- TRUNCATE does not fire row triggers, so it is its own door. Emptying the
-- table erases exactly as much as deleting its rows one by one.
DO $test$
BEGIN
  BEGIN
    TRUNCATE audit_log;
    RAISE EXCEPTION 'The whole log was truncated. Row-level protection is not protection if the table can be emptied in one statement';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'The whole log was truncated%' THEN RAISE; END IF;
  END;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A refusal without its reason is not worth writing: it cannot answer the one
-- question it exists to answer.
-- ---------------------------------------------------------------------------
DO $test$
BEGIN
  BEGIN
    PERFORM audit(p_action => 'scan.award', p_outcome => 'refused',
                  p_actor_kind => 'participant', p_actor_id => pg_temp.zorro());
    RAISE EXCEPTION 'A refusal was recorded with no reason, which is indistinguishable from a refusal nobody understands';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'A refusal was recorded%' THEN RAISE; END IF;
  WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    PERFORM audit(p_action => 'scan.award', p_outcome => 'refused',
                  p_actor_kind => 'participant', p_actor_id => pg_temp.zorro(),
                  p_reason => '   ');
    RAISE EXCEPTION 'A refusal was recorded with a blank reason';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'A refusal was recorded%' THEN RAISE; END IF;
  WHEN check_violation THEN
    NULL;
  END;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The log must not become the leak.
--
-- Registering a community generates a password; claiming and recovery generate
-- codes. All three are logged actions. The easy place to forget is `before`,
-- which gets filled by copying the previous row wholesale.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_campo TEXT;
  v_clave TEXT;
BEGIN
  FOREACH v_clave IN ARRAY ARRAY['password', 'password_hash', 'fingerprint',
                                 'code', 'recovery_code', 'token', 'secret'] LOOP
    FOREACH v_campo IN ARRAY ARRAY['before', 'detail'] LOOP
      BEGIN
        IF v_campo = 'before' THEN
          PERFORM audit(p_action => 'community.create', p_outcome => 'ok',
                        p_actor_kind => 'organizer',
                        p_before => jsonb_build_object(v_clave, 'valor'));
        ELSE
          PERFORM audit(p_action => 'community.create', p_outcome => 'ok',
                        p_actor_kind => 'organizer',
                        p_detail => jsonb_build_object(v_clave, 'valor'));
        END IF;
        RAISE EXCEPTION 'The log accepted "%" in %. That key holds a secret, and the log is the one screen the organiser leaves open all afternoon', v_clave, v_campo;
      EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'The log accepted%' THEN RAISE; END IF;
      END;
    END LOOP;
  END LOOP;
END;
$test$;

-- Copying a whole row into `before` is the mistake the trigger exists for: it
-- is how a fingerprint or a bcrypt hash ends up in a log nobody meant to put
-- it in.
DO $test$
BEGIN
  BEGIN
    PERFORM audit(p_action => 'participant.set_flags', p_outcome => 'ok',
                  p_actor_kind => 'organizer',
                  p_before => (SELECT to_jsonb(p) FROM participants p WHERE id = pg_temp.zorro()));
    RAISE EXCEPTION 'A whole participants row was copied into an entry, publishing the fingerprint that is half of the key to that profile';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'A whole participants row%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM audit(p_action => 'community.update', p_outcome => 'ok',
                  p_actor_kind => 'organizer',
                  p_before => (SELECT to_jsonb(c) FROM communities c
                               WHERE id = 'aaaa0016-0000-4000-8000-00000000000a'));
    RAISE EXCEPTION 'A whole communities row was copied into an entry, publishing the bcrypt hash of a stand password';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'A whole communities row%' THEN RAISE; END IF;
  END;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Reading is scoped to the organiser. The log holds every attendee's movements
-- and every stand's operations; a stand calling the function directly is the
-- attack this refuses.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_actor TEXT;
  v_res   JSONB;
BEGIN
  FOREACH v_actor IN ARRAY ARRAY['An attendee', 'A stand', 'A caller with no session'] LOOP
    IF    v_actor = 'An attendee' THEN PERFORM pg_temp.act_as(pg_temp.zorro());
    ELSIF v_actor = 'A stand'     THEN PERFORM pg_temp.act_as('aaaa0016-0000-4000-8000-00000000000a');
    ELSE  PERFORM pg_temp.no_session();
    END IF;

    v_res := audit_read();
    IF NOT (v_res ? 'error') THEN
      RAISE EXCEPTION '% read the audit log: every attendee movement and every stand operation in the fair', v_actor;
    END IF;
    IF v_res ? 'entries' THEN
      RAISE EXCEPTION '% was refused but still received entries', v_actor;
    END IF;
  END LOOP;
END;
$test$;

-- A secret does not have to be at the top level to be published. `before` is
-- filled by copying, and copying nests: {"community": {"password_hash": ...}}
-- is the exact shape the careless version of this guard let through.
DO $test$
DECLARE v_forma JSONB;
BEGIN
  FOREACH v_forma IN ARRAY ARRAY[
    '{"community": {"password_hash": "$2a$12$abcdefghijklmnopqrstuv"}}'::jsonb,
    '{"a": {"b": {"c": {"fingerprint": "huella"}}}}'::jsonb,
    '{"claims": [{"code": "ABC123"}]}'::jsonb,
    '{"nested": [[{"token": "t"}]]}'::jsonb
  ] LOOP
    BEGIN
      PERFORM audit(p_action => 'community.update', p_outcome => 'ok',
                    p_actor_kind => 'organizer', p_before => v_forma);
      RAISE EXCEPTION 'A secret nested inside % reached the log. Only the top level was being checked, and `before` is filled by copying rows, which nests', v_forma;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM LIKE 'A secret nested inside%' THEN RAISE; END IF;
    END;
  END LOOP;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Every action writes its entry, and a change carries what it changed from.
--
-- This is the assertion that catches the whole point of the spec: a reward that
-- everybody agrees used to cost 200 and now costs 20 is unanswerable unless the
-- entry holds the 200.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_comunidad UUID;
  v_premio    UUID;
  v_res       JSONB;
  v_antes     JSONB;
  v_clave     TEXT;
BEGIN
  PERFORM pg_temp.as_organizer();

  v_res := create_community('Comunidad Auditada', 'auditada', '7', 'Cpu', 'Una descripcion');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Creating a community failed: %', v_res->>'error';
  END IF;
  v_comunidad := (v_res->'community'->>'id')::UUID;
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'community.create' AND outcome = 'ok'
                   AND actor_kind = 'organizer' AND subject_id = v_comunidad) THEN
    RAISE EXCEPTION 'Creating a community left no entry';
  END IF;

  -- La contrasena generada no puede estar en ninguna parte del registro.
  v_clave := v_res->>'password';
  IF v_clave IS NULL THEN
    RAISE EXCEPTION 'The fixture assumed create_community returns the generated password and it does not, so the leak check below would pass on nothing';
  END IF;
  IF EXISTS (SELECT 1 FROM audit_log WHERE (audit_log.*)::text LIKE '%' || v_clave || '%') THEN
    RAISE EXCEPTION 'The password generated for a new stand is sitting in the audit log';
  END IF;

  v_res := reset_community_password(v_comunidad);
  v_clave := v_res->>'password';
  IF EXISTS (SELECT 1 FROM audit_log WHERE (audit_log.*)::text LIKE '%' || v_clave || '%') THEN
    RAISE EXCEPTION 'The password from a reset is sitting in the audit log';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'community.reset_password' AND subject_id = v_comunidad) THEN
    RAISE EXCEPTION 'Resetting a stand password left no entry';
  END IF;

  -- Retirar y reincorporar, con el valor anterior en cada uno.
  PERFORM set_community_withdrawn(v_comunidad, true);
  SELECT before INTO v_antes FROM audit_log
  WHERE action = 'community.set_withdrawn' AND subject_id = v_comunidad
  ORDER BY id DESC LIMIT 1;
  IF v_antes->>'is_withdrawn' <> 'false' THEN
    RAISE EXCEPTION 'Withdrawing a community recorded a previous state of % instead of false', v_antes;
  END IF;

  -- Un premio que cambia de precio: el asiento tiene que decir desde cuanto.
  INSERT INTO rewards (community_id, name, cost, stock)
  VALUES (v_comunidad, 'Premio Auditado', 200, 5) RETURNING id INTO v_premio;

  PERFORM set_reward_cost(v_premio, 20);
  SELECT before INTO v_antes FROM audit_log
  WHERE action = 'reward.reprice' AND subject_id = v_premio ORDER BY id DESC LIMIT 1;
  IF v_antes IS NULL OR (v_antes->>'cost')::int <> 200 THEN
    RAISE EXCEPTION 'Repricing a reward from 200 to 20 recorded a previous cost of %. Without it the log confirms there was an argument instead of settling it', v_antes;
  END IF;

  PERFORM set_reward_stock(v_premio, 3);
  SELECT before INTO v_antes FROM audit_log
  WHERE action = 'reward.set_stock' AND subject_id = v_premio ORDER BY id DESC LIMIT 1;
  IF v_antes IS NULL OR (v_antes->>'stock')::int <> 5 THEN
    RAISE EXCEPTION 'Restocking recorded a previous stock of % instead of 5', v_antes;
  END IF;

  PERFORM set_reward_withdrawn(v_premio, true);
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'reward.withdraw' AND subject_id = v_premio) THEN
    RAISE EXCEPTION 'Withdrawing a reward left no entry';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- The writer is not an endpoint.
--
-- PostgREST publishes every function in `public` the caller's role may execute,
-- and Postgres grants EXECUTE to PUBLIC by default. A client that can call
-- audit() directly can forge entries -- "scan.award ok" attributed to anyone --
-- in the one screen the organiser reads all afternoon. A log a third party can
-- write to is worth no more than one they can edit.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_rol TEXT;
  v_fn  TEXT;
BEGIN
  FOREACH v_rol IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol);

    FOREACH v_fn IN ARRAY ARRAY[
      'audit(TEXT, TEXT, TEXT, UUID, TEXT, UUID, TEXT, JSONB, JSONB, TEXT)',
      'audit_actor()',
      'audit_actor_id()',
      'scan_refused(UUID, UUID, TEXT, TEXT)',
      'handover_refused(UUID, UUID, TEXT, TEXT)'
    ] LOOP
      IF has_function_privilege(v_rol, 'public.' || v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'Role % can execute %, so PostgREST publishes it and any client holding the publishable key can write entries into the audit log', v_rol, v_fn;
      END IF;
    END LOOP;

    -- El lector si es un endpoint: decide por dentro, con calling_organizer().
    IF NOT has_function_privilege(v_rol, 'public.audit_read(TEXT, TEXT, UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, BIGINT, INT)', 'EXECUTE') THEN
      RAISE EXCEPTION 'Role % cannot execute audit_read, so the organiser panel cannot reach the log at all', v_rol;
    END IF;
  END LOOP;
END;
$test$;

-- Nobody reads the table directly either: RLS on, and not one policy.
DO $test$
DECLARE v_politicas INT;
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.audit_log'::regclass) THEN
    RAISE EXCEPTION 'Row level security is off on audit_log';
  END IF;
  SELECT count(*) INTO v_politicas FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'audit_log';
  IF v_politicas <> 0 THEN
    RAISE EXCEPTION 'audit_log has % policies. It is meant to have none: the organiser reads it through a function that checks who is calling', v_politicas;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A stand's own actions: activities and rewards.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_stand    UUID := 'aaaa0016-0000-4000-8000-00000000000a';
  v_res      JSONB;
  v_actividad UUID;
  v_premio   UUID;
  v_antes    JSONB;
BEGIN
  PERFORM pg_temp.act_as(v_stand);

  v_res := create_activity('Taller de soldadura', 'Traer gafas', '10:30'::TIME, 45, false);
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Creating an activity failed: %', v_res->>'error';
  END IF;
  v_actividad := (v_res->'activity'->>'id')::UUID;
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'activity.create' AND outcome = 'ok'
                   AND actor_kind = 'stand' AND actor_id = v_stand
                   AND subject_id = v_actividad) THEN
    RAISE EXCEPTION 'Creating an activity left no entry, or did not attribute it to the stand';
  END IF;

  PERFORM start_activity(v_actividad);
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'activity.start' AND subject_id = v_actividad) THEN
    RAISE EXCEPTION 'Starting an activity left no entry';
  END IF;

  PERFORM finish_activity(v_actividad);
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'activity.finish' AND subject_id = v_actividad) THEN
    RAISE EXCEPTION 'Finishing an activity left no entry';
  END IF;

  v_res := create_reward('Llavero', 30, 4, 'Key', 'De metal');
  IF v_res ? 'error' THEN
    RAISE EXCEPTION 'Registering a reward failed: %', v_res->>'error';
  END IF;
  v_premio := (v_res->'reward'->>'id')::UUID;
  IF NOT EXISTS (SELECT 1 FROM audit_log
                 WHERE action = 'reward.create' AND subject_id = v_premio) THEN
    RAISE EXCEPTION 'Registering a reward left no entry';
  END IF;

  PERFORM increase_reward_stock(v_premio, 3);
  SELECT before INTO v_antes FROM audit_log
  WHERE action = 'reward.restock' AND subject_id = v_premio ORDER BY id DESC LIMIT 1;
  IF v_antes IS NULL OR (v_antes->>'stock')::int <> 4 THEN
    RAISE EXCEPTION 'Restocking from 4 by 3 recorded a previous stock of % instead of 4', v_antes;
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- A refusal is recorded as such, with the reason the caller was given. Most
-- complaints at a fair are about something that did NOT happen, and without
-- this "there is no record" and "it was refused" look identical.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res    JSONB;
  v_motivo TEXT;
BEGIN
  PERFORM pg_temp.act_as(pg_temp.zorro());
  v_res := create_activity('Taller ajeno', NULL, '11:00'::TIME, 30, false);
  IF NOT (v_res ? 'error') THEN
    RAISE EXCEPTION 'An attendee created an activity';
  END IF;

  SELECT reason INTO v_motivo FROM audit_log
  WHERE action = 'activity.create' AND outcome = 'refused' ORDER BY id DESC LIMIT 1;
  IF v_motivo IS NULL THEN
    RAISE EXCEPTION 'A refused activity creation left no entry. A refusal nobody recorded is indistinguishable from an attempt nobody made';
  END IF;
  IF v_motivo <> (v_res->>'error') THEN
    RAISE EXCEPTION 'The log recorded "%" but the caller was told "%". A reason that drifts from the message answers a different question than the one being asked at the desk', v_motivo, v_res->>'error';
  END IF;
END;
$test$;

-- ---------------------------------------------------------------------------
-- Reading it: filters, order, and paging that returns each entry once.
-- ---------------------------------------------------------------------------
DO $test$
DECLARE
  v_res     JSONB;
  v_total   INT;
  v_ids     BIGINT[];
  v_cursor  BIGINT;
  v_pagina  JSONB;
  v_vueltas INT := 0;
BEGIN
  PERFORM pg_temp.as_organizer();

  -- Por ambito.
  v_res := audit_read(p_kind => 'activity');
  IF v_res ? 'error' THEN RAISE EXCEPTION 'The organiser was refused: %', v_res->>'error'; END IF;
  IF jsonb_array_length(v_res->'entries') = 0 THEN
    RAISE EXCEPTION 'Filtering by the activity scope returned nothing, though activities were created above';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'entries') e
             WHERE split_part(e->>'action', '.', 1) <> 'activity') THEN
    RAISE EXCEPTION 'Filtering by scope returned entries from another scope';
  END IF;

  -- Por resultado, y las dos juntas (R15).
  v_res := audit_read(p_kind => 'activity', p_outcome => 'refused');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'entries') e
             WHERE e->>'outcome' <> 'refused'
                OR split_part(e->>'action', '.', 1) <> 'activity') THEN
    RAISE EXCEPTION 'Combining two filters returned entries matching only one of them';
  END IF;

  -- Por actor.
  v_res := audit_read(p_actor_kind => 'organizer');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_res->'entries') e
             WHERE e->>'actor_kind' <> 'organizer') THEN
    RAISE EXCEPTION 'Filtering by actor returned somebody else''s actions';
  END IF;

  -- Por rango de tiempo: una ventana ya cerrada no devuelve nada de ahora.
  v_res := audit_read(p_from => now() - interval '2 days', p_to => now() - interval '1 day');
  IF jsonb_array_length(v_res->'entries') <> 0 THEN
    RAISE EXCEPTION 'A time range entirely in the past returned entries written just now';
  END IF;
  v_res := audit_read(p_from => now() - interval '1 hour');
  IF jsonb_array_length(v_res->'entries') = 0 THEN
    RAISE EXCEPTION 'A time range covering the last hour returned nothing';
  END IF;

  -- Orden: mas nuevo primero, sin empates (R16).
  v_res := audit_read(p_limit => 50);
  SELECT array_agg((e->>'id')::BIGINT ORDER BY ord)
  INTO v_ids
  FROM jsonb_array_elements(v_res->'entries') WITH ORDINALITY AS t(e, ord);
  FOR v_vueltas IN 2 .. COALESCE(array_length(v_ids, 1), 1) LOOP
    IF v_ids[v_vueltas] >= v_ids[v_vueltas - 1] THEN
      RAISE EXCEPTION 'Entries came back out of order: % then %', v_ids[v_vueltas - 1], v_ids[v_vueltas];
    END IF;
  END LOOP;

  -- Paginado: cada asiento exactamente una vez, sin repetir ni saltear (R17).
  SELECT count(*) INTO v_total FROM audit_log;
  v_ids := ARRAY[]::BIGINT[];
  v_cursor := NULL;
  v_vueltas := 0;
  LOOP
    v_pagina := audit_read(p_cursor => v_cursor, p_limit => 3);
    SELECT v_ids || COALESCE(array_agg((e->>'id')::BIGINT), ARRAY[]::BIGINT[])
    INTO v_ids
    FROM jsonb_array_elements(v_pagina->'entries') e;
    v_cursor := (v_pagina->>'nextCursor')::BIGINT;
    v_vueltas := v_vueltas + 1;
    EXIT WHEN v_cursor IS NULL OR v_vueltas > 200;
  END LOOP;

  IF array_length(v_ids, 1) <> v_total THEN
    RAISE EXCEPTION 'Paging through the log returned % entries out of %', array_length(v_ids, 1), v_total;
  END IF;
  IF array_length(v_ids, 1) <> (SELECT count(DISTINCT u) FROM unnest(v_ids) u) THEN
    RAISE EXCEPTION 'Paging returned the same entry more than once';
  END IF;

  -- El tamano de pagina lo acota el servidor, no el cliente.
  v_res := audit_read(p_limit => 100000);
  IF jsonb_array_length(v_res->'entries') > 200 THEN
    RAISE EXCEPTION 'A client asked for 100000 entries and got %. R17 stops meaning anything if the page size is the caller''s to choose', jsonb_array_length(v_res->'entries');
  END IF;
END;
$test$;

ROLLBACK;
