/* ============================================
   API Layer — Supabase CRUD & RPC helpers
   ============================================ */

import { supabase } from '../supabaseClient.js';

// ─── Participants ────────────────────────────

export async function registerParticipant(name, fingerprint) {
    const { data, error } = await supabase
        .from('participants')
        .insert({
            name,
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

export async function loginAdmin(username, password) {
    const { data, error } = await supabase
        .from('communities')
        .select('*')
        .eq('username', username)
        .eq('password', password)
        .single();

    if (error || !data) {
        console.error('Custom Login Error:', error);
        return { success: false, error: 'Credenciales incorrectas' };
    }
    
    // Create a mock user object representing the community
    const user = { id: data.id, email: username, communityId: data.id, role: 'community_admin' };
    
    // Store in localStorage directly as a patch since we bypassed real Auth
    localStorage.setItem('admin_session', JSON.stringify(user));
    
    return { success: true, user: user, session: { user } };
}

export async function logoutAdmin() {
    localStorage.removeItem('admin_session');
}

export async function getSession() {
    const stored = localStorage.getItem('admin_session');
    if (stored) return { user: JSON.parse(stored) };
    return null;
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
