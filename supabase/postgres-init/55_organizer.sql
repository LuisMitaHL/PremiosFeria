-- 55_organizer.sql — the event organiser (spec 017).
--
-- A separate table, deliberately. An organiser is not a stand, and putting them
-- in `communities` would leave the difference one UPDATE away: a stand that can
-- create stands. One table, one kind of caller, one login function each.

CREATE TABLE IF NOT EXISTS organizers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  -- Igual que en communities: el organizador es su propia identidad, así que
  -- auth_user_id es su propio id. El token lleva ese id como sub y
  -- calling_organizer() lo resuelve por acá.
  auth_user_id UUID UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Sin ninguna política, igual que settings y claim_codes: ningún cliente lo
-- lee. Lo consulta solo lo que corre como dueño.
ALTER TABLE organizers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "organizers_read" ON organizers;

-- Espejo de stand_login, contra la tabla propia. Que sean dos funciones
-- separadas es lo que impide que un stand se autentique como organizador o al
-- revés: cada una mira una sola tabla.
CREATE OR REPLACE FUNCTION organizer_login(p_username TEXT, p_password TEXT)
RETURNS TABLE (id UUID, username TEXT)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $fn$
  SELECT o.id, o.username
  FROM organizers o
  WHERE lower(o.username) = lower(btrim(p_username))
    AND o.password_hash = crypt(p_password, o.password_hash)
$fn$;

GRANT EXECUTE ON FUNCTION organizer_login(TEXT, TEXT) TO anon;

-- Se mantiene la invariante aunque una fila se cree sin ella.
CREATE OR REPLACE FUNCTION organizers_link_identity() RETURNS TRIGGER
LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.auth_user_id := COALESCE(NEW.auth_user_id, NEW.id);
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS organizers_identity ON organizers;
CREATE TRIGGER organizers_identity
  BEFORE INSERT ON organizers
  FOR EACH ROW EXECUTE FUNCTION organizers_link_identity();

-- La identidad nunca es un parámetro (constitución IV). Toda función del panel
-- resuelve al organizador por acá; el flag que lleva el token es decoración
-- para que el cliente sepa a qué pantalla ir, y no decide nada.
CREATE OR REPLACE FUNCTION calling_organizer() RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT id FROM organizers WHERE auth_user_id = auth.uid()
$fn$;

-- ---------------------------------------------------------------------------
-- El pulso del evento, en una sola lectura.
--
-- Son agregados sobre casi todas las tablas, los mira una sola persona seguido,
-- y no pueden armarse trayéndose todas las filas al navegador. El máximo
-- alcanzable se calcula, nunca se guarda: depende de las constantes del spec
-- 020 y de lo que las comunidades hayan publicado.
CREATE OR REPLACE FUNCTION event_overview()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_cfg JSONB := points_config();
  v_stands INT;
  v_max_reachable INT;
BEGIN
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  SELECT count(*) INTO v_stands FROM communities;

  -- Lo que gana quien recorre la feria una vez y participa en todo. No el
  -- máximo teórico -- que exige volver a escanear diez stands cada media hora
  -- durante seis horas -- sino lo que consigue alguien aplicado, que es la
  -- comparación que sirve para detectar un premio inalcanzable.
  SELECT v_stands * (v_cfg->>'visit')::int
       + COALESCE(SUM(CASE WHEN a.is_main_event
                           THEN (v_cfg->>'activity_main')::int
                           ELSE (v_cfg->>'activity_other')::int END), 0)
  INTO v_max_reachable
  FROM activities a;

  RETURN jsonb_build_object(
    'participants',      (SELECT count(*) FROM participants),
    'pointsAwarded',     (SELECT COALESCE(SUM(points), 0) FROM scans),
    'pointsSpent',       (SELECT COALESCE(SUM(r.cost), 0)
                          FROM claimed_rewards cr JOIN rewards r ON r.id = cr.reward_id),
    'rewardsHandedOver', (SELECT count(*) FROM claimed_rewards),
    'stockRemaining',    (SELECT COALESCE(SUM(stock), 0) FROM rewards WHERE NOT is_withdrawn),
    'rewardsPublished',  (SELECT count(*) FROM rewards WHERE NOT is_withdrawn),
    'mostExpensive',     (SELECT MAX(cost) FROM rewards WHERE NOT is_withdrawn),
    'maxReachable',      v_max_reachable,
    'stands',            v_stands,
    'runningActivities', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'activity', a.name, 'stand', c.name, 'isMainEvent', a.is_main_event
      ) ORDER BY c.name), '[]'::jsonb)
      FROM activities a JOIN communities c ON c.id = a.community_id
      WHERE activity_state(a) = 'running'
    )
  );
END;
$fn$;
