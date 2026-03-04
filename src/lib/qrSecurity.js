/* ============================================
   QR Security — TOTP-like rotating codes
   ============================================
   - generateQRPayload: runs CLIENT-SIDE on admin pages
     (secret fetched from Supabase settings table)
   - Validation: runs SERVER-SIDE via RPC
     (validate_and_scan PostgreSQL function)
   ============================================ */

const TIME_STEP = 30; // seconds — QR rotates every 30s

// --- HMAC-like token generation ---
function simpleHMAC(secret, message) {
    const combined = secret + '|' + message;
    let hash = 0;
    for (let i = 0; i < combined.length; i++) {
        const char = combined.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return Math.abs(hash).toString(16).padStart(8, '0');
}

// Get current time step
function getTimeStep() {
    return Math.floor(Date.now() / 1000 / TIME_STEP);
}

// --- Generate QR Payload (admin, client-side) ---
export function generateQRPayload(stand, type = 'visit', secret) {
    const ts = getTimeStep();
    const points = type === 'visit' ? (stand.visit_points || 10) : (stand.activity_points || 25);

    const data = {
        sid: stand.id,
        ts,
        pts: points,
        type,
        name: stand.name,
        emoji: stand.emoji,
    };

    // Generate token
    const tokenMessage = `${stand.id}|${ts}|${points}|${type}`;
    data.tok = simpleHMAC(secret, tokenMessage);

    // Encode to base64
    const json = JSON.stringify(data);
    return btoa(encodeURIComponent(json));
}

// --- Decode QR payload (participant, client-side) ---
export function decodeQRPayload(encodedPayload) {
    try {
        const json = decodeURIComponent(atob(encodedPayload));
        return JSON.parse(json);
    } catch {
        return null;
    }
}

// --- Time remaining until next QR rotation ---
export function getTimeUntilRotation() {
    const now = Date.now() / 1000;
    const elapsed = now % TIME_STEP;
    return Math.ceil(TIME_STEP - elapsed);
}

// --- Get current time step value (for display) ---
export function getCurrentTimeStep() {
    return getTimeStep();
}
