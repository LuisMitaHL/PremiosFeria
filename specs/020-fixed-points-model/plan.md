# Plan 020 — Fixed points model

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Ships with** | Spec 019 — one deployment, one schema change |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Business rules live in the database | Yes | Every award value becomes a constant in SQL. Nothing moves to the client. |
| IV — Identity is never a parameter | Yes | Unchanged: `validate_and_scan` keeps resolving the participant from `auth.uid()`. |
| V — Secrets never reach the client | Yes | The payload stops carrying the award amount, so it carries strictly less. |
| VI — Defence in depth for the point economy | Yes | The cooldown keeps its `FOR UPDATE`; activity uniqueness moves from a partial index on `(participant, community)` to one on `(participant, activity)` — still an index, not an `IF`. |
| VII — Chromium 83 target | N/A | No client syntax changes. |
| IX — Quality gates | Yes | Existing SQL suites 02, 03 and 04 are rewritten against the new values; they must fail before the change and pass after. |

## 2. Approach

The award values become **constants in one place** rather than columns on `communities`. A single
`points_config()` function returning the three numbers keeps them in one file and gives the tests
something to assert against — a scatter of literals across `50_rpc.sql` would drift.

The alternative considered was a `settings` row per value, editable without a deployment. Rejected:
spec 020 says these are constants precisely so reward costs and leaderboard positions cannot be
silently revalued mid-event, and a row in a table is an invitation to edit it.

`communities.visit_points` and `activity_points` are **dropped**, not left unused. A column nobody
reads is a column somebody will read.

## 3. Database changes

Requires a wipe: `./dev.sh --fresh` locally, `rm -rf ./data/db` in production. **Cannot be applied
during an event.** It ships together with spec 019's `activities` table.

| File | Change |
|---|---|
| `20_schema.sql` | Drop `visit_points` and `activity_points` from `communities` with their `CHECK`s. Add `scans.activity_id` referencing `activities`. Replace the partial unique index `scans_one_activity_per_stand` with `scans_one_completion_per_activity` on `(participant_id, activity_id) WHERE activity_id IS NOT NULL`. |
| `50_rpc.sql` | Add `points_config()`. Rewrite the award arithmetic in `sign_scan_code` and `validate_and_scan` to read from it. Change the visit cooldown from 5 minutes to 30. Replace the per-stand activity check with a per-activity one. |
| `80_column_grants.sql` | Runs last already; the dropped columns disappear from its computed list on their own. |

The payload signed by `sign_scan_code` changes shape: it stops carrying `pts` and starts carrying
`act` (the activity, for activity codes). That invalidates every code in flight, which is
acceptable in a deployment and impossible during an event.

**The clamp stays.** With the amount no longer in the payload there is nothing to inflate, but
`GREATEST(0, LEAST(...))` costs nothing and removing a guard because the current caller is trusted
is how audit finding F3 happened.

## 4. Backend and API surface

`points_config()` returns `jsonb`: `{visit, activity_main, activity_other}`. Read by the RPC and by
the tests; not exposed to clients, which have no reason to know the numbers before a scan.

`validate_and_scan` return shape is unchanged, so the scanner screen needs no change for this spec.

## 5. Frontend changes

| File | Change |
|---|---|
| `src/pages/admin/AdminDashboard.jsx` | Remove the visit/activity point inputs and their display. A stand no longer configures award values. |
| `src/lib/api.js` | Drop `visit_points` and `activity_points` from `COMMUNITY_COLUMNS` and from the stand update payload. |
| `src/pages/admin/QRDisplay.jsx` | Stops reading `visit_points` for its subtitle. Spec 011 reworks this screen properly; this spec only stops it referencing columns that no longer exist. |

## 6. Test strategy

| Layer | What is covered | Where |
|---|---|---|
| SQL | Visit awards 10 everywhere; cooldown is 30 minutes not 5; main event awards 30 and others 10; at most one main event; one completion per activity, structurally; awards never negative; a stand cannot set an award value because the columns are gone | `tests/sql/02`, `03`, `04`, rewritten |
| SQL | Two concurrent scans of one activity produce one award | `tests/sql/03` |
| Frontend | Nothing worth a unit test: the change is removal | — |
| Manual | Scan a visit twice inside 30 minutes and after; complete an activity twice | Chrome DevTools against `./dev.sh` |

Existing suites 02, 03 and 04 assert the **old** values. They are rewritten as part of the change,
and each must be seen failing against the old schema first — a test that was never red proves
nothing.

## 7. Risks and rollback

- **The dev schema diverges** (`dev.sh` keeps a plaintext password column and writes its own
  grants). The activity changes touch files dev copies verbatim, so dev must be re-provisioned and
  the flow re-verified in the browser, not assumed.
- **Rollback is a redeploy of the previous image plus a wipe.** There is no migration back; an event
  mid-flight cannot take this change at all.
- The 30-minute cooldown makes the fair feel slower. That is the intent, and it is reversible in one
  constant if the first event says otherwise.

## 8. Out of scope for this plan

Everything about activities as entities — the table, the lifecycle, the stand's screens. Spec 019,
same deployment. This plan assumes `activities` exists and prices it.
