// El contexto y sus dos ayudantes viven aparte del proveedor.
//
// No es una preferencia de estilo: un archivo que exporta un componente y ademas
// constantes o funciones rompe el refresco en caliente de React, asi que cada
// cambio en la sesion recargaba la pagina entera durante el desarrollo. La
// huella del dispositivo, ademas, la usan pantallas que no montan el proveedor.

import { createContext, useContext } from 'react';

export const AuthContext = createContext(null);

export function useAuth() {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
    return ctx;
}

// Identifica al telefono, no a la persona. Es el segundo factor que hace segura
// una identificacion por nombre (spec 001): sin el, cualquiera escribe un
// nickname ajeno y se lleva el perfil.
export function getDeviceFingerprint() {
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
