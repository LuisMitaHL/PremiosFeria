-- 40_rls.sql — canonical RLS source (policies for public tables).
-- Participantes: cualquiera puede leer (leaderboard), insertar (registro)
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "participants_read" ON participants;
CREATE POLICY "participants_read" ON participants FOR SELECT USING (true);

DROP POLICY IF EXISTS "participants_insert" ON participants;
CREATE POLICY "participants_insert" ON participants FOR INSERT WITH CHECK (auth_user_id = auth.uid());

-- Comunidades: lectura pública, edición solo por su admin (vinculado vía auth_user_id)
ALTER TABLE communities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "communities_read" ON communities;
CREATE POLICY "communities_read" ON communities FOR SELECT USING (true);

DROP POLICY IF EXISTS "communities_update" ON communities;
CREATE POLICY "communities_update" ON communities FOR UPDATE
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- Actividades: lectura publica (el estudiante ve las de toda la feria); toda
-- escritura pasa por RPC, igual que scans
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "activities_read" ON activities;
CREATE POLICY "activities_read" ON activities FOR SELECT USING (true);

-- Scans: lectura publica, insert via RPC unicamente
ALTER TABLE scans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "scans_read" ON scans;
CREATE POLICY "scans_read" ON scans FOR SELECT USING (true);

-- Settings: sin acceso público; solo funciones SECURITY DEFINER leen el secreto
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "settings_read" ON settings;

-- Rewards: lectura pública
ALTER TABLE rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rewards_read" ON rewards;
CREATE POLICY "rewards_read" ON rewards FOR SELECT USING (true);

-- Códigos de canje: RLS activa y SIN ninguna política, igual que settings.
-- Ningún cliente los lee ni los escribe: el estudiante consulta el suyo por RPC
-- y el stand lo presenta al confirmar. Un código legible por cualquiera es la
-- capacidad de caminar hasta cualquier stand y gastarle los puntos a otro.
ALTER TABLE claim_codes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "claim_codes_read" ON claim_codes;

-- Claimed rewards: lectura pública, insert via RPC
ALTER TABLE claimed_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "claimed_rewards_read" ON claimed_rewards;
CREATE POLICY "claimed_rewards_read" ON claimed_rewards FOR SELECT USING (true);
