import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
    plugins: [
        react(),
        VitePWA({
            registerType: 'autoUpdate',
            includeAssets: ['favicon.svg', 'icon-192.svg', 'icon-512.svg'],
            manifest: {
                name: 'Community Quest — Rewards System',
                short_name: 'Community Quest',
                description: 'Escanea QR, acumula puntos y gana premios',
                theme_color: '#ffffff',
                background_color: '#ffffff',
                display: 'standalone',
                start_url: '/',
                icons: [
                    { src: '/icon-192.svg', sizes: '192x192', type: 'image/svg+xml' },
                    { src: '/icon-512.svg', sizes: '512x512', type: 'image/svg+xml', purpose: 'any maskable' }
                ]
            },
            workbox: {
                globPatterns: ['**/*.{js,css,html,ico,png,svg}']
            }
        })
    ],
    server: {
        allowedHosts: true
    },
    // Minimum target: Bromite 83 (= Chromium 83). Chrome 83 supports
    // native ESM + dynamic import + import.meta, so no SystemJS legacy
    // bundle needed — just stop Oxc from emitting post-83 syntax.
    build: {
        target: 'chrome83',
        cssTarget: 'chrome83',
        modulePreload: { polyfill: true },
    }
});
