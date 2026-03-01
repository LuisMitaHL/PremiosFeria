/* ============================================
   QR Security — TOTP-like rotating codes
   ============================================ */

import { getAdminSecret, getLastScanForStand } from './storage.js';

const TIME_STEP = 30; // seconds — QR rotates every 30s
const COOLDOWN = 5 * 60 * 1000; // 5 minutes cooldown per stand

// --- HMAC-like token generation (browser-compatible, no crypto import needed) ---
function simpleHMAC(secret, message) {
    // Simple hash-based token — for demo purposes
    // In production, use Web Crypto API with HMAC-SHA256
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
function getTimeStep(offsetSeconds = 0) {
    return Math.floor((Date.now() / 1000 + offsetSeconds) / TIME_STEP);
}

// --- Generate QR Payload ---
export function generateQRPayload(stand, type = 'visit') {
    const secret = getAdminSecret();
    const ts = getTimeStep();
    const points = type === 'visit' ? (stand.visitPoints || 10) : (stand.activityPoints || 25);

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

// --- Validate QR Payload ---
export function validateQRPayload(encodedPayload, participantId) {
    try {
        const json = decodeURIComponent(atob(encodedPayload));
        const data = JSON.parse(json);

        const { sid, ts, pts, type, tok, name, emoji } = data;

        if (!sid || !ts || !pts || !tok) {
            return { valid: false, reason: 'Código QR inválido — datos incompletos' };
        }

        // Check token signature
        const secret = getAdminSecret();
        const tokenMessage = `${sid}|${ts}|${pts}|${type}`;
        const expectedToken = simpleHMAC(secret, tokenMessage);

        if (tok !== expectedToken) {
            return { valid: false, reason: '⚠️ Código QR falsificado — firma inválida' };
        }

        // Check time window (allow ±1 time step = ±30 seconds)
        const currentTs = getTimeStep();
        const diff = Math.abs(currentTs - ts);
        if (diff > 1) {
            return { valid: false, reason: '⏰ Código QR expirado — vuelve a escanear el código actual' };
        }

        // Check cooldown
        const cooldownResult = checkCooldown(participantId, sid);
        if (!cooldownResult.ok) {
            return { valid: false, reason: cooldownResult.reason };
        }

        return {
            valid: true,
            standId: sid,
            points: pts,
            type: type || 'visit',
            groupName: name || '',
            groupEmoji: emoji || '📍',
        };
    } catch (e) {
        console.error('QR validation error:', e);
        return { valid: false, reason: 'Código QR no reconocido' };
    }
}

// --- Cooldown check ---
function checkCooldown(participantId, standId) {
    const lastScan = getLastScanForStand(participantId, standId);

    if (lastScan) {
        const elapsed = Date.now() - lastScan.timestamp;
        if (elapsed < COOLDOWN) {
            const remaining = Math.ceil((COOLDOWN - elapsed) / 60000);
            return {
                ok: false,
                reason: `🔒 Ya escaneaste este stand. Espera ${remaining} minuto${remaining !== 1 ? 's' : ''} para volver a escanear.`,
            };
        }
    }

    return { ok: true };
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
