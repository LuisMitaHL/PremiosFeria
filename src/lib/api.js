/* ============================================
   API Layer — Supabase CRUD & RPC helpers
   ============================================ */

import { supabase } from '../supabaseClient.js';

// ─── Participants ────────────────────────────

export async function registerParticipant(name, email, universityId, fingerprint) {
    const { data, error } = await supabase
        .from('participants')
        .insert({
            name,
            email: email || null,
            university_id: universityId || null,
            fingerprint: fingerprint || null,
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

export async function getMyCommunity(authUserId) {
    const { data, error } = await supabase
        .from('communities')
        .select('*')
        .eq('auth_user_id', authUserId)
        .single();

    if (error) return null;
    return data;
}

export async function updateCommunity(id, updates) {
    if (updates.visit_points !== undefined && updates.visit_points > 30) {
        throw new Error('El límite máximo de puntos por visita es 30.');
    }
    if (updates.activity_points !== undefined && updates.activity_points > 100) {
        throw new Error('El límite máximo de puntos por actividad es 100.');
    }

    const { data, error } = await supabase
        .from('communities')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    if (error) throw new Error(`Error al actualizar comunidad: ${error.message}`);
    return data;
}

// ─── Scans ───────────────────────────────────

export async function scanQR(participantId, encodedPayload) {
    const { data, error } = await supabase.rpc('validate_and_scan', {
        p_participant_id: participantId,
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

export async function claimReward(participantId, rewardId) {
    const { data, error } = await supabase.rpc('claim_reward', {
        p_participant_id: participantId,
        p_reward_id: rewardId,
    });

    if (error) throw new Error(`Error al canjear premio: ${error.message}`);
    return data; // { success, newPoints } or { success: false, reason }
}

// ─── Auth (Admin) ────────────────────────────

export async function loginAdmin(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
    });

    if (error) return { success: false, error: error.message };
    return { success: true, user: data.user, session: data.session };
}

export async function logoutAdmin() {
    const { error } = await supabase.auth.signOut();
    if (error) throw new Error(`Error al cerrar sesión: ${error.message}`);
}

export async function getSession() {
    const { data: { session } } = await supabase.auth.getSession();
    return session;
}

// ─── Settings ────────────────────────────────

export async function getHmacSecret() {
    const { data, error } = await supabase
        .from('settings')
        .select('value')
        .eq('key', 'hmac_secret')
        .single();

    if (error) throw new Error(`Error al obtener secreto: ${error.message}`);
    return data.value;
}

// ─── Realtime ────────────────────────────────

export function subscribeToLeaderboard(callback) {
    const channel = supabase
        .channel('leaderboard-changes')
        .on(
            'postgres_changes',
            { event: '*', schema: 'public', table: 'participants' },
            () => callback()
        )
        .subscribe();

    return () => supabase.removeChannel(channel);
}

export function subscribeToScans(callback) {
    const channel = supabase
        .channel('scans-changes')
        .on(
            'postgres_changes',
            { event: 'INSERT', schema: 'public', table: 'scans' },
            (payload) => callback(payload.new)
        )
        .subscribe();

    return () => supabase.removeChannel(channel);
}
