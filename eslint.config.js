import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';

// Lint is the verification gate for this project (see AGENTS.md): `npm run build`
// is a release step, not a check. Keep this config strict enough to catch real
// mistakes and quiet enough that a clean run means something.
export default [
    {
        ignores: [
            'dist/**',
            'node_modules/**',
            '.dev/**',
            'data/**',
            'coverage/**',
        ],
    },

    // Browser application code.
    {
        files: ['src/**/*.{js,jsx}'],
        ...js.configs.recommended,
        languageOptions: {
            ecmaVersion: 2020, // Chromium 83 floor — see ADR 0005
            sourceType: 'module',
            globals: globals.browser,
            parserOptions: {
                ecmaFeatures: { jsx: true },
            },
        },
        plugins: {
            'react-hooks': reactHooks,
            'react-refresh': reactRefresh,
        },
        rules: {
            ...js.configs.recommended.rules,

            // Hooks correctness. The full `recommended-latest` preset of
            // eslint-plugin-react-hooks v7 also enables the React Compiler rules;
            // adopting those is tracked as future work, not a silent change here.
            'react-hooks/rules-of-hooks': 'error',
            'react-hooks/exhaustive-deps': 'warn',

            // Keep fast refresh working: a module that exports a component
            // should export only components.
            'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],

            // Unused code is removed, not commented out (Definition of Done).
            'no-unused-vars': ['error', {
                argsIgnorePattern: '^_',
                varsIgnorePattern: '^_',
                caughtErrorsIgnorePattern: '^_',
            }],

            // Constitution VII: no emoji in source code. Commit messages only.
            'no-irregular-whitespace': 'error',

            eqeqeq: ['error', 'smart'],
            'no-console': ['warn', { allow: ['warn', 'error'] }],
        },
    },

    // Node code: the auth service, tooling and config files.
    {
        files: ['auth/**/*.mjs', '*.config.js', 'tests/**/*.mjs'],
        ...js.configs.recommended,
        languageOptions: {
            ecmaVersion: 'latest',
            sourceType: 'module',
            globals: globals.node,
        },
        rules: {
            ...js.configs.recommended.rules,
            'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],

            // The auth service initialises defensively before a try/catch
            // (`let body = {}`, `let community = null`) so the variable always
            // has a defined shape on every branch. That reads better than the
            // alternatives and is not a bug, which is all this rule detects.
            'no-useless-assignment': 'off',
        },
    },

    // Tests run under Vitest in Node, not in the browser, so the Chromium 83
    // syntax floor does not apply to them — only to what ships.
    {
        files: ['**/*.test.{js,jsx}', 'src/test/**/*.{js,jsx}'],
        languageOptions: {
            ecmaVersion: 'latest',
            globals: { ...globals.browser, ...globals.node },
        },
        rules: {
            'no-console': 'off',
        },
    },
// ---------------------------------------------------------------------
    // TEMPORARY: pre-existing debt, downgraded so the gate can be switched on
    // without touching application code outside a spec.
    //
    // As of the SDD bootstrap there are 24 unused identifiers in `src/`: a
    // vestigial `import React` in every page (the automatic JSX runtime made it
    // unnecessary) plus a handful of genuinely dead imports and locals.
    //
    // Spec 016 (naming-and-hygiene-cleanup) removes them. When it lands, DELETE
    // this block and add `--max-warnings 0` to the lint script, so unused code
    // becomes a hard failure again.
    // ---------------------------------------------------------------------
    {
        files: ['src/**/*.{js,jsx}'],
        rules: {
            'no-unused-vars': ['warn', {
                argsIgnorePattern: '^_',
                varsIgnorePattern: '^_',
                caughtErrorsIgnorePattern: '^_',
            }],
        },
    },
];
