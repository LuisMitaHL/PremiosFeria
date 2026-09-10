import { describe, it, expect, vi, afterEach } from 'vitest';
import { encodeQRPayload, decodeQRPayload, getTimeUntilRotation } from './qrSecurity';

// These helpers carry no secret and perform no signing: the HMAC is produced by
// the sign_scan_code RPC and verified by validate_and_scan (constitution V).
// What is worth protecting here is that a payload survives the round trip
// intact, that a corrupt code fails softly, and that the countdown matches the
// 15-second rotation window the database enforces.

describe('encodeQRPayload / decodeQRPayload', () => {
    it('round-trips a signed payload without altering any field', () => {
        const payload = {
            sid: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
            ts: 112233445,
            pts: 25,
            type: 'activity',
            name: 'CtrlDev',
            emoji: 'Rocket',
            tok: 'a1b2c3d4e5f6',
        };

        expect(decodeQRPayload(encodeQRPayload(payload))).toEqual(payload);
    });

    it('preserves accented and non-ASCII stand names', () => {
        // Stand names are Spanish and operator-supplied; a naive btoa would throw
        // on these, which is why the payload is URI-encoded before base64.
        const payload = { sid: 'x', name: 'Comunidad Técnica ñandú', type: 'visit' };

        expect(decodeQRPayload(encodeQRPayload(payload))).toEqual(payload);
    });

    it('returns null for a code that is not valid base64', () => {
        expect(decodeQRPayload('not-base64-!!!')).toBeNull();
    });

    it('returns null for base64 that does not decode to JSON', () => {
        expect(decodeQRPayload(btoa('plain text, not json'))).toBeNull();
    });

    it('returns null for an empty code', () => {
        expect(decodeQRPayload('')).toBeNull();
    });
});

describe('getTimeUntilRotation', () => {
    afterEach(() => {
        vi.useRealTimers();
    });

    const atEpochSeconds = (seconds) => {
        vi.useFakeTimers();
        vi.setSystemTime(new Date(seconds * 1000));
    };

    it('reports a full window at the instant one begins', () => {
        atEpochSeconds(1_000_000_005 * 15);
        expect(getTimeUntilRotation()).toBe(15);
    });

    it('counts down within the window', () => {
        atEpochSeconds(1_000_000_005 * 15 + 4);
        expect(getTimeUntilRotation()).toBe(11);
    });

    it('never reports zero or a negative remainder', () => {
        // The countdown drives a progress bar; a zero would render an empty bar
        // for a window that is still valid.
        for (let offset = 0; offset < 15; offset += 1) {
            atEpochSeconds(1_000_000_005 * 15 + offset);
            const remaining = getTimeUntilRotation();
            expect(remaining).toBeGreaterThan(0);
            expect(remaining).toBeLessThanOrEqual(15);
        }
    });
});
