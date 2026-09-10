import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

// Vitest runs with its own config rather than reusing vite.config.js: the PWA
// plugin has nothing to contribute to a test run, and keeping the two separate
// means a change to the build cannot quietly change how tests behave.
export default defineConfig({
    plugins: [react()],
    test: {
        environment: 'jsdom',
        globals: true,
        setupFiles: ['./src/test/setup.js'],
        include: ['src/**/*.test.{js,jsx}'],
        restoreMocks: true,
    },
});
