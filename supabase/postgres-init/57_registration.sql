-- 57_registration.sql — registering and coming back (spec 001).
--
-- The nickname is the only thing an attendee gives, and it is also their way
-- back: typing it again on the same device returns the profile they already
-- have. That is what makes a name-only registration survive an afternoon.
--
-- One function, three outcomes, one atomic step. Split across a lookup and an
-- insert, two people registering the same nickname at once would both see it
-- free.

CREATE OR REPLACE FUNCTION register_or_recover(p_name TEXT, p_fingerprint TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_name TEXT := btrim(COALESCE(p_name, ''));
  v_uid UUID := auth.uid();
  v_existing participants%ROWTYPE;
  v_row participants%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'No se pudo crear tu sesión. Intenta de nuevo.');
  END IF;

  IF char_length(v_name) < 2 THEN
    RETURN jsonb_build_object('error', 'El nombre debe tener al menos 2 caracteres');
  END IF;
  IF char_length(v_name) > 24 THEN
    RETURN jsonb_build_object('error', 'El nombre no puede tener más de 24 caracteres');
  END IF;

  -- ¿Ya existe ese nickname? Se bloquea la fila: dos intentos simultáneos sobre
  -- el mismo nombre se serializan acá, y el segundo ve lo que el primero dejó.
  SELECT * INTO v_existing FROM participants
  WHERE lower(btrim(name)) = lower(v_name)
  FOR UPDATE;

  IF FOUND THEN
    -- El dispositivo es el segundo factor que hace segura una identificación
    -- por nombre. Sin él, cualquiera escribe un nickname y se lleva el perfil.
    IF v_existing.fingerprint IS NOT NULL
       AND p_fingerprint IS NOT NULL
       AND v_existing.fingerprint = p_fingerprint THEN
      -- Vuelve a su perfil. Se re-vincula a esta sesión, que es el único lugar
      -- del sistema donde la identidad de una fila existente cambia.
      UPDATE participants SET auth_user_id = v_uid
      WHERE id = v_existing.id
      RETURNING * INTO v_row;

      RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint',
                                'recovered', true);
    END IF;

    -- Mismo nombre, otro dispositivo. No se puede distinguir a quien cambió de
    -- teléfono de quien quiere el perfil ajeno, así que se rechaza: el error
    -- caro es el otro. El spec 022 le da salida a quien de verdad lo perdió.
    RETURN jsonb_build_object('error', 'Ese nombre ya está en uso, elige otro.');
  END IF;

  BEGIN
    INSERT INTO participants (name, fingerprint, auth_user_id)
    VALUES (v_name, NULLIF(btrim(COALESCE(p_fingerprint, '')), ''), v_uid)
    RETURNING * INTO v_row;
  EXCEPTION
    WHEN unique_violation THEN
      -- El índice es la puerta real: otra sesión ganó la carrera entre el
      -- SELECT de arriba y este INSERT.
      RETURN jsonb_build_object('error', 'Ese nombre ya está en uso, elige otro.');
    WHEN check_violation THEN
      RETURN jsonb_build_object('error', 'El nombre debe tener entre 2 y 24 caracteres');
  END;

  RETURN jsonb_build_object('participant', to_jsonb(v_row) - 'fingerprint',
                            'recovered', false);
END;
$fn$;
