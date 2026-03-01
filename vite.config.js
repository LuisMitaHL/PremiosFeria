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
                name: 'FeriaPoints — Rewards System',
                short_name: 'FeriaPoints',
                description: 'Escanea QR, acumula puntos y gana premios en la feria universitaria',
                theme_color: '#0f0a1e',
                background_color: '#0f0a1e',
                display: 'standalone',
                start_url: '/',
                icons: [
                    { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
                    { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' }
                ]
            },
            workbox: {
                globPatterns: ['**/*.{js,css,html,ico,png,svg}']
            }
        })
    ],
    server: {
        allowedHosts: true
    }
});
