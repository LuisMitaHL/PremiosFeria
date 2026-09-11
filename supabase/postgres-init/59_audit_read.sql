-- 59_audit_read.sql — leer el registro de actividad (spec 024).
--
-- Aparte de 45_audit.sql porque necesita calling_organizer(), que se crea en
-- 55. La separacion tambien dice algo cierto: escribir es parte de cada accion
-- del sistema, leer es una sola pantalla para una sola persona.
--
-- El registro no otorga nada. Es una superficie de lectura: ninguna accion del
-- sistema se dispara desde aca, y su existencia no debilita ninguna otra regla.

-- Paginado por clave, no por OFFSET: el organizador lee de lo mas nuevo hacia
-- atras mientras la feria sigue escribiendo, y un OFFSET sobre una tabla que
-- crece por arriba repite y saltea filas. El cursor es el id del ultimo
-- asiento entregado, que es monotono y no empata (R16, R17).
CREATE OR REPLACE FUNCTION audit_read(
  p_kind      TEXT        DEFAULT NULL,  -- 'scan', 'reward', 'participant'...
  p_actor_kind TEXT       DEFAULT NULL,
  p_actor_id  UUID        DEFAULT NULL,
  p_from      TIMESTAMPTZ DEFAULT NULL,
  p_to        TIMESTAMPTZ DEFAULT NULL,
  p_outcome   TEXT        DEFAULT NULL,
  p_cursor    BIGINT      DEFAULT NULL,
  p_limit     INT         DEFAULT 50
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_limit   INT;
  v_rows    JSONB;
  v_next    BIGINT;
BEGIN
  -- El registro contiene los movimientos de todos los asistentes y las
  -- operaciones de todos los stands. Un stand que llame a esta funcion
  -- directamente no recibe nada (R11).
  IF calling_organizer() IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;

  -- Acotado en el servidor: el tamano de pagina no es del cliente, o R17 deja
  -- de valer en cuanto alguien pide todo de una.
  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.id DESC), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT l.id, l.at, l.action, l.outcome, l.actor_kind, l.actor_id,
           l.subject_kind, l.subject_id, l.subject_label,
           l.before, l.detail, l.reason
    FROM audit_log l
    WHERE (p_kind       IS NULL OR split_part(l.action, '.', 1) = p_kind)
      AND (p_actor_kind IS NULL OR l.actor_kind = p_actor_kind)
      AND (p_actor_id   IS NULL OR l.actor_id   = p_actor_id)
      AND (p_outcome    IS NULL OR l.outcome    = p_outcome)
      AND (p_from       IS NULL OR l.at >= p_from)
      AND (p_to         IS NULL OR l.at <= p_to)
      AND (p_cursor     IS NULL OR l.id < p_cursor)
    ORDER BY l.id DESC
    LIMIT v_limit
  ) e;

  -- El cursor de la pagina siguiente sale de la ultima fila entregada. NULL
  -- significa que no hay mas, no que hubo un error.
  SELECT (v_rows -> (jsonb_array_length(v_rows) - 1) ->> 'id')::BIGINT
  INTO v_next
  WHERE jsonb_array_length(v_rows) = v_limit;

  RETURN jsonb_build_object('entries', v_rows, 'nextCursor', v_next);
END;
$fn$;

-- La pantalla ofrece la lista completa de ambitos, escrita en el cliente, en vez
-- de preguntarle a la base cuales tienen asientos: un filtro que va apareciendo
-- a medida que la feria genera cada tipo no se puede aprender. Por eso aca no
-- hay una funcion audit_kinds.
DROP FUNCTION IF EXISTS audit_kinds();
