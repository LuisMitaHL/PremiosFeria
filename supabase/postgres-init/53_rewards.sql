-- 53_rewards.sql — a stand registers and restocks its own prizes (spec 021).
--
-- There is deliberately no `update_reward`. The cost is fixed when the reward
-- is created and belongs to the organiser afterwards (spec 023), and a stand
-- may only ever increase stock. Naming each function after the one thing it may
-- do is what makes the direction a rule rather than a convention: a general
-- "update" would let a stand raise a price attendees are saving towards, or
-- quietly take away units they can already see.

CREATE OR REPLACE FUNCTION create_reward(
  p_name TEXT,
  p_cost INT,
  p_stock INT,
  p_emoji TEXT,
  p_description TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row rewards%ROWTYPE;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    -- Se rechaza porque no hay stand que resolver, así que el asiento queda a
    -- nombre de quien haya llamado, sea quien sea (spec 024, R8).
    PERFORM audit(p_action => 'reward.create', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'reward', p_subject_label => btrim(p_name),
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_emoji IS NULL OR btrim(p_emoji) = '' THEN
    v_error := 'Elige un ícono para el premio.';
    PERFORM audit(p_action => 'reward.create', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'reward', p_subject_label => btrim(p_name),
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  BEGIN
    INSERT INTO rewards (community_id, name, description, cost, stock, emoji)
    VALUES (v_community, btrim(p_name), NULLIF(btrim(COALESCE(p_description, '')), ''),
            p_cost, p_stock, btrim(p_emoji))
    RETURNING * INTO v_row;
  -- El asiento va en el manejador y no dentro del bloque protegido: si no se
  -- puede escribir, la excepción sale de la función y la acción falla (R21).
  EXCEPTION WHEN check_violation THEN
    v_error := CASE
      WHEN SQLERRM LIKE '%cost%'        THEN 'El costo no puede superar los 300 puntos.'
      WHEN SQLERRM LIKE '%name%'        THEN 'El nombre debe tener entre 3 y 40 caracteres.'
      WHEN SQLERRM LIKE '%description%' THEN 'La descripción no puede superar los 100 caracteres.'
      WHEN SQLERRM LIKE '%stock%'       THEN 'El stock no puede ser negativo.'
      ELSE 'Datos inválidos.'
    END;
    PERFORM audit(p_action => 'reward.create', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'reward', p_subject_label => btrim(p_name),
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END;

  PERFORM audit(p_action => 'reward.create', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'reward', p_subject_id => v_row.id,
                p_subject_label => v_row.name);

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;

-- Only upwards. More boxes arrive; nothing about what a prize costs anyone
-- changes. Reducing stock takes away something attendees can already see and
-- may be walking towards, so it belongs to the organiser (spec 023).
CREATE OR REPLACE FUNCTION increase_reward_stock(p_reward_id UUID, p_by INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_community UUID := calling_community();
  v_row rewards%ROWTYPE;
  v_error TEXT;
BEGIN
  IF v_community IS NULL THEN
    PERFORM audit(p_action => 'reward.restock', p_outcome => 'refused',
                  p_actor_kind => audit_actor(), p_actor_id => audit_actor_id(),
                  p_subject_kind => 'reward', p_subject_id => p_reward_id,
                  p_reason => 'No autorizado');
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_by IS NULL OR p_by <= 0 THEN
    v_error := 'Solo puedes agregar unidades. Para reducir el stock, pide al organizador.';
    PERFORM audit(p_action => 'reward.restock', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'reward', p_subject_id => p_reward_id,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  UPDATE rewards SET stock = stock + p_by
  WHERE id = p_reward_id AND community_id = v_community
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    v_error := 'Premio no encontrado o no es de tu stand.';
    PERFORM audit(p_action => 'reward.restock', p_outcome => 'refused',
                  p_actor_kind => 'stand', p_actor_id => v_community,
                  p_subject_kind => 'reward', p_subject_id => p_reward_id,
                  p_reason => v_error);
    RETURN jsonb_build_object('error', v_error);
  END IF;

  -- La escritura condicional devuelve la fila ya repuesta, así que el stock
  -- anterior se deriva restando: leerlo antes obligaría a una segunda consulta
  -- y a decidir si bloquear la fila, que es justo lo que este UPDATE evita.
  PERFORM audit(p_action => 'reward.restock', p_outcome => 'ok',
                p_actor_kind => 'stand', p_actor_id => v_community,
                p_subject_kind => 'reward', p_subject_id => v_row.id,
                p_subject_label => v_row.name,
                p_before => jsonb_build_object('stock', v_row.stock - p_by));

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;
