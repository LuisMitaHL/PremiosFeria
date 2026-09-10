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
    PARTICIPANT_COLUMNS,
} from './api.js';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    // --- Participant (anonymous, localStorage-based) ---
    const [participant, setParticipant] = useState(null);
    const [participantLoading, setParticipantLoading] = useState(true);

    // --- Admin (Supabase Auth) ---
    const [adminUser, setAdminUser] = useState(null);
    const [adminLoading, setAdminLoading] = useState(true);
    const [organizerUser, setOrganizerUser] = useState(null);

    // Load participant on mount: prefiere la fila vinculada a la sesión de
    // Supabase Auth; localStorage solo es caché de visualización.
    useEffect(() => {
        const load = async () => {
            try {
                const { data: { user } } = await supabase.auth.getUser();
                let p = null;
                if (user) {
                    const { data } = await supabase
                        .from('participants')
                        .select(PARTICIPANT_COLUMNS)
                        .eq('auth_user_id', user.id)
                        .maybeSingle();
                    p = data;
                }
                if (!p) {
                    const id = getCurrentParticipantId();
                    if (id) p = await getParticipantById(id);
                }
                if (p) {
                    saveCurrentParticipantId(p.id);
                } else {
                    clearCurrentParticipant();
                }
                setParticipant(p);
            } catch {
                clearCurrentParticipant();
            } finally {
                setParticipantLoading(false);
            }
        };
        load();
    }, []);

    // Listen for custom admin auth state changes
    useEffect(() => {
        import('./api.js').then(({ getSession }) => {
            getSession().then(session => {
                // Una sola sesión a la vez: el cliente de auth es uno. Se
                // encamina según lo que diga el token, pero cada pantalla del
                // panel vuelve a comprobarlo contra la base.
                if (session?.user?.organizer) {
                    setOrganizerUser(session.user);
                    setAdminUser(null);
                } else {
                    setAdminUser(session?.user ?? null);
                    setOrganizerUser(null);
                }
                setAdminLoading(false);
            });
        });
    }, []);

    // --- Participant actions ---
    const registerParticipant = async ({ name }) => {
        const fingerprint = getDeviceFingerprint();
        const { id, recovered } = await apiRegister(name, fingerprint);
        saveCurrentParticipantId(id);
        const p = await getParticipantById(id);
        setParticipant(p);
        return { ...p, recovered };
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

    const logoutParticipant = async () => {
        await supabase.auth.signOut();
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

    const loginOrganizer = async (username, password) => {
        const { loginOrganizer: apiLoginOrganizer } = await import('./api.js');
        const result = await apiLoginOrganizer(username, password);
        if (result.success) {
            setOrganizerUser(result.user);
            setAdminUser(null);
        }
        return result;
    };

    const logoutOrganizer = async () => {
        const { logoutAdmin: apiLogoutAdmin } = await import('./api.js');
        await apiLogoutAdmin();
        setOrganizerUser(null);
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
        // Organizer
        organizerUser,
        loginOrganizer,
        logoutOrganizer,
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
