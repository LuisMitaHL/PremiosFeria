-- 61_statistics.sql — leer la feria entera cuando ya termino (spec 031).
--
-- Una sola funcion y una sola lectura. La seccion muestra el instante en que se
-- leyo y un filtro de tiempo que mueve todas las figuras a la vez; devolver todo
-- junto hace las dos cosas ciertas por construccion, y una sola sentencia le da
-- a cada sub-agregado la misma foto MVCC. Con un endpoint por grafico, dos
-- cifras leidas a destiempo podrian contradecirse.
--
-- Se calcula aca y no en el navegador (constitucion III): son agregados sobre
-- casi todas las tablas y no pueden armarse trayendose las filas. La escala de
-- referencia son unos 300 participantes y 10 stands, asi que la respuesta son
-- unas pocas decenas de puntos, no miles de filas.
--
-- La zona horaria es fija y va en el servidor: el reloj del portatil del
-- organizador y el de los telefonos no son el mismo, y agrupar por la zona de
-- quien mira daria dos respuestas distintas a la misma pregunta. Los buckets
-- vuelven como hora local en texto, para que el cliente no los reinterprete en
-- la zona del dispositivo.
--
-- Es una superficie de SOLO LECTURA: no llama a audit() y no cambia nada (R47).
-- El unico lector es el organizador: no lleva GRANT explicito, igual que
-- audit_read, porque el control es calling_organizer() por dentro
-- (constitucion IV).

-- Indices para agrupar por tiempo. La tabla del registro ya trae los suyos.
CREATE INDEX IF NOT EXISTS scans_created_at_idx         ON scans (created_at);
CREATE INDEX IF NOT EXISTS claimed_rewards_claimed_idx  ON claimed_rewards (claimed_at);
CREATE INDEX IF NOT EXISTS participants_registered_idx  ON participants (registered_at);

CREATE OR REPLACE FUNCTION event_statistics(
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to   TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_resultado JSONB;
BEGIN
  -- R2: un stand o un participante que llega directo no recibe nada. Esconder
  -- la pantalla no es el control; la decision esta donde se sirven las cifras.
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- Una sola sentencia. Todos los CTE comparten la misma foto de la base.
  --
  -- El filtro define el universo de participantes por registered_at: las
  -- cifras de saldo y de "quien tiene mas puntos" son estado actual, no
  -- historia, y no se puede reconstruir el saldo que alguien tenia en una
  -- ventana pasada. En el valor por defecto (todo el evento) el universo son
  -- todos. Con una ventana acotada, son quienes se registraron en ella.
  WITH
  scans_f AS (
    SELECT s.* FROM scans s
    WHERE (p_from IS NULL OR s.created_at >= p_from)
      AND (p_to   IS NULL OR s.created_at <= p_to)
  ),
  claims_f AS (
    SELECT cr.* FROM claimed_rewards cr
    WHERE (p_from IS NULL OR cr.claimed_at >= p_from)
      AND (p_to   IS NULL OR cr.claimed_at <= p_to)
  ),
  regs_f AS (
    SELECT p.* FROM participants p
    WHERE (p_from IS NULL OR p.registered_at >= p_from)
      AND (p_to   IS NULL OR p.registered_at <= p_to)
  ),
  adj_f AS (
    SELECT a.* FROM point_adjustments a
    WHERE (p_from IS NULL OR a.adjusted_at >= p_from)
      AND (p_to   IS NULL OR a.adjusted_at <= p_to)
  ),
  codes_f AS (
    SELECT c.* FROM claim_codes c
    WHERE (p_from IS NULL OR c.issued_at >= p_from)
      AND (p_to   IS NULL OR c.issued_at <= p_to)
  ),
  audit_f AS (
    SELECT a.* FROM audit_log a
    WHERE a.outcome = 'refused'
      AND (p_from IS NULL OR a.at >= p_from)
      AND (p_to   IS NULL OR a.at <= p_to)
  ),

  -- Instante de todo lo que ocurrio, para armar la grilla horaria.
  event_ts AS (
    SELECT created_at AS ts FROM scans_f
    UNION ALL SELECT registered_at FROM regs_f
    UNION ALL SELECT claimed_at FROM claims_f
  ),
  grid AS (
    SELECT generate_series(
      date_trunc('hour', min(ts AT TIME ZONE 'America/La_Paz')),
      date_trunc('hour', max(ts AT TIME ZONE 'America/La_Paz')),
      interval '1 hour') AS bucket
    FROM event_ts
  ),

  scan_hour AS (
    SELECT date_trunc('hour', s.created_at AT TIME ZONE 'America/La_Paz') AS bucket,
           count(*) FILTER (WHERE s.type = 'visit')    AS visits,
           count(*) FILTER (WHERE s.type = 'activity') AS activities,
           count(DISTINCT s.participant_id)            AS active_participants,
           COALESCE(sum(s.points), 0)                  AS points_awarded
    FROM scans_f s GROUP BY 1
  ),
  reg_hour AS (
    SELECT date_trunc('hour', r.registered_at AT TIME ZONE 'America/La_Paz') AS bucket,
           count(*) AS registrations
    FROM regs_f r GROUP BY 1
  ),
  spend_hour AS (
    SELECT date_trunc('hour', c.claimed_at AT TIME ZONE 'America/La_Paz') AS bucket,
           count(*) AS handovers,
           COALESCE(sum(rw.cost), 0) AS points_spent
    FROM claims_f c JOIN rewards rw ON rw.id = c.reward_id
    GROUP BY 1
  ),
  timeline AS (
    SELECT g.bucket,
           COALESCE(sh.visits, 0)              AS visits,
           COALESCE(sh.activities, 0)          AS activities,
           COALESCE(sh.active_participants, 0) AS active_participants,
           COALESCE(rh.registrations, 0)       AS registrations,
           COALESCE(sh.points_awarded, 0)      AS points_awarded,
           COALESCE(sph.points_spent, 0)       AS points_spent,
           sum(COALESCE(sh.points_awarded, 0)) OVER (ORDER BY g.bucket) AS cumulative_points
    FROM grid g
    LEFT JOIN scan_hour  sh  ON sh.bucket  = g.bucket
    LEFT JOIN reg_hour   rh  ON rh.bucket  = g.bucket
    LEFT JOIN spend_hour sph ON sph.bucket = g.bucket
  ),
  -- El primer y el ultimo ESCANEO, no cualquier evento: eso es la duracion
  -- efectiva de la feria (R22). La grilla horaria, en cambio, cubre todo lo que
  -- ocurrio, para que un registro o una entrega caigan en su hora.
  bounds AS (
    SELECT min(s.created_at) AS first_ts,
           max(s.created_at) AS last_ts,
           CASE WHEN min(s.created_at) IS NULL THEN 0
                ELSE (EXTRACT(EPOCH FROM (max(s.created_at) - min(s.created_at))) / 60)::int END AS duration_min
    FROM scans_f s
  ),

  -- Puntos por stand, partidos por tipo. Una actividad y una visita valen
  -- distinto (spec 020) y promediarlas juntas esconde cual rinde.
  scan_stand AS (
    SELECT s.community_id,
           count(*) FILTER (WHERE s.type = 'visit')    AS visits,
           count(*) FILTER (WHERE s.type = 'activity') AS activities,
           COALESCE(sum(s.points) FILTER (WHERE s.type = 'visit'), 0)    AS visit_points,
           COALESCE(sum(s.points) FILTER (WHERE s.type = 'activity'), 0) AS activity_points,
           count(*) AS total_scans
    FROM scans_f s GROUP BY 1
  ),
  stands_full AS (
    SELECT c.id,
           c.name,
           c.stand_number,
           c.is_withdrawn,
           COALESCE(ss.visits, 0)          AS visits,
           COALESCE(ss.activities, 0)      AS activities,
           COALESCE(ss.visit_points, 0)    AS visit_points,
           COALESCE(ss.activity_points, 0) AS activity_points,
           COALESCE(ss.visit_points, 0) + COALESCE(ss.activity_points, 0) AS total_points,
           COALESCE(ss.total_scans, 0)     AS total_scans,
           CASE WHEN COALESCE(ss.total_scans, 0) = 0 THEN 0
                ELSE round(((COALESCE(ss.visit_points, 0) + COALESCE(ss.activity_points, 0))::numeric
                            / ss.total_scans), 1) END AS avg_points
    FROM communities c
    LEFT JOIN scan_stand ss ON ss.community_id = c.id
  ),

  -- Los ajustes manuales no son puntos que otorgo un stand: van aparte y nunca
  -- se suman a la columna del stand (R25).
  adj_totals AS (
    SELECT COALESCE(sum(a.amount), 0) AS total, count(*) AS cnt FROM adj_f a
  ),
  adj_reasons AS (
    SELECT a.reason, sum(a.amount) AS amount, count(*) AS cnt
    FROM adj_f a GROUP BY a.reason
  ),

  -- Un premio reclamado no guarda lo que costo cuando se entrego, asi que el
  -- gasto por premio usa el costo actual, igual que event_overview (spec 021).
  handover_reward AS (
    SELECT c.reward_id, count(*) AS handed
    FROM claims_f c GROUP BY c.reward_id
  ),
  rewards_full AS (
    SELECT rw.id,
           rw.name,
           c.name AS stand,
           rw.cost,
           rw.is_withdrawn,
           COALESCE(hr.handed, 0)             AS handed_over,
           COALESCE(hr.handed, 0) * rw.cost   AS points_spent,
           rw.stock                           AS remaining
    FROM rewards rw
    JOIN communities c ON c.id = rw.community_id
    LEFT JOIN handover_reward hr ON hr.reward_id = rw.id
  ),

  -- Quien visita un stand es quien lo escanea como visita, igual que en el
  -- inicio del participante (spec 013): una actividad tambien lo lleva, pero
  -- "stands visitados" ya significa eso en el resto del sistema.
  stand_visits AS (
    SELECT s.participant_id, count(DISTINCT s.community_id) AS stands_visited
    FROM scans_f s WHERE s.type = 'visit'
    GROUP BY s.participant_id
  ),
  participant_visits AS (
    SELECT r.id, COALESCE(sv.stands_visited, 0) AS n
    FROM regs_f r LEFT JOIN stand_visits sv ON sv.participant_id = r.id
  ),
  no_scan AS (
    SELECT count(*) AS cnt
    FROM regs_f r
    WHERE NOT EXISTS (SELECT 1 FROM scans_f s WHERE s.participant_id = r.id)
  ),
  band_counts AS (
    SELECT LEAST(floor(r.points / 50.0)::int, 6) AS b, count(*) AS cnt
    FROM regs_f r GROUP BY 1
  ),
  bands_full AS (
    SELECT g.n AS band_order,
           CASE g.n WHEN 0 THEN '0'
                    WHEN 6 THEN '300+'
                    ELSE (g.n * 50)::text || '-' || (g.n * 50 + 49)::text END AS label,
           COALESCE(bc.cnt, 0) AS cnt
    FROM generate_series(0, 6) g(n)
    LEFT JOIN band_counts bc ON bc.b = g.n
  ),
  visited_dist AS (
    SELECT g.n AS stands_visited, count(pv.id) AS cnt
    FROM generate_series(0, (SELECT count(*)::int FROM communities)) g(n)
    LEFT JOIN participant_visits pv ON pv.n = g.n
    GROUP BY g.n
  ),
  top_participants AS (
    SELECT r.name, r.points, r.is_removed, r.claims_barred
    FROM regs_f r
    ORDER BY r.points DESC, r.name ASC
    LIMIT 10
  ),

  refusals AS (
    SELECT a.action,
           COALESCE(NULLIF(btrim(a.reason), ''), '(sin motivo)') AS reason,
           count(*) AS cnt
    FROM audit_f a
    GROUP BY 1, 2
  ),
  -- "Vencido" no es un estado guardado: es un codigo que quedo abierto y ya no
  -- esta vivo (nadie volvio a preguntar por el). Se deriva, como su vigencia.
  code_counts AS (
    SELECT count(*) AS issued,
           count(*) FILTER (WHERE c.closed_reason = 'used')     AS used,
           count(*) FILTER (WHERE c.closed_reason = 'replaced')  AS replaced,
           count(*) FILTER (WHERE c.closed_at IS NULL AND NOT claim_code_is_live(c)) AS expired
    FROM codes_f c
  )

  SELECT jsonb_build_object(
    'generatedAt', now(),
    'from', p_from,
    'to',   p_to,
    'timezone', 'America/La_Paz',

    'callouts', jsonb_build_object(
      'busiestHour', (
        SELECT jsonb_build_object('bucket', to_char(t.bucket, 'YYYY-MM-DD"T"HH24:00'),
                                  'scans',  t.visits + t.activities)
        FROM timeline t
        WHERE t.visits + t.activities > 0
        ORDER BY t.visits + t.activities DESC, t.bucket ASC
        LIMIT 1
      ),
      'topStandByPoints', (
        SELECT jsonb_build_object('stand', s.name, 'points', s.total_points)
        FROM stands_full s
        WHERE s.total_points > 0
        ORDER BY s.total_points DESC, s.name ASC
        LIMIT 1
      ),
      'mostHandedOverReward', (
        SELECT jsonb_build_object('reward', r.name, 'count', r.handed_over)
        FROM rewards_full r
        WHERE r.handed_over > 0
        ORDER BY r.handed_over DESC, r.name ASC
        LIMIT 1
      ),
      'registeredWithoutScan', (SELECT cnt FROM no_scan),
      'standsWithoutScans', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('stand', s.name, 'standNumber', s.stand_number)
                         ORDER BY s.name)
        FROM stands_full s WHERE s.total_scans = 0
      ), '[]'::jsonb)
    ),

    'attendance', jsonb_build_object(
      'timeline', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'bucket',              to_char(t.bucket, 'YYYY-MM-DD"T"HH24:00'),
                 'visits',              t.visits,
                 'activities',          t.activities,
                 'activeParticipants',  t.active_participants,
                 'registrations',       t.registrations,
                 'pointsAwarded',       t.points_awarded,
                 'pointsSpent',         t.points_spent,
                 'cumulativePointsAwarded', t.cumulative_points
               ) ORDER BY t.bucket)
        FROM timeline t
      ), '[]'::jsonb),
      'bounds', (
        SELECT jsonb_build_object('firstScan', b.first_ts, 'lastScan', b.last_ts,
                                  'durationMinutes', b.duration_min)
        FROM bounds b
      )
    ),

    'stands', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',            s.id,
               'name',          s.name,
               'standNumber',   s.stand_number,
               'withdrawn',     s.is_withdrawn,
               'visits',        s.visits,
               'activities',    s.activities,
               'visitPoints',   s.visit_points,
               'activityPoints', s.activity_points,
               'totalPoints',   s.total_points,
               'totalScans',    s.total_scans,
               'avgPoints',     s.avg_points
             ) ORDER BY s.total_points DESC, s.name ASC)
      FROM stands_full s
    ), '[]'::jsonb),

    'adjustments', jsonb_build_object(
      'total', (SELECT t.total FROM adj_totals t),
      'count', (SELECT t.cnt FROM adj_totals t),
      'byReason', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('reason', a.reason, 'amount', a.amount, 'count', a.cnt)
                         ORDER BY a.amount DESC, a.reason ASC)
        FROM adj_reasons a
      ), '[]'::jsonb)
    ),

    'rewards', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id',          r.id,
               'name',        r.name,
               'stand',       r.stand,
               'cost',        r.cost,
               'withdrawn',   r.is_withdrawn,
               'handedOver',  r.handed_over,
               'pointsSpent', r.points_spent,
               'remaining',   r.remaining
             ) ORDER BY r.handed_over DESC, r.name ASC)
      FROM rewards_full r
    ), '[]'::jsonb),

    'handoversPerHour', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('bucket', to_char(sp.bucket, 'YYYY-MM-DD"T"HH24:00'),
                                          'count', sp.handovers)
                       ORDER BY sp.bucket)
      FROM spend_hour sp
    ), '[]'::jsonb),

    'participants', jsonb_build_object(
      'balanceBands', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('band', b.label, 'count', b.cnt)
                         ORDER BY b.band_order)
        FROM bands_full b
      ), '[]'::jsonb),
      'standsVisited', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('standsVisited', v.stands_visited, 'count', v.cnt)
                         ORDER BY v.stands_visited)
        FROM visited_dist v
      ), '[]'::jsonb),
      'registeredWithoutScan', (SELECT cnt FROM no_scan),
      'top', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name', t.name, 'points', t.points,
                                            'removed', t.is_removed, 'barred', t.claims_barred)
                         ORDER BY t.points DESC, t.name ASC)
        FROM top_participants t
      ), '[]'::jsonb)
    ),

    'operations', jsonb_build_object(
      'refusals', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('action', r.action, 'reason', r.reason, 'count', r.cnt)
                         ORDER BY r.cnt DESC, r.action ASC, r.reason ASC)
        FROM refusals r
      ), '[]'::jsonb),
      'claimCodes', (
        SELECT jsonb_build_object('issued', c.issued, 'used', c.used,
                                  'replaced', c.replaced, 'expired', c.expired)
        FROM code_counts c
      )
    )
  ) INTO v_resultado;

  RETURN v_resultado;
END;
$fn$;
