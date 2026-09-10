/* ============================================
   API Layer — Supabase CRUD & RPC helpers
   ============================================ */

import { supabase } from '../supabaseClient.js';

// The columns a client is allowed to read. 31_column_grants.sql revokes the
// rest at the database, so asking for '*' here is not merely untidy: it fails.
// Kept in one place so the two cannot drift apart.
export const PARTICIPANT_COLUMNS = 'id, name, points, registered_at';
export const COMMUNITY_COLUMNS =
    'id, username, name, emoji, stand_number, description, is_withdrawn, auth_user_id, created_at';

// Activities carry a derived state -- activity_state() in the database, exposed
// by PostgREST as a computed column. The screens must read that rather than
// working it out from started_at and a duration: a phone with a wrong clock
// would otherwise show a finished activity as open and send someone across the
// hall for nothing (spec 025, R11).
export const ACTIVITY_COLUMNS =
    'id, community_id, name, description, estimated_start, duration_min, is_main_event, started_at, finished_at, activity_state';

// ─── Participants ────────────────────────────

// Registro: crea una identidad anónima de Supabase Auth y vincula el
// participante a ella. El servidor ya nunca acepta un participant_id
// del cliente: los RPC resuelven al participante por auth.uid().
// Registrarse y volver son la misma acción, decidida en la base en un solo
// paso (spec 001): el nickname libre crea un perfil, el nickname propio en el
// mismo dispositivo lo devuelve, y el nickname ajeno se rechaza. Partido entre
// una consulta y una inserción, dos personas eligiendo el mismo nombre a la vez
// lo verían libre las dos.
export async function registerParticipant(name, fingerprint) {
    // Cierra cualquier sesión anónima previa para no acumular usuarios huérfanos
    await supabase.auth.signOut();

    const { data: authData, error: authError } = await supabase.auth.signInAnonymously();
    if (authError || !authData?.user) {
        throw new Error('No se pudo crear tu sesión. Intenta de nuevo.');
    }

    const { data, error } = await supabase.rpc('register_or_recover', {
        p_name: name,
        p_fingerprint: fingerprint || null,
    });

    if (error) throw new Error(`Error al registrar: ${error.message}`);
    if (data?.error) {
        // La sesión anónima recién creada no sirve para nada si el registro se
        // rechazó; dejarla abierta acumula identidades huérfanas.
        await supabase.auth.signOut();
        const refusal = new Error(data.error);
        refusal.refused = true;
        throw refusal;
    }
    return { id: data.participant.id, recovered: data.recovered };
}

export async function getParticipantById(id) {
    const { data, error } = await supabase
        .from('participants')
        .select(PARTICIPANT_COLUMNS)
        .eq('id', id)
        .single();

    if (error) return null;
    return data;
}

export async function getLeaderboard() {
    const { data, error } = await supabase
        .from('participants')
        .select('id, name, points')
        .order('points', { ascending: false });

    if (error) throw new Error(`Error al obtener leaderboard: ${error.message}`);
    return data;
}

// ─── Communities ─────────────────────────────

export async function getCommunities() {
    const { data, error } = await supabase
        .from('communities')
        .select(COMMUNITY_COLUMNS);

    if (error) throw new Error(`Error al obtener comunidades: ${error.message}`);
    return data;
}

export async function getMyCommunity(communityId) {
    const { data, error } = await supabase
        .from('communities')
        .select(COMMUNITY_COLUMNS)
        .eq('id', communityId)
        .single();

    if (error) return null;
    return data;
}

export async function updateCommunity(communityId, updates) {
    const { data, error } = await supabase
        .from('communities')
        .update(updates)
        .eq('id', communityId)
        .select()
        .single();

    if (error) throw new Error(`Error al actualizar comunidad: ${error.message}`);
    return data;
}

// ─── Scans ───────────────────────────────────

export async function scanQR(encodedPayload) {
    const { data, error } = await supabase.rpc('validate_and_scan', {
        p_encoded_payload: encodedPayload,
    });

    if (error) throw new Error(`Error al validar QR: ${error.message}`);
    return data; // { valid, points, type, groupName, groupEmoji } or { valid: false, reason }
}

export async function getScansForParticipant(participantId) {
    const { data, error } = await supabase
        .from('scans')
        .select('*, communities(name, emoji)')
        .eq('participant_id', participantId)
        .order('created_at', { ascending: false });

    if (error) throw new Error(`Error al obtener escaneos: ${error.message}`);
    return data;
}

export async function getAllScans() {
    const { data, error } = await supabase
        .from('scans')
        .select('*')
        .order('created_at', { ascending: false });

    if (error) throw new Error(`Error al obtener escaneos: ${error.message}`);
    return data;
}

export async function getScansByCommunity(communityId) {
    const { data, error } = await supabase
        .from('scans')
        .select('*, participants(name)')
        .eq('community_id', communityId)
        .order('created_at', { ascending: false });

    if (error) throw new Error(`Error al obtener escaneos: ${error.message}`);
    return data;
}

// ─── Rewards ─────────────────────────────────

export async function getRewards() {
    const { data, error } = await supabase
        .from('rewards')
        .select('*, communities(name)');

    if (error) throw new Error(`Error al obtener premios: ${error.message}`);
    return data;
}

export async function getClaimedRewards(participantId) {
    const { data, error } = await supabase
        .from('claimed_rewards')
        .select('reward_id')
        .eq('participant_id', participantId);

    if (error) throw new Error(`Error al obtener premios canjeados: ${error.message}`);
    return data.map(r => r.reward_id);
}

// El canje lo confirma el stand al entregar el premio (spec 018). El estudiante
// pide un código, lo muestra, y su pantalla pregunta hasta que se confirme.
export async function issueClaimCode() {
    const { data, error } = await supabase.rpc('issue_claim_code');
    if (error) throw new Error(`Error al generar el código: ${error.message}`);
    return data;
}

// Pregunta por el código propio, resuelto desde la sesión: nunca se envía un
// identificador. Cada consulta renueva la tolerancia que lo mantiene vivo.
export async function pollMyClaimCode() {
    const { data, error } = await supabase.rpc('poll_my_claim_code');
    if (error) throw new Error(`Error al consultar el código: ${error.message}`);
    return data;
}

export async function confirmHandover(code, rewardId) {
    const { data, error } = await supabase.rpc('confirm_handover', {
        p_code: code,
        p_reward_id: rewardId,
    });
    if (error) throw new Error(`Error al confirmar la entrega: ${error.message}`);
    return data;
}

// ─── Auth (Admin) ────────────────────────────

export async function loginAdmin(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });

    if (error || !data?.user) {
        return { success: false, error: 'Credenciales incorrectas' };
    }

    // The auth session carries the linked community in user_metadata (set by
    // Supabase Auth in prod and by the dev auth mock). Fall back to resolving
    // via communities.auth_user_id for sessions without that metadata.
    let comm = data.user.user_metadata?.community_id
        ? { id: data.user.user_metadata.community_id }
        : null;

    if (!comm) {
        const { data: row, error: commErr } = await supabase
            .from('communities')
            .select(COMMUNITY_COLUMNS)
            .eq('auth_user_id', data.user.id)
            .single();
        if (commErr || !row) {
            await supabase.auth.signOut();
            return { success: false, error: 'No hay comunidad vinculada a esta cuenta' };
        }
        comm = row;
    }

    const user = { id: comm.id, authId: data.user.id, email, communityId: comm.id, role: 'community_admin' };
    return { success: true, user, session: { user } };
}

export async function logoutAdmin() {
    await supabase.auth.signOut();
}

// El organizador entra por el mismo servicio de autenticación con su propia
// función contra su propia tabla (spec 017). El flag del token solo dice a qué
// pantalla ir; toda autoridad se resuelve en la base por auth.uid().
export async function loginOrganizer(username, password) {
    await supabase.auth.signOut();
    const { data, error } = await supabase.auth.signInWithPassword({
        email: username,
        password,
    });
    if (error || !data?.user) {
        return { success: false, error: 'Credenciales incorrectas' };
    }
    if (!data.user.user_metadata?.organizer) {
        // Credenciales válidas, pero de un stand. El panel no es suyo.
        await supabase.auth.signOut();
        return { success: false, error: 'Credenciales incorrectas' };
    }
    return {
        success: true,
        user: { id: data.user.id, username: data.user.user_metadata.username, organizer: true },
    };
}

// ─── Organizer: communities (spec 023) ───────

export async function organizerCreateCommunity(fields) {
    const { data, error } = await supabase.rpc('create_community', {
        p_name: fields.name,
        p_username: fields.username,
        p_stand_number: fields.stand_number,
        p_emoji: fields.emoji,
        p_description: fields.description || null,
    });
    if (error) throw new Error(`Error al crear la comunidad: ${error.message}`);
    return data;
}

export async function organizerUpdateCommunity(id, fields) {
    const { data, error } = await supabase.rpc('update_community_profile', {
        p_id: id,
        p_name: fields.name,
        p_stand_number: fields.stand_number,
        p_emoji: fields.emoji,
        p_description: fields.description || null,
    });
    if (error) throw new Error(`Error al actualizar la comunidad: ${error.message}`);
    return data;
}

// Devuelve la contraseña UNA sola vez. Después solo queda el hash.
export async function organizerResetPassword(id) {
    const { data, error } = await supabase.rpc('reset_community_password', { p_id: id });
    if (error) throw new Error(`Error al restablecer la contraseña: ${error.message}`);
    return data;
}

export async function organizerSetCommunityWithdrawn(id, withdrawn) {
    const { data, error } = await supabase.rpc('set_community_withdrawn', {
        p_id: id,
        p_withdrawn: withdrawn,
    });
    if (error) throw new Error(`Error al cambiar el estado: ${error.message}`);
    return data;
}

export async function organizerSetRewardCost(rewardId, cost) {
    const { data, error } = await supabase.rpc('set_reward_cost', {
        p_reward_id: rewardId,
        p_cost: Number(cost),
    });
    if (error) throw new Error(`Error al cambiar el costo: ${error.message}`);
    return data;
}

export async function organizerSetRewardStock(rewardId, stock) {
    const { data, error } = await supabase.rpc('set_reward_stock', {
        p_reward_id: rewardId,
        p_stock: Number(stock),
    });
    if (error) throw new Error(`Error al cambiar el stock: ${error.message}`);
    return data;
}

export async function organizerSetRewardWithdrawn(rewardId, withdrawn) {
    const { data, error } = await supabase.rpc('set_reward_withdrawn', {
        p_reward_id: rewardId,
        p_withdrawn: withdrawn,
    });
    if (error) throw new Error(`Error al cambiar el estado del premio: ${error.message}`);
    return data;
}

export async function getEventOverview() {
    const { data, error } = await supabase.rpc('event_overview');
    if (error) throw new Error(`Error al obtener el resumen: ${error.message}`);
    return data;
}

export async function getSession() {
    const { data } = await supabase.auth.getSession();
    const uid = data?.session?.user?.id;
    if (!uid) return null;

    const meta = data.session.user.user_metadata;
    if (meta?.organizer) {
        return { user: { id: uid, username: meta.username, organizer: true } };
    }
    if (meta?.community_id) {
        return {
            user: {
                id: meta.community_id,
                authId: uid,
                email: data.session.user.email,
                communityId: meta.community_id,
                role: 'community_admin',
            },
        };
    }

    const { data: comm } = await supabase
        .from('communities')
        .select(COMMUNITY_COLUMNS)
        .eq('auth_user_id', uid)
        .single();

    if (!comm) return null;
    return {
        user: {
            id: comm.id,
            authId: uid,
            email: data.session.user.email,
            communityId: comm.id,
            role: 'community_admin',
        },
    };
}

// ─── Activities ──────────────────────────────

export async function getActivitiesForCommunity(communityId) {
    const { data, error } = await supabase
        .from('activities')
        .select(ACTIVITY_COLUMNS)
        .eq('community_id', communityId)
        .order('created_at', { ascending: true });

    if (error) throw new Error(`Error al obtener actividades: ${error.message}`);
    return data;
}

export async function getAllActivities() {
    const { data, error } = await supabase
        .from('activities')
        // is_withdrawn viaja con el stand porque la pantalla del estudiante
        // tiene que mostrar sus actividades como no disponibles en vez de
        // esconderlas (spec 025, R10).
        .select(`${ACTIVITY_COLUMNS}, communities(name, emoji, stand_number, is_withdrawn)`)
        .order('estimated_start', { ascending: true });

    if (error) throw new Error(`Error al obtener actividades: ${error.message}`);
    return data;
}

// These four return { activity } or { error: 'reason' }. The reason is written
// for the stand admin to act on, so it is shown as-is.
export async function createActivity(fields) {
    const { data, error } = await supabase.rpc('create_activity', {
        p_name: fields.name,
        p_description: fields.description,
        p_estimated_start: fields.estimated_start,
        p_duration_min: fields.duration_min,
        p_is_main_event: fields.is_main_event,
    });
    if (error) throw new Error(`Error al crear actividad: ${error.message}`);
    return data;
}

export async function updateActivity(id, fields) {
    const { data, error } = await supabase.rpc('update_activity', {
        p_id: id,
        p_name: fields.name,
        p_description: fields.description,
        p_estimated_start: fields.estimated_start,
        p_duration_min: fields.duration_min,
        p_is_main_event: fields.is_main_event,
    });
    if (error) throw new Error(`Error al actualizar actividad: ${error.message}`);
    return data;
}

export async function startActivity(id) {
    const { data, error } = await supabase.rpc('start_activity', { p_id: id });
    if (error) throw new Error(`Error al iniciar actividad: ${error.message}`);
    return data;
}

export async function finishActivity(id) {
    const { data, error } = await supabase.rpc('finish_activity', { p_id: id });
    if (error) throw new Error(`Error al terminar actividad: ${error.message}`);
    return data;
}

export async function getRewardsForCommunity(communityId) {
    const { data, error } = await supabase
        .from('rewards')
        .select('*')
        .eq('community_id', communityId)
        .order('cost', { ascending: true });

    if (error) throw new Error(`Error al obtener premios: ${error.message}`);
    return data;
}

// A stand registers its own prizes and may only ever add stock. Reducing it,
// and changing a cost, belong to the organiser (spec 021), which is why there
// is no updateReward here to reach for.
export async function createReward(fields) {
    const { data, error } = await supabase.rpc('create_reward', {
        p_name: fields.name,
        p_cost: Number(fields.cost),
        p_stock: Number(fields.stock),
        p_emoji: fields.emoji,
        p_description: fields.description || null,
    });
    if (error) throw new Error(`Error al crear premio: ${error.message}`);
    return data;
}

export async function increaseRewardStock(rewardId, by) {
    const { data, error } = await supabase.rpc('increase_reward_stock', {
        p_reward_id: rewardId,
        p_by: Number(by),
    });
    if (error) throw new Error(`Error al agregar stock: ${error.message}`);
    return data;
}

// ─── QR Signing (server-side) ────────────────

// Firma el código QR rotativo en el servidor (el secreto nunca sale de la BD).
export async function getSignedScanCode(communityId, type, activityId = null) {
    const { data, error } = await supabase.rpc('sign_scan_code', {
        p_community_id: communityId,
        p_type: type,
        p_activity_id: activityId,
    });

    if (error) throw new Error(`Error al firmar código: ${error.message}`);
    return data; // { payload, shortCode, ts } or { error }
}

// ─── Polling ─────────────────────────────────
// Ephemeral fair backend has no realtime service: callers poll instead.
// Same cleanup contract as the old channel subscriptions (call the
// returned function on unmount). Refetches on interval + on tab focus.
export function startLeaderboardPolling(callback, ms = 5000) {
    const timer = setInterval(callback, ms);
    const onFocus = () => callback();
    window.addEventListener('focus', onFocus);
    document.addEventListener('visibilitychange', onFocus);
    return () => {
        clearInterval(timer);
        window.removeEventListener('focus', onFocus);
        document.removeEventListener('visibilitychange', onFocus);
    };
}
