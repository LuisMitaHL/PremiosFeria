# Plan NNN — <Feature name>

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) — must be `Approved` before this file is written |
| **Status** | Draft \| Approved \| Executed |
| **Last updated** | YYYY-MM-DD |

> Written in English. This is the HOW. It may name files, tables, functions and packages freely.
> It must not introduce behaviour the spec does not require — if it does, the spec is amended
> first.

## 1. Constitution check

Confirm this plan does not violate `.specify/memory/constitution.md`. Any "No" needs a
justification here and, if the deviation is permanent, an ADR.

| Principle | Complies | Note |
|---|---|---|
| III — Business rules live in the database | Yes / No / N/A | |
| IV — Identity is never a parameter | Yes / No / N/A | |
| V — Secrets never reach the client | Yes / No / N/A | |
| VI — Defence in depth for the point economy | Yes / No / N/A | |
| VII — Chromium 83 target | Yes / No / N/A | |
| IX — Quality gates | Yes / No / N/A | |

## 2. Approach

The shape of the solution in a few paragraphs. Why this approach and not the obvious
alternative. If a simpler option was rejected, say what ruled it out.

## 3. Database changes

Schema, RLS policies and RPC touched. **Remember the init scripts run only once on an empty
volume**: state whether this change requires `./dev.sh --fresh` locally and a wipe in production,
and whether it can be applied to a live event.

| File | Change |
|---|---|
| `supabase/postgres-init/NN_*.sql` | ... |

## 4. Backend and API surface

New or changed RPC signatures, PostgREST queries, and auth service endpoints. Give the exact
success and failure shapes returned to the client.

## 5. Frontend changes

| File | Change |
|---|---|
| `src/...` | ... |

State-management, routing and access-control implications. Remember route guards are cosmetic:
the real control is RLS and RPC.

## 6. Test strategy

| Layer | What is covered | Where |
|---|---|---|
| SQL rule tests | ... | `tests/sql/*.sql` |
| Frontend unit tests | ... | `src/**/*.test.js` |
| Manual verification | ... | steps against `./dev.sh` |

Every business rule from section 5 of the spec needs a SQL test. Every point-economy path needs
a concurrency test.

## 7. Risks and rollback

What could go wrong during the event, how it is detected, and how it is undone.

## 8. Out of scope for this plan

Work the spec allows but this plan deliberately defers, and why.
