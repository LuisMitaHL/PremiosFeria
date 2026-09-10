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
BEGIN
  IF v_community IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_emoji IS NULL OR btrim(p_emoji) = '' THEN
    RETURN jsonb_build_object('error', 'Elige un ícono para el premio.');
  END IF;

  BEGIN
    INSERT INTO rewards (community_id, name, description, cost, stock, emoji)
    VALUES (v_community, btrim(p_name), NULLIF(btrim(COALESCE(p_description, '')), ''),
            p_cost, p_stock, btrim(p_emoji))
    RETURNING * INTO v_row;
  EXCEPTION WHEN check_violation THEN
    RETURN jsonb_build_object('error', CASE
      WHEN SQLERRM LIKE '%cost%'        THEN 'El costo no puede superar los 300 puntos.'
      WHEN SQLERRM LIKE '%name%'        THEN 'El nombre debe tener entre 3 y 40 caracteres.'
      WHEN SQLERRM LIKE '%description%' THEN 'La descripción no puede superar los 100 caracteres.'
      WHEN SQLERRM LIKE '%stock%'       THEN 'El stock no puede ser negativo.'
      ELSE 'Datos inválidos.'
    END);
  END;

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
BEGIN
  IF v_community IS NULL THEN
    RETURN jsonb_build_object('error', 'No autorizado');
  END IF;
  IF p_by IS NULL OR p_by <= 0 THEN
    RETURN jsonb_build_object('error', 'Solo puedes agregar unidades. Para reducir el stock, pide al organizador.');
  END IF;

  UPDATE rewards SET stock = stock + p_by
  WHERE id = p_reward_id AND community_id = v_community
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Premio no encontrado o no es de tu stand.');
  END IF;

  RETURN jsonb_build_object('reward', to_jsonb(v_row));
END;
$fn$;
