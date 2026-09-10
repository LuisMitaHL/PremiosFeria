# Plan 021 — Stand reward management

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Rules in the database | Yes | Registering, restocking and the ceiling are RPC and constraints. `rewards` gets no client write policy. |
| IV — Identity is never a parameter | Yes | The owning stand comes from `auth.uid()` via `calling_community()`, already built for spec 019. |
| V — Secrets never reach the client | N/A | Nothing secret here. |
| VI — Defence in depth | Yes | The 300-point ceiling is a `CHECK`; "a stand may only increase stock" is enforced in the RPC, which is the only write path. |
| VII — Chromium 83 | Yes | Same React and CSS as the rest. |
| IX — Quality gates | Yes | New SQL suite. |

## 2. Approach

Two RPC, mirroring the activity ones: `create_reward` and `increase_reward_stock`. There is
deliberately **no** `update_reward` — the cost is fixed at creation and belongs to the organiser
afterwards (spec 023), and stock only ever goes up from the stand's side. Naming the functions after
what they may do, rather than a general "update", is what makes the direction a rule instead of a
convention.

`rewards` gains `is_withdrawn`, so the organiser can take a prize off the shelf without deleting it
(spec 023, R22 to R25). The column exists now because the catalogue must already respect it — a
withdrawn reward is not claimable — even though only spec 023 will set it.

## 3. Database changes

Requires a wipe, as every schema change does.

| File | Change |
|---|---|
| `20_schema.sql` | `rewards`: `CHECK (cost BETWEEN 0 AND 300)`, name 3 to 40 characters, description at most 100, `is_withdrawn BOOLEAN NOT NULL DEFAULT false` |
| `53_rewards.sql` (new) | `create_reward`, `increase_reward_stock` |
| `50_rpc.sql` | `claim_reward` refuses a withdrawn reward, and one whose community is withdrawn |
| `80_column_grants.sql` | Runs last; picks up the new column automatically. The suite asserts it. |

## 4. Frontend changes

| File | Change |
|---|---|
| `src/pages/admin/RewardsSection.jsx` | New. The console's second section: the stand's rewards with remaining stock, a create form, and a control to add stock |
| `src/pages/admin/AdminDashboard.jsx` | Replace the rewards placeholder |
| `src/pages/Rewards.jsx` | Hide withdrawn rewards as unavailable rather than claimable |
| `src/lib/api.js` | `getRewardsForCommunity`, `createReward`, `increaseRewardStock`; exclude withdrawn from the catalogue's claimable state |

## 5. Test strategy

`tests/sql/11_reward_management.sql`: the ceiling at 300 including through the API; name and
description limits; a stand can raise stock and cannot lower it; a stand cannot touch another
stand's rewards; a withdrawn reward cannot be claimed; stock never negative; no reward can be
deleted. Concurrency: two claims on the last unit produce one handover (already covered by suite
05, extended for withdrawal).

## 6. Risks

- The claim path changes again in spec 018, which replaces `claim_reward` entirely. Anything built
  here on top of the current claim should be the catalogue's display, not its mechanics.
- `is_withdrawn` ships unused by any writer until spec 023. That is deliberate: the reader has to
  respect it from the moment it exists, or 023 would have to revisit every reader.

## 7. Out of scope

The organiser's screens (spec 023) and the in-person handover (spec 018).
