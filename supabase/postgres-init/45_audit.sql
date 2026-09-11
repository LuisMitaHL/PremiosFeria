-- 45_audit.sql — el registro de actividad del evento (spec 024).
--
-- En una feria casi todo problema llega como una frase: "me dice que ya hice
-- esa actividad", "el stand me escaneo y no paso nada", "mi premio estaba hace
-- cinco minutos". Las tablas guardan lo que es cierto ahora, no lo que ocurrio,
-- y un rechazo no dejaba ninguna huella. Un rechazo es justamente de lo que
-- habla la mayoria de los reclamos: sin registro, "no paso nada" y "se rechazo
-- por el cooldown" se ven exactamente igual desde el mostrador.
--
-- Va numerado 45 y no 59 porque toda funcion que cambia algo escribe aca, y
-- esas funciones se crean desde 50 en adelante. El lector vive aparte, en
-- 59_audit_read.sql, porque necesita calling_organizer() (55).
--
-- Tres propiedades sostienen todo lo demas, y ninguna es una convencion:
--
--   Se escribe DENTRO de la accion. audit() es un INSERT mas en la misma
--   transaccion que el cambio, asi que ambos ocurren o ninguno ocurre (R20).
--   Si el asiento no se puede escribir, la accion falla (R21): no hay camino
--   por el que un cambio quede sin registrar y nada lo revele despues.
--
--   No se edita ni se borra, por nadie. Un registro que su lector puede
--   alterar no es evidencia, y el organizador es el unico lector: si pudiera
--   reescribirlo, sus propios ajustes de puntos serian negables (R18, R19).
--
--   No guarda secretos. Registrar una comunidad genera una contrasena;
--   canjear y recuperar generan codigos. Las tres son acciones que se
--   registran, y las tres deben quedar por lo que son y nunca por su valor
--   (R9). El disparador de mas abajo es la segunda cerradura de esa puerta.

CREATE TABLE IF NOT EXISTS audit_log (
  -- Identidad monotona, no uuid: dos acciones en el mismo instante tienen que
  -- poder leerse en orden, y `at` sola no alcanza para desempatarlas (R16).
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- 'ambito.verbo': 'scan.award', 'reward.reprice', 'participant.remove'. El
  -- ambito es lo que el organizador filtra desde la pantalla.
  action        TEXT NOT NULL CHECK (action ~ '^[a-z_]+\.[a-z_]+$'),
  outcome       TEXT NOT NULL CHECK (outcome IN ('ok', 'refused')),

  -- Quien lo hizo, resuelto por quien ya lo resolvio: cada RPC deduce a su
  -- llamante de auth.uid() antes de actuar, asi que lo pasa en vez de que este
  -- archivo lo vuelva a buscar. La identidad sigue sin ser un parametro del
  -- cliente (constitucion IV); es un parametro entre funciones del servidor.
  actor_kind    TEXT NOT NULL CHECK (actor_kind IN ('participant', 'stand', 'organizer', 'anonymous')),
  actor_id      UUID,

  -- Sobre que o sobre quien. La etiqueta se copia en el momento para que el
  -- asiento siga leyendose aunque despues renombren al estudiante o retiren el
  -- premio: un registro que hay que resolver contra el estado de hoy cuenta lo
  -- de hoy, no lo que paso.
  subject_kind  TEXT,
  subject_id    UUID,
  subject_label TEXT,

  -- Lo que la cosa cambiada valia ANTES. Sin esto el registro dice que un
  -- precio cambio pero no desde cuanto, que es exactamente lo que pregunta
  -- cualquiera (R7).
  before        JSONB,
  detail        JSONB,

  -- Un rechazo lleva su motivo o no sirve de nada (R10).
  reason        TEXT,
  CONSTRAINT audit_log_refusal_has_reason
    CHECK (outcome = 'ok' OR btrim(COALESCE(reason, '')) <> '')
);

-- Lectura filtrada y ordenada sobre una tabla grande, por un solo usuario.
-- A la escala de referencia son decenas de miles de asientos: poco para la
-- base, mucho para una pantalla (R17).
CREATE INDEX IF NOT EXISTS audit_log_recent_idx ON audit_log (id DESC);
CREATE INDEX IF NOT EXISTS audit_log_at_idx     ON audit_log (at DESC, id DESC);
CREATE INDEX IF NOT EXISTS audit_log_action_idx ON audit_log (split_part(action, '.', 1), id DESC);
CREATE INDEX IF NOT EXISTS audit_log_actor_idx  ON audit_log (actor_kind, actor_id, id DESC);

-- ---------------------------------------------------------------------------
-- Ningun cliente lo lee. RLS activa y sin una sola politica, como settings,
-- claim_codes y organizers: contiene los movimientos de todos los asistentes y
-- las operaciones de todos los stands. El organizador lo lee por
-- audit_read(), que corre como dueno y comprueba quien llama.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- 30_grants.sql concede SELECT, INSERT y UPDATE sobre todas las tablas, y sus
-- ALTER DEFAULT PRIVILEGES se los conceden tambien a las que se crean despues
-- — esta entre ellas. RLS ya bloquearia la escritura, pero "no se edita" no
-- puede depender de una sola cerradura (constitucion VI).
REVOKE ALL ON public.audit_log FROM PUBLIC;
DO $grants$
DECLARE v_roles TEXT;
BEGIN
  SELECT string_agg(quote_ident(rolname), ', ' ORDER BY rolname) INTO v_roles
  FROM pg_roles WHERE rolname IN ('anon', 'authenticated');
  IF v_roles IS NOT NULL THEN
    EXECUTE format('REVOKE ALL ON public.audit_log FROM %s', v_roles);
  END IF;
END;
$grants$;

-- La tercera cerradura, y la unica que tambien alcanza al dueno. Las dos
-- anteriores son privilegios, y un SECURITY DEFINER corre como postgres: sin
-- esto, "nadie edita un asiento, ni el organizador" seria falso para cualquier
-- funcion que alguien agregue manana.
CREATE OR REPLACE FUNCTION audit_log_is_append_only() RETURNS TRIGGER
LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION 'El registro de actividad no se edita ni se borra (spec 024, R18 y R19).';
END;
$fn$;

DROP TRIGGER IF EXISTS audit_log_no_update ON audit_log;
CREATE TRIGGER audit_log_no_update
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_is_append_only();

-- TRUNCATE no dispara triggers de fila, asi que se bloquea aparte: vaciar la
-- tabla borra tanto como borrar sus filas de a una.
DROP TRIGGER IF EXISTS audit_log_no_truncate ON audit_log;
CREATE TRIGGER audit_log_no_truncate
  BEFORE TRUNCATE ON audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION audit_log_is_append_only();

-- ---------------------------------------------------------------------------
-- El registro no puede ser la fuga.
--
-- Las contrasenas, los codigos de canje y los de recuperacion pasan todos por
-- acciones que se registran. Una sola llamada descuidada convierte la unica
-- pantalla que el organizador mira todo el dia en el blanco mas blando del
-- sistema. Los nombres prohibidos se comprueban en la escritura, no en la
-- revision de codigo, porque el lugar donde esto se olvida es el campo `before`
-- — el que se llena copiando la fila anterior entera.
CREATE OR REPLACE FUNCTION audit_log_holds_no_secret() RETURNS TRIGGER
LANGUAGE plpgsql AS $fn$
DECLARE
  v_prohibidas TEXT[] := ARRAY[
    'password', 'password_hash', 'contrasena', 'pass',
    'code', 'claim_code', 'recovery_code', 'short_code', 'shortcode',
    'fingerprint', 'token', 'tok', 'secret', 'hmac_secret'
  ];
  v_campo TEXT;
  v_clave TEXT;
BEGIN
  FOREACH v_campo IN ARRAY ARRAY['before', 'detail'] LOOP
    -- A cualquier profundidad, y tambien dentro de arreglos. jsonb_object_keys
    -- solo mira el primer nivel, y con eso un before con forma
    -- {"community": {"password_hash": "..."}} pasaba la cerradura entera —
    -- justo la forma que sale de copiar una fila anidada, que es el error que
    -- este disparador existe para atajar.
    FOR v_clave IN
      SELECT jsonb_path_query(
               CASE v_campo WHEN 'before' THEN NEW.before ELSE NEW.detail END,
               'strict $.**?(@.type() == "object").keyvalue()') ->> 'key'
    LOOP
      IF lower(v_clave) = ANY (v_prohibidas) THEN
        RAISE EXCEPTION
          'El asiento % lleva "%" en %, que es un secreto. Registra que la accion ocurrio, nunca el valor (spec 024, R9).',
          NEW.action, v_clave, v_campo;
      END IF;
    END LOOP;
  END LOOP;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS audit_log_no_secrets ON audit_log;
CREATE TRIGGER audit_log_no_secrets
  BEFORE INSERT ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_holds_no_secret();

-- ---------------------------------------------------------------------------
-- El escritor.
--
-- Un INSERT y nada mas: corre dentro de la transaccion de quien llama, de modo
-- que el asiento y el cambio se confirman juntos o no se confirma ninguno. No
-- atrapa excepciones a proposito — si no puede escribir, la accion debe fallar
-- (R21). Los parametros van con nombre en cada llamada; son demasiados para
-- leerlos por posicion.
CREATE OR REPLACE FUNCTION audit(
  p_action        TEXT,
  p_outcome       TEXT,
  p_actor_kind    TEXT,
  p_actor_id      UUID    DEFAULT NULL,
  p_subject_kind  TEXT    DEFAULT NULL,
  p_subject_id    UUID    DEFAULT NULL,
  p_subject_label TEXT    DEFAULT NULL,
  p_before        JSONB   DEFAULT NULL,
  p_detail        JSONB   DEFAULT NULL,
  p_reason        TEXT    DEFAULT NULL
) RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $fn$
  INSERT INTO audit_log (action, outcome, actor_kind, actor_id,
                         subject_kind, subject_id, subject_label,
                         before, detail, reason)
  VALUES (p_action, p_outcome, p_actor_kind, p_actor_id,
          p_subject_kind, p_subject_id, p_subject_label,
          p_before, p_detail, p_reason);
$fn$;

-- Quien llama, para las funciones que aun no lo resolvieron cuando tienen que
-- registrar un rechazo (el caso tipico: rechazar precisamente porque no se
-- pudo resolver). Devuelve 'anonymous' cuando no hay sesion.
CREATE OR REPLACE FUNCTION audit_actor() RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN 'anonymous'; END IF;
  IF EXISTS (SELECT 1 FROM organizers   WHERE auth_user_id = v_uid) THEN RETURN 'organizer'; END IF;
  IF EXISTS (SELECT 1 FROM communities  WHERE auth_user_id = v_uid) THEN RETURN 'stand'; END IF;
  IF EXISTS (SELECT 1 FROM participants WHERE auth_user_id = v_uid) THEN RETURN 'participant'; END IF;
  RETURN 'anonymous';
END;
$fn$;

-- El id de quien llama, en el MISMO espacio de identificadores que usan las
-- funciones que ya lo resolvieron: el id de participante, de comunidad o de
-- organizador, nunca el sub del token. Si se mezclaran los dos espacios,
-- filtrar el registro por un stand dejaria fuera justamente sus intentos
-- rechazados, que son los que alguien va a querer mirar.
CREATE OR REPLACE FUNCTION audit_actor_id() RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM organizers   WHERE auth_user_id = v_uid;
  IF FOUND THEN RETURN v_id; END IF;
  SELECT id INTO v_id FROM communities  WHERE auth_user_id = v_uid;
  IF FOUND THEN RETURN v_id; END IF;
  SELECT id INTO v_id FROM participants WHERE auth_user_id = v_uid;
  IF FOUND THEN RETURN v_id; END IF;
  RETURN NULL;
END;
$fn$;

-- ---------------------------------------------------------------------------
-- El escritor no es un endpoint.
--
-- PostgREST publica como /rpc/<nombre> toda funcion de public que el rol del
-- cliente pueda ejecutar, y Postgres concede EXECUTE a PUBLIC por defecto. Sin
-- esto, cualquiera con la clave publicable llama a /rpc/audit y fabrica
-- asientos — "scan.award ok" a nombre de quien quiera — en la unica pantalla
-- que el organizador mira toda la tarde. Un registro en el que un tercero
-- puede escribir no vale mas que uno que se puede editar.
--
-- Las funciones que lo llaman son SECURITY DEFINER y corren como el dueno, asi
-- que revocar no rompe ninguna: el permiso se comprueba contra el dueno.
--
-- audit_read y audit_kinds no aparecen aca a proposito: comprueban
-- calling_organizer() por dentro, que es donde tiene que estar la decision.
REVOKE ALL ON FUNCTION audit(TEXT, TEXT, TEXT, UUID, TEXT, UUID, TEXT, JSONB, JSONB, TEXT)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION audit_actor()    FROM PUBLIC;
REVOKE ALL ON FUNCTION audit_actor_id() FROM PUBLIC;
DO $revokes$
DECLARE v_roles TEXT; v_fn TEXT;
BEGIN
  SELECT string_agg(quote_ident(rolname), ', ' ORDER BY rolname) INTO v_roles
  FROM pg_roles WHERE rolname IN ('anon', 'authenticated');
  IF v_roles IS NULL THEN RETURN; END IF;
  FOREACH v_fn IN ARRAY ARRAY[
    'audit(TEXT, TEXT, TEXT, UUID, TEXT, UUID, TEXT, JSONB, JSONB, TEXT)',
    'audit_actor()',
    'audit_actor_id()'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM %s', v_fn, v_roles);
  END LOOP;
END;
$revokes$;
