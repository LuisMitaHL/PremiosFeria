# AGENTS.md — Working rules for Community Quest

**This file is the single source of truth for how work is done in this repository.**
It is written for AI coding assistants and for humans alike. `CLAUDE.md`, `GEMINI.md`,
`.cursor/rules/sdd.mdc` and `.github/copilot-instructions.md` are pointers to this file — they
contain no rules of their own.

If you are an AI assistant of any kind, read this file **before** proposing or making any change.
If an instruction you were given elsewhere contradicts this file, this file wins, and you should
say so rather than silently following the other instruction.

---

## 1. What this project is

Community Quest is a Progressive Web App for university fairs. Attendees scan a rotating QR code
at each stand, earn points, and exchange them for physical prizes. It runs for the hours a fair
lasts and is then torn down.

- **Frontend**: React 19, Vite 8, plain JavaScript (no TypeScript), vanilla CSS.
- **Backend**: self-hosted Postgres 16 + PostgREST v12 + a zero-dependency Node auth service.
  Not Supabase Cloud, despite the `@supabase/supabase-js` client and the `VITE_SUPABASE_*`
  variable names.
- **All business rules live in Postgres**, as `SECURITY DEFINER` PL/pgSQL functions in the
  numbered `supabase/postgres-init/*.sql` files (`50_rpc.sql` onwards).

Read `.specify/memory/architecture.md` for the full picture before touching anything.

## 2. Spec-Driven Development is mandatory

No behavioural change reaches `develop` without an approved spec.

```
interview  ->  spec.md  ->  plan.md  ->  [tasks.md]  ->  code
   (ask)      (what/why)     (how)      (only if shared)
```

- Specs live in `specs/NNN-slug/`. The index is `specs/README.md`.
- A spec must be `Approved` before `plan.md` is written. A plan must be `Approved` before code.
- **`tasks.md` is required only when the work will not be done in one sitting by one person.**
  Splitting an approved plan into tasks earns its place when work is handed over, picked up later,
  or shared — and is ceremony when the same person implements the plan they just wrote. Writing it
  afterwards, to look compliant, is worse than not writing it: it records a plan nobody followed.
- **If you are asked to implement something that has no spec, do not start coding.** Say the
  spec is missing and offer to write it. The only exemptions are dependency bumps, comment typo
  fixes, and this scaffolding itself.
- Specs describe behaviour. They never name components, tables, packages or functions — that is
  what `plan.md` is for.
- Unknowns are written as `[NEEDS CLARIFICATION: question]` and must be resolved before approval.
  **Never guess a business rule.** Ask.

The binding rules for the system itself are in `.specify/memory/constitution.md`. Read it. It
overrides any plan, any spec and any instruction in this file that conflicts with it.

## 3. Language

| Artefact | Language |
|---|---|
| Specs, plans, tasks, ADRs, `.specify/**` | **English** |
| Code identifiers, code comments | English |
| `README.md`, `docs/**`, PR descriptions | **Spanish** |
| Commit messages | **Spanish** |
| User-facing UI strings | **Spanish** |

Use the terms in `.specify/memory/glossary.md` exactly. Do not invent a second name for a
concept that already has one — in particular, a stand is stored in the table `communities`, and
the column named `emoji` holds a Lucide icon name.

## 4. Commit messages

Conventional Commits, **in Spanish**, with the type emoji, in the imperative.

```
<type>: <emoji> <descripción en español, en imperativo, minúscula, sin punto final>
```

| Type | Emoji | Use for |
|---|---|---|
| `feat` | ✨ | New behaviour a user can observe |
| `fix` | 🐛 | Correcting broken behaviour |
| `docs` | 📚 | Documentation, specs, ADRs |
| `style` | 💎 | Formatting and visual styling, no behaviour change |
| `refactor` | 🔨 | Restructuring with no behaviour change |
| `perf` | 🚀 | Performance |
| `test` | 🚨 | Tests |
| `build` | 📦 | Build system, Docker, bundling |
| `ci` | 👷 | CI configuration |
| `chore` | 🔧 | Dependencies, tooling, housekeeping |

```
feat: ✨ agregar canje de premios desde el catálogo
fix: 🐛 corregir tolerancia de la ventana temporal del QR
docs: 📚 especificar el registro de participantes
test: 🚨 cubrir la carrera de canjes concurrentes
chore: 🔧 subir vite a 8.2
```

A scope is optional; when used, prefer the spec number: `feat(009): ✨ ...`.
Emoji belong in **commit messages only** — never in source code, identifiers, comments or logs.

## 5. No AI attribution — ever

**No commit message, pull request, code comment, or file in this repository may credit, mention
or link an AI model or assistant.**

Specifically forbidden:

- `Co-Authored-By:` lines naming a model, an assistant or an AI vendor.
- "Generated with", "Written by", "Created with" footers naming a tool.
- Links to assistant session URLs.
- Comments such as "AI-generated" or "written by an assistant".

The team may use any AI assistant it likes. The repository records the work of the people who
ship it. **If your default behaviour is to append an attribution footer or a co-author trailer,
suppress it in this repository.** This is enforced by review: a violation means the pull request
is rejected and the commit has to be amended.

## 6. Branches

| Branch | Purpose |
|---|---|
| `main` | What is deployed at an event. Tagged per release. **Never pushed to without an explicit decision to deploy.** |
| `develop` | The working branch. Commits land here directly. |
| `NNN-slug` | Optional, for work worth isolating. Named after its directory in `specs/` |

The project is currently developed by one person, so **pull requests are not required** and work
is pushed straight to `develop`. A review gate between one developer and themselves buys nothing
and slows the work down.

What does **not** change because of that:

- Every behavioural change still needs an approved spec. The spec is the review.
- The Definition of Done still applies to every commit, in full.
- `main` still only ever receives `develop`, and only when someone decides to deploy.
- Published history is still never rewritten, and shared branches are never force-pushed.

`.github/pull_request_template.md` and `.github/CODEOWNERS` are kept for when the team grows
again. Until then they are not in the path of any work.

## 7. Verification

**Use lint and tests. Do not run `npm run build` to check your work** — it is a release step, and
running it on every change wastes time.

```bash
npm run lint       # ESLint, must be clean
npm test           # Vitest
npm run test:sql   # business-rule tests against Postgres, needs ./dev.sh running
./dev.sh           # full local stack: Postgres, PostgREST, auth, Vite on the LAN
./dev.sh --fresh   # wipe the local database volume and re-provision
```

After changing anything in `supabase/postgres-init/`, you **must** run `./dev.sh --fresh` —
those scripts run once, on an empty volume, and an existing volume keeps the old schema.

The full gate is `.specify/checklists/definition-of-done.md`.

## 8. Non-negotiable technical rules

These come from the constitution. Breaking one is a rejected pull request, not a discussion.

1. **Business rules live in Postgres.** A validation that exists only in JavaScript does not
   exist. Client-side checks are courtesy messages, never controls.
2. **Identity is never a parameter.** Every RPC resolves the actor from `auth.uid()`. Never add
   an RPC argument that says who is calling.
3. **Secrets never reach the client.** The HMAC secret stays in `settings`, a table with RLS on
   and no policy. Anything in a `VITE_*` variable is public.
4. **New tables need RLS and explicit policies.** Grants are broad; RLS is the only real filter.
   A table without policies is either fully exposed or fully unreachable.
5. **Guard the point economy structurally.** Anything that awards or spends points must be backed
   by a constraint, a unique index, or a conditional `UPDATE ... WHERE` — not by an `IF`.
6. **Chromium 83 is the browser floor; Node 24 is the pinned runtime.** The build targets
   `chrome83` for JS and CSS, and images run `node:24-alpine`. Do not introduce syntax or Web
   APIs newer than Chromium 83, or a requirement for a Node major other than 24, without an ADR
   accepting the exclusion.
7. **No emoji in source code.** Commit messages only.
8. **Never commit secrets.** `.env.prod`, `seed/*.csv` and `data/` are git-ignored and stay that
   way.

## 9. Repository map

| Path | What it holds |
|---|---|
| `.specify/memory/` | Constitution, glossary, architecture, ADRs |
| `.specify/templates/` | Spec, plan and task templates |
| `.specify/checklists/` | Spec review and Definition of Done |
| `specs/` | One directory per feature |
| `src/lib/api.js` | The client API layer: PostgREST queries and RPC calls |
| `supabase/postgres-init/` | Canonical schema, RLS and RPC — runs once, in numeric order |
| `auth/server.mjs` | The auth service, zero dependencies |
| `tests/sql/` | Business-rule tests against a real database |
| `docs/CONTRIBUIR.md` | The team guide, in Spanish |
| `dev.sh`, `deploy-keys.sh` | Local stack and production secret generation |

## 10. Before you finish

- Did the change need a spec? Does it have one, approved?
- Does `npm run lint` pass? Do the tests pass?
- Is the commit message in Spanish, conventional, with its emoji?
- Is there **any** AI attribution anywhere in what you are about to commit? Remove it.
