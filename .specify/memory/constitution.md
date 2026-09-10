# Community Quest — Constitution

Version: 1.0.0 · Ratified: 2026-09-09 · Status: Active

This document defines the non-negotiable principles of the Community Quest project. It sits
above every spec, plan and task. When a spec, a plan, a code review or an AI assistant proposes
something that contradicts this constitution, **the constitution wins** — the only way to
override a principle is to amend this file in its own pull request, with the rationale recorded.

Process rules for the team (branching, commit format, review) live in `AGENTS.md`.
Domain vocabulary lives in `.specify/memory/glossary.md`.

---

## I. Specification precedes implementation

No behavioural change reaches `develop` without an approved spec.

- A **spec** (`specs/NNN-slug/spec.md`) states WHAT the system does and WHY. It is written for
  someone who does not read code.
- A **plan** (`plan.md`) states HOW, technically.
- **Tasks** (`tasks.md`) break the plan into executable steps.
- Only then is code written.

Exempt from this rule: dependency bumps, typo fixes in comments, and the SDD scaffolding itself
(bootstrapped in branch `000-sdd-bootstrap`). Everything else needs a spec.

A spec that documents already-shipped behaviour is a **retro-spec**: it carries
`Status: Implemented` and an *As-built notes* section anchoring each requirement to real code.
Retro-specs have no `plan.md` or `tasks.md` until a change is proposed against them.

## II. Specs describe behaviour, never implementation

A spec must not name a React component, a table column, an npm package or an RPC function in its
requirements. It describes observable behaviour, rules, and edge cases. If a reader cannot tell
whether a requirement was met by running the app, the requirement is not written yet.

Implementation detail belongs in `plan.md` and in *As-built notes*.

Every requirement must be **testable**. "The scanner should be fast" is not a requirement;
"a scan resolves in under 2 seconds on a 3G connection" is.

Unknowns are marked `[NEEDS CLARIFICATION: question]` and must be resolved before the spec is
approved. An unresolved marker blocks the plan.

## III. Business rules live in the database

All game rules — point awards, cooldowns, uniqueness, ceilings, claim atomicity — are
implemented as `SECURITY DEFINER` PL/pgSQL functions in `supabase/postgres-init/50_rpc.sql` and
`51_stand_login.sql`, with `SET search_path = public`.

The client is a rendering layer. Any validation in the frontend is a **courtesy message**, never
a control. A rule that exists only in JavaScript does not exist.

Corollary: a spec whose rules cannot be enforced server-side is not ready.

## IV. Identity is never a parameter

Every RPC resolves the acting participant or stand from `auth.uid()`, read out of the verified
JWT claims by the `auth` shim (`35_auth_shim.sql`). No RPC accepts a caller identity as an
argument, and no RPC trusts an id sent by the client to decide who is acting.

Row Level Security is enabled on all six tables and anchors on `auth.uid()`, not on a role name.
JWTs always carry `role: authenticated`; `community_admin` is a client-side label with no
authority behind it.

`30_grants.sql` grants `SELECT/INSERT/UPDATE` broadly to `anon` and `authenticated` — the
effective filter is **entirely RLS**. Adding a table without adding its policies exposes it.

## V. Secrets never reach the client

The HMAC secret lives in `settings.hmac_secret`. The `settings` table has RLS enabled and **no
policy at all**, which makes it unreadable to every client role; only `SECURITY DEFINER`
functions can read it.

QR payloads are signed server-side by `sign_scan_code`. The browser only base64-encodes an
already-signed payload. This is the fix for audit finding F3 and must not regress.

Anything Vite bakes into the bundle (`VITE_*`) is public by definition. Nothing secret may be
passed that way. Files holding real secrets (`.env.prod`, `seed/*.csv`, `data/`) are
git-ignored and stay that way.

## VI. Defence in depth for the point economy

Points are the currency of the event; every path that mints or spends them is hardened at more
than one layer:

- **Ceilings**: visit points are capped at 30 and activity points at 100, enforced by a `CHECK`
  constraint on `communities` *and* re-clamped inside `validate_and_scan` with
  `GREATEST(0, LEAST(...))`, so a tampered payload cannot exceed them.
- **Non-negative**: `participants.points` carries `CHECK (points >= 0)`; awards are floored at 0.
- **Activity uniqueness**: guaranteed by the partial unique index
  `scans_one_activity_per_stand`, not by an `IF` — the `IF` only renders a friendly message.
- **Cooldown races**: the participant row is locked with `SELECT ... FOR UPDATE` before the
  cooldown is evaluated (audit finding F8).
- **Claim atomicity**: `claim_reward` gates on conditional `UPDATE ... WHERE stock > 0` and
  `UPDATE ... WHERE points >= cost` inside a subtransaction, so stock is never decremented
  without points being debited.

Pre-checks that produce friendly messages are allowed and encouraged, but **the real gate is
always a constraint, an index, or a conditional write**.

## VII. Compatibility target: Chromium 83

The audience uses old Android browsers. The build targets `chrome83` for both JS and CSS
(`vite.config.js`), and `browserslist` states it. Do not introduce syntax or Web APIs newer than
Chromium 83 without an ADR that accepts the exclusion.

## VIII. Designed to be ephemeral

The production stack runs for the hours a fair lasts and is then torn down. Provisioning is
operator-driven: stands and rewards come from `seed/*.csv` at first Postgres init; secrets come
from `deploy-keys.sh`. No account is ever hardcoded in SQL.

Changes must preserve the ability to bring the whole system up from nothing with a documented
sequence, and to wipe it just as easily.

## IX. Quality gates are not optional

Before a pull request merges: lint clean, frontend tests green, SQL rule tests green, CI green.
The full Definition of Done is `.specify/checklists/definition-of-done.md`.

Verification is done with **lint and tests, not with production builds**. `npm run build` is a
release step, not a check.

## X. No AI attribution in the repository

No commit message, pull request description, code comment, or documentation file in this
repository may credit, mention, or link to an AI model or assistant. No `Co-Authored-By` lines
naming a model, no "Generated with" footers, no session links.

The team may use any AI assistant. The repository records the work of the people who ship it.

This rule is enforced by convention and by review, not by hooks. Reviewers reject PRs that
violate it.

---

## Amendment

Amending this constitution requires its own pull request, touching only this file plus any spec
made obsolete by the change, with the rationale in the PR description. Bump the version:
MAJOR for removing or reversing a principle, MINOR for adding one, PATCH for wording.
