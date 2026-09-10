-- 20_schema.sql — app tables (canonical schema source).
-- (IF NOT EXISTS / ON CONFLICT guards added so re-provision never errors).
-- The plaintext `password` column is dropped later in 25_auth_columns.sql
-- (audit F2: credentials move to communities.password_hash + auth service).

-- Comunidades (antes "groups")
-- Los puntos ya no se configuran por comunidad: son constantes del evento
-- (spec 020). Una visita vale lo mismo en todos los stands, y una actividad
-- vale según sea o no el evento principal de su stand.
CREATE TABLE IF NOT EXISTS communities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  name TEXT NOT NULL,
  emoji TEXT DEFAULT 'BookOpen',
  stand_number TEXT,
  description TEXT,
  -- Retirada del evento por el organizador (spec 023). No se elimina nunca:
  -- los escaneos y canjes la referencian, y borrarla se llevaria el historial
  -- de todos los que pasaron por ella. Retirar es un estado; borrar, no.
  is_withdrawn BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Participantes
CREATE TABLE IF NOT EXISTS participants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  -- El nickname es tambien la llave con la que se vuelve al perfil (spec 001),
  -- asi que tiene limites: 24 caracteres es lo que entra en una fila del
  -- ranking proyectado, y sin tope una sola persona deforma la pantalla que
  -- mira todo el salon.
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 24),
  points INT DEFAULT 0 CHECK (points >= 0),
  fingerprint TEXT,
  -- Sanciones del organizador (spec 022). Retirado no participa en nada;
  -- bloqueado sigue jugando y sumando, pero no canjea: es la sancion que el
  -- registro anuncia para un nombre ofensivo. Ninguna borra nada.
  is_removed BOOLEAN NOT NULL DEFAULT false,
  claims_barred BOOLEAN NOT NULL DEFAULT false,
  registered_at TIMESTAMPTZ DEFAULT now()
);

-- Ajustes manuales de saldo (spec 022). Es el unico cambio de puntos que no
-- viene de escanear ni de canjear, y por eso lleva motivo: un numero sin
-- motivo no se distingue de un favor. Van en su propia tabla para que un saldo
-- pueda descomponerse en ganado y otorgado.
CREATE TABLE IF NOT EXISTS point_adjustments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE RESTRICT NOT NULL,
  amount INT NOT NULL CHECK (amount <> 0),
  reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 3 AND 200),
  adjusted_at TIMESTAMPTZ DEFAULT now()
);

-- Codigos de recuperacion (spec 022). Los emite el organizador cuando decide,
-- mirando a la persona, que el reclamo es genuino. El sistema no puede
-- distinguir a quien cambio de telefono de quien quiere el perfil ajeno; una
-- persona si.
CREATE TABLE IF NOT EXISTS recovery_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE RESTRICT NOT NULL,
  code TEXT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  closed_reason TEXT CHECK (closed_reason IN ('used', 'replaced'))
);

CREATE UNIQUE INDEX IF NOT EXISTS recovery_codes_one_open_per_participant
  ON recovery_codes (participant_id) WHERE closed_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS recovery_codes_open_code_unique
  ON recovery_codes (code) WHERE closed_at IS NULL;

-- Unico en todo el evento, sin distinguir mayusculas ni espacios. Es un indice
-- y no un chequeo previo porque dos personas eligiendo el mismo nickname libre
-- en el mismo instante no pueden ganar las dos: el costo de esa ambiguedad son
-- los puntos de alguien.
CREATE UNIQUE INDEX IF NOT EXISTS participants_nickname_unique
  ON participants (lower(btrim(name)));

-- Actividades (spec 019). Hasta 3 por comunidad, para todo el evento.
--
-- El estado NO se guarda: se deriva de started_at y finished_at, porque nada
-- en este stack corre en segundo plano. Una actividad que nadie cierra tiene
-- que terminarse sola al vencer su duración, y eso solo es cierto si el estado
-- es una pregunta que se responde en el momento, no una columna que alguien
-- tiene que ir a actualizar. Ver activity_state() en 52_activities.sql.
CREATE TABLE IF NOT EXISTS activities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  community_id UUID REFERENCES communities(id) ON DELETE RESTRICT NOT NULL,
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 3 AND 40),
  description TEXT NOT NULL CHECK (char_length(btrim(description)) BETWEEN 1 AND 100),
  estimated_start TIME NOT NULL,
  duration_min INT NOT NULL CHECK (duration_min BETWEEN 1 AND 60),
  is_main_event BOOLEAN NOT NULL DEFAULT false,
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  -- No se puede terminar lo que nunca empezó.
  CONSTRAINT activities_finished_implies_started
    CHECK (finished_at IS NULL OR started_at IS NOT NULL)
);

-- Un solo evento principal por comunidad. Sin esto, todas las actividades se
-- marcarían como principales: no hay ningún costo en hacerlo (spec 020, R7).
CREATE UNIQUE INDEX IF NOT EXISTS activities_one_main_event_per_community
  ON activities (community_id) WHERE is_main_event;

-- Una sola actividad en curso por comunidad. El stand proyecta un código a la
-- vez y atiende una cosa a la vez, y así "en curso" es inequívoco para el
-- estudiante (spec 019, R13).
CREATE UNIQUE INDEX IF NOT EXISTS activities_one_running_per_community
  ON activities (community_id) WHERE started_at IS NOT NULL AND finished_at IS NULL;

CREATE INDEX IF NOT EXISTS activities_community_idx ON activities (community_id);

-- Escaneos
CREATE TABLE IF NOT EXISTS scans (
  -- RESTRICT en todo lo que referencia historia: nada se elimina en este
  -- sistema. Con CASCADE la promesa dependia de que nadie escribiera un DELETE.
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE RESTRICT NOT NULL,
  community_id UUID REFERENCES communities(id) ON DELETE RESTRICT NOT NULL,
  -- RESTRICT, no CASCADE: una actividad no se elimina nunca (spec 019, R5) y
  -- los puntos otorgados no se retiran jamás (spec 020, R11). Con CASCADE esa
  -- promesa dependía de que nadie escribiera un DELETE; así la base se niega.
  activity_id UUID REFERENCES activities(id) ON DELETE RESTRICT,
  points INT NOT NULL CHECK (points >= 0),
  type TEXT CHECK (type IN ('visit', 'activity')) DEFAULT 'visit',
  created_at TIMESTAMPTZ DEFAULT now(),
  -- Una actividad siempre identifica cuál; una visita nunca.
  CONSTRAINT scans_activity_id_matches_type
    CHECK ((type = 'activity') = (activity_id IS NOT NULL))
);

-- Cada actividad se completa una sola vez por participante. Antes la regla era
-- una actividad por stand; con hasta 3 por stand la garantía se muda a la
-- actividad concreta (spec 020, R8). Sigue siendo un índice, no un IF: es lo
-- que sostiene cuando dos escaneos llegan en el mismo instante.
CREATE UNIQUE INDEX IF NOT EXISTS scans_one_completion_per_activity
  ON scans (participant_id, activity_id) WHERE (activity_id IS NOT NULL);

-- Premios (spec 021).
--
-- El techo de 300 puntos es la mitad de lo que rinde recorrer la feria entera
-- bajo el modelo del spec 020 (~600): quien hace la mitad ya puede aspirar al
-- premio más caro. Un premio por encima de lo alcanzable no lo reclama nadie.
--
-- is_withdrawn permite al organizador sacar un premio de la vitrina sin
-- borrarlo (spec 023): un canje ya confirmado tiene que seguir apuntando a algo
-- que existe. La columna existe desde ahora porque el catálogo tiene que
-- respetarla desde el momento en que aparece, aunque solo el spec 023 la
-- escriba.
CREATE TABLE IF NOT EXISTS rewards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  community_id UUID REFERENCES communities(id) ON DELETE RESTRICT NOT NULL,
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 3 AND 40),
  description TEXT CHECK (description IS NULL OR char_length(btrim(description)) <= 100),
  cost INT NOT NULL CHECK (cost BETWEEN 0 AND 300),
  stock INT DEFAULT 0 CHECK (stock >= 0),
  emoji TEXT DEFAULT 'Gift',
  is_withdrawn BOOLEAN NOT NULL DEFAULT false
);

-- Códigos de canje (spec 018).
--
-- El código es lo único que el sistema acepta como identificador de una
-- persona, así que todas las defensas viven sobre él: un solo uso, vida corta,
-- uno vivo por participante, e impredecible. Una foto del modal no vale nada
-- un momento después.
--
-- La vigencia se DERIVA, como el estado de una actividad: un código está vivo
-- mientras no se haya cerrado y su pantalla siga preguntando por él. Nada barre
-- nada; "¿este código sirve?" se responde cuando se presenta.
CREATE TABLE IF NOT EXISTS claim_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE CASCADE NOT NULL,
  code TEXT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  closed_reason TEXT CHECK (closed_reason IN ('used', 'replaced'))
);

-- Un solo código abierto por participante. Dos vivos dejarían al estudiante
-- parado en dos stands con un saldo que solo alcanza para uno.
CREATE UNIQUE INDEX IF NOT EXISTS claim_codes_one_open_per_participant
  ON claim_codes (participant_id) WHERE closed_at IS NULL;

-- Y ningún código abierto puede repetirse entre participantes.
CREATE UNIQUE INDEX IF NOT EXISTS claim_codes_open_code_unique
  ON claim_codes (code) WHERE closed_at IS NULL;

-- Premios reclamados
CREATE TABLE IF NOT EXISTS claimed_rewards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE RESTRICT NOT NULL,
  reward_id UUID REFERENCES rewards(id) ON DELETE RESTRICT NOT NULL,
  -- Qué stand entregó. Un canje confirmado tiene que poder decir quién lo hizo
  -- (spec 024), y el premio no se borra nunca, así que la referencia resuelve.
  confirmed_by UUID REFERENCES communities(id) ON DELETE RESTRICT,
  claimed_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(participant_id, reward_id)
);

-- Configuración (secreto HMAC). Fresh random per deployment — no rotation
-- needed on first boot (the F3 finding was about a previously public value).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO settings (key, value)
VALUES ('hmac_secret', gen_random_uuid()::text || gen_random_uuid()::text)
ON CONFLICT (key) DO NOTHING;
