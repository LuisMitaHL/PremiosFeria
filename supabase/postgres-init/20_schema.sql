-- 20_schema.sql — app tables. Faithful to "schema SQL community quest.txt"
-- (IF NOT EXISTS / ON CONFLICT guards added so re-provision never errors).
-- The plaintext `password` column is dropped later in 25_auth_columns.sql
-- (audit F2: credentials move to communities.password_hash + auth service).

-- Comunidades (antes "groups")
CREATE TABLE IF NOT EXISTS communities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  name TEXT NOT NULL,
  emoji TEXT DEFAULT 'BookOpen',
  stand_number TEXT,
  description TEXT,
  visit_points INT DEFAULT 10 CHECK (visit_points BETWEEN 0 AND 30),
  activity_points INT DEFAULT 25 CHECK (activity_points BETWEEN 0 AND 100),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Participantes
CREATE TABLE IF NOT EXISTS participants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  points INT DEFAULT 0 CHECK (points >= 0),
  fingerprint TEXT,
  registered_at TIMESTAMPTZ DEFAULT now()
);

-- Escaneos
CREATE TABLE IF NOT EXISTS scans (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE CASCADE NOT NULL,
  community_id UUID REFERENCES communities(id) ON DELETE CASCADE NOT NULL,
  points INT NOT NULL CHECK (points >= 0),
  type TEXT CHECK (type IN ('visit', 'activity')) DEFAULT 'visit',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Actividades: una sola vez por stand y participante (las visitas siguen siendo repetibles tras su cooldown)
CREATE UNIQUE INDEX IF NOT EXISTS scans_one_activity_per_stand
  ON scans (participant_id, community_id) WHERE (type = 'activity');

-- Premios
CREATE TABLE IF NOT EXISTS rewards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  community_id UUID REFERENCES communities(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  cost INT NOT NULL CHECK (cost >= 0),
  stock INT DEFAULT 0 CHECK (stock >= 0),
  emoji TEXT DEFAULT 'Gift'
);

-- Premios reclamados
CREATE TABLE IF NOT EXISTS claimed_rewards (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  participant_id UUID REFERENCES participants(id) ON DELETE CASCADE NOT NULL,
  reward_id UUID REFERENCES rewards(id) ON DELETE CASCADE NOT NULL,
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
