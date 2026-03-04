/* ============================================
   Storage — Local session helpers (lightweight)
   ============================================
   This file now ONLY manages the current participant's
   session ID in localStorage. All data operations
   have moved to api.js (Supabase).
   ============================================ */

const PARTICIPANT_KEY = 'fp_current_participant_id';

/**
 * Save the current participant's UUID to localStorage.
 * Called after registration to persist the session locally.
 */
export function saveCurrentParticipantId(id) {
    localStorage.setItem(PARTICIPANT_KEY, id);
}

/**
 * Get the current participant's UUID from localStorage.
 * Returns null if not registered.
 */
export function getCurrentParticipantId() {
    return localStorage.getItem(PARTICIPANT_KEY) || null;
}

/**
 * Clear the current participant session.
 * Used for logout or resetting the device.
 */
export function clearCurrentParticipant() {
    localStorage.removeItem(PARTICIPANT_KEY);
}
