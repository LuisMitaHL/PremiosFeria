/* ============================================
   QR Security — códigos rotativos firmados en el servidor
   ============================================
   - La firma (HMAC-SHA256) ocurre en la base de datos vía el RPC
     sign_scan_code; el secreto nunca llega al navegador.
   - Validación: RPC validate_and_scan.
   ============================================ */

const TIME_STEP = 15; // segundos — QR rota cada 15s

// --- Codificar payload para el QR (admin, client-side) ---
export function encodeQRPayload(payloadObj) {
    const json = JSON.stringify(payloadObj);
    return btoa(encodeURIComponent(json));
}

// --- Decodificar payload del QR (participante, client-side) ---
export function decodeQRPayload(encodedPayload) {
    try {
        const json = decodeURIComponent(atob(encodedPayload));
        return JSON.parse(json);
    } catch {
        return null;
    }
}

// --- Tiempo restante hasta la próxima rotación del QR ---
export function getTimeUntilRotation() {
    const now = Date.now() / 1000;
    const elapsed = now % TIME_STEP;
    return Math.ceil(TIME_STEP - elapsed);
}
