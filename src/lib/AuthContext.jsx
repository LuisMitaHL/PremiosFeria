/* ============================================
   Auth Context — Participant + Admin sessions
   ============================================ */

import React, { createContext, useContext, useState, useEffect } from 'react';
import { supabase } from '../supabaseClient.js';
import {
    getCurrentParticipantId,
    saveCurrentParticipantId,
    clearCurrentParticipant,
} from './storage.js';
import {
    getParticipantById,
    registerParticipant as apiRegister,
} from './api.js';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    // --- Participant (anonymous, localStorage-based) ---
    const [participant, setParticipant] = useState(null);
    const [participantLoading, setParticipantLoading] = useState(true);

    // --- Admin (Supabase Auth) ---
    const [adminUser, setAdminUser] = useState(null);
    const [adminLoading, setAdminLoading] = useState(true);

    // Load participant from localStorage on mount
    useEffect(() => {
        const load = async () => {
            const id = getCurrentParticipantId();
            if (id) {
                try {
                    const p = await getParticipantById(id);
                    setParticipant(p);
                } catch {
                    // ID in localStorage but not in DB — clear it
                    clearCurrentParticipant();
                }
            }
            setParticipantLoading(false);
        };
        load();
    }, []);

    // Listen for custom admin auth state changes
    useEffect(() => {
        import('./api.js').then(({ getSession }) => {
            getSession().then(session => {
                setAdminUser(session?.user ?? null);
                setAdminLoading(false);
            });
        });
    }, []);

    // --- Participant actions ---
    const registerParticipant = async ({ name }) => {
        const fingerprint = getDeviceFingerprint();
        const id = await apiRegister(name, fingerprint);
        saveCurrentParticipantId(id);
        const p = await getParticipantById(id);
        setParticipant(p);
        return p;
    };

    const refreshParticipant = async () => {
        const id = getCurrentParticipantId();
        if (id) {
            const p = await getParticipantById(id);
            setParticipant(p);
            return p;
        }
        return null;
    };

    const logoutParticipant = () => {
        clearCurrentParticipant();
        setParticipant(null);
    };

    // --- Admin actions ---
    const loginAdmin = async (username, password) => {
        const { loginAdmin: apiLoginAdmin } = await import('./api.js');
        const result = await apiLoginAdmin(username, password);
        if (result.success) {
            setAdminUser(result.user);
        }
        return result;
    };

    const logoutAdmin = async () => {
        const { logoutAdmin: apiLogoutAdmin } = await import('./api.js');
        await apiLogoutAdmin();
        setAdminUser(null);
    };

    const value = {
        // Participant
        participant,
        participantLoading,
        registerParticipant,
        refreshParticipant,
        logoutParticipant,
        // Admin
        adminUser,
        adminLoading,
        loginAdmin,
        logoutAdmin,
    };

    return (
        <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
    );
}

export function useAuth() {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
    return ctx;
}

// --- Device Fingerprint (moved from old storage.js) ---
function getDeviceFingerprint() {
    const nav = navigator;
    const screen = window.screen;
    const raw = [
        nav.userAgent,
        nav.language,
        screen.width + 'x' + screen.height,
        screen.colorDepth,
        Intl.DateTimeFormat().resolvedOptions().timeZone,
        nav.hardwareConcurrency || '',
    ].join('|');

    let hash = 0;
    for (let i = 0; i < raw.length; i++) {
        const char = raw.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
    }
    return Math.abs(hash).toString(36);
}
