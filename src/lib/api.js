/* ============================================
   API Layer — Supabase CRUD & RPC helpers
   ============================================ */

import { supabase } from '../supabaseClient.js';

// ─── Participants ────────────────────────────

// Registro: crea una identidad anónima de Supabase Auth y vincula el
// participante a ella. El servidor ya nunca acepta un participant_id
// del cliente: los RPC resuelven al participante por auth.uid().
export async function registerParticipant(name, fingerprint) {
    // Cierra cualquier sesión anónima previa para no acumular usuarios huérfanos
    await supabase.auth.signOut();

    const { data: authData, error: authError } = await supabase.auth.signInAnonymously();
    if (authError || !authData?.user) {
        throw new Error('No se pudo crear tu sesión. Habilita "Anonymous sign-ins" en Supabase.');
    }

    const { data, error } = await supabase
        .from('participants')
        .insert({
            name,
            fingerprint: fingerprint || null,
            auth_user_id: authData.user.id,
        })
        .select('id')
        .single();

    if (error) throw new Error(`Error al registrar: ${error.message}`);
    return data.id;
}

export async function getParticipantById(id) {
    const { data, error } = await supabase
        .from('participants')
        .select('*')
        .eq('id', id)
        .single();

    if (error) return null;
    return data;
}

export async function getLeaderboard() {
    const { data, error } = await supabase
        .from('participants')
        .select('*')
        .order('points', { ascending: false });

    if (error) throw new Error(`Error al obtener leaderboard: ${error.message}`);
    return data;
}

// ─── Communities ─────────────────────────────

export async function getCommunities() {
    const { data, error } = await supabase
        .from('communities')
        .select('*');

    if (error) throw new Error(`Error al obtener comunidades: ${error.message}`);
    return data;
}

export async function getMyCommunity(communityId) {
    const { data, error } = await supabase
        .from('communities')
        .select('*')
        .eq('id', communityId)
        .single();

    if (error) return null;
    return data;
}

export async function updateCommunity(communityId, updates) {
    if (updates.visit_points !== undefined && updates.visit_points > 30) {
        throw new Error('El límite máximo de puntos por visita es 30.');
    }
    if (updates.activity_points !== undefined && updates.activity_points > 100) {
        throw new Error('El límite máximo de puntos por actividad es 100.');
    }

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

export async function claimReward(rewardId) {
    const { data, error } = await supabase.rpc('claim_reward', {
        p_reward_id: rewardId,
    });

    if (error) throw new Error(`Error al canjear premio: ${error.message}`);
    return data; // { success, newPoints } or { success: false, reason }
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
            .select('*')
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

export async function getSession() {
    const { data } = await supabase.auth.getSession();
    const uid = data?.session?.user?.id;
    if (!uid) return null;

    const meta = data.session.user.user_metadata;
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
        .select('*')
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

// ─── QR Signing (server-side) ────────────────

// Firma el código QR rotativo en el servidor (el secreto nunca sale de la BD).
export async function getSignedScanCode(communityId, type) {
    const { data, error } = await supabase.rpc('sign_scan_code', {
        p_community_id: communityId,
        p_type: type,
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
