# Plan 031 — Event statistics

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) — Approved |
| **Status** | Approved |
| **Last updated** | 2026-09-11 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Business rules live in the database | Yes | Every figure is computed by one `SECURITY DEFINER` function in Postgres. The client renders; it computes no total, average, band or grouping. |
| IV — Identity is never a parameter | Yes | `event_statistics(p_from, p_to)` accepts only time bounds. Who may read is resolved inside by `calling_organizer()` from `auth.uid()`. |
| V — Secrets never reach the client | Yes | The response selects counts, names and timestamps only. No code value, hash, fingerprint or secret is projected (R48). |
| VI — Defence in depth for the point economy | N/A | This feature awards and spends nothing; R47 makes it read-only. |
| VII — Chromium 83 target | Yes, with ADR | Shared surfaces keep the floor. The chart dependency is confined to a lazily loaded operator-only chunk; ADR 0006 records the exclusion. |
| IX — Quality gates | Yes | SQL tests for every figure and the access rule; unit tests for CSV and empty states; lint and tests, not build. |

## 2. Approach

**One RPC, one snapshot.** All figures come back from a single `event_statistics()` call. The
spec requires the section to show the moment it was read (R10) and one filter to move every
figure together (R15); a single read makes both true by construction, and a single SQL statement
gives all sub-aggregates the same MVCC snapshot. Per-chart endpoints were rejected: they would
multiply round trips, and two figures read a moment apart could disagree about a fair that is no
longer changing anyway.

**Aggregate where the data is, send answers not rows.** The function returns pre-bucketed arrays
(about 24 hourly points, ~10 stands, ~7 bands, ~10 top participants). Reference scale is ~300
participants and ~10 stands, so the payload is small and the query is cheap. No table rows reach
the browser.

**Time is grouped server-side in the fixed event zone.** `America/La_Paz`, via
`date_trunc('hour', ts AT TIME ZONE 'America/La_Paz')`. Bucket labels are returned as local
wall-clock text (`YYYY-MM-DDTHH:00`) and used verbatim as axis labels, so no client ever
re-interprets a timestamp in the device's zone.

**The charting dependency is quarantined.** `react-chartjs-2` + `chart.js` are imported only by
`StatsArea.jsx`, which is reached through `React.lazy`. Vite emits it as a separate chunk, so the
participant/stand bundle is unchanged and R5 holds. CSV needs no library at all.

The obvious alternate approach — a weight chart library on every screen, or a server-rendered
image per chart — was rejected: the first breaks the bundle and the floor, the second needs a
rendering service this ephemeral stack does not have.

## 3. Database changes

One new file, additive, no schema change, no RLS change, no column grant.

| File | Change |
|---|---|
| `supabase/postgres-init/61_statistics.sql` | `event_statistics(p_from TIMESTAMPTZ, p_to TIMESTAMPTZ)` and three supporting indexes. |

It is numbered 61 because it needs `calling_organizer()` (55), `claim_code_is_live()` and
`claim_code_grace()` (54), and reads `audit_log` (45). All dependencies are earlier.

Indexes added for the time-bucketed scans (the audit table already has its own):

```sql
CREATE INDEX IF NOT EXISTS scans_created_at_idx        ON scans (created_at);
CREATE INDEX IF NOT EXISTS claimed_rewards_claimed_idx ON claimed_rewards (claimed_at);
CREATE INDEX IF NOT EXISTS participants_registered_idx ON participants (registered_at);
```

**Deployment.** The init scripts run once on an empty volume, so this file will not run on an
existing database: locally it requires `./dev.sh --fresh`, and in production a new deployment
(or a manual `psql -f` of just this file). It is **not applicable to a fair in progress** — the
feature is post-event. The file is purely additive, so applying it by hand to a live database is
safe; it creates a function and three indexes and changes no data.

## 4. Backend and API surface

```sql
CREATE OR REPLACE FUNCTION event_statistics(
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to   TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
```

- Gate: `IF calling_organizer() IS NULL THEN RETURN jsonb_build_object('error','No autorizado');`.
  Mirrors `audit_read` / `event_overview`: no explicit grant, the internal check is the control.
- Filter predicate applied to every source: `(p_from IS NULL OR ts >= p_from) AND
  (p_to IS NULL OR ts <= p_to)`. Both NULL means the whole event.
- No `audit()` call: reading records nothing (R47).
- All sub-aggregates are CTEs feeding one final `SELECT jsonb_build_object(...)`, so they share
  one snapshot.

**Failure shape**

```json
{ "error": "No autorizado" }
```

**Success shape** (abridged; every array is pre-sorted server-side):

```json
{
  "generatedAt": "2026-09-11T22:14:03Z",
  "from": null, "to": null,
  "timezone": "America/La_Paz",
  "callouts": {
    "busiestHour": { "bucket": "2026-09-11T11:00", "scans": 84 },
    "topStandByPoints": { "stand": "IEEE", "points": 4120 },
    "mostHandedOverReward": { "reward": "Sticker", "count": 61 },
    "registeredWithoutScan": 23,
    "standsWithoutScans": [ { "stand": "Robótica", "standNumber": "12" } ]
  },
  "attendance": {
    "timeline": [
      { "bucket": "2026-09-11T10:00", "visits": 40, "activities": 6,
        "activeParticipants": 44, "registrations": 12,
        "pointsAwarded": 960, "pointsSpent": 200, "cumulativePointsAwarded": 960 }
    ],
    "bounds": { "firstScan": "2026-09-11T10:02:11Z", "lastScan": "2026-09-11T18:41:09Z",
                "durationMinutes": 519 }
  },
  "stands": [
    { "id": "…", "name": "IEEE", "standNumber": "3", "withdrawn": false,
      "visits": 120, "activities": 30, "visitPoints": 3600, "activityPoints": 2400,
      "totalPoints": 6000, "totalScans": 150, "avgPoints": 40.0 }
  ],
  "adjustments": { "total": 150, "count": 4,
    "byReason": [ { "reason": "compensación", "amount": 150 } ] },
  "rewards": [
    { "id": "…", "name": "Sticker", "stand": "IEEE", "cost": 50, "withdrawn": false,
      "handedOver": 61, "pointsSpent": 3050, "remaining": 4 }
  ],
  "handoversPerHour": [ { "bucket": "2026-09-11T11:00", "count": 9 } ],
  "participants": {
    "balanceBands": [ { "band": "0", "count": 23 }, { "band": "1-49", "count": 61 } ],
    "standsVisited": [ { "standsVisited": 0, "count": 23 } ],
    "registeredWithoutScan": 23,
    "top": [ { "name": "Ana", "points": 590, "removed": false, "barred": false } ]
  },
  "operations": {
    "refusals": [ { "action": "scan.award", "reason": "…", "count": 37 } ],
    "claimCodes": { "issued": 90, "used": 61, "replaced": 20, "expired": 9 }
  }
}
```

How each spec figure maps to the query:

| Spec | Query |
|---|---|
| R18–R21 timeline | Bucket over the union of `scans`, `participants.registered_at` and `claimed_rewards.claimed_at`; `scans` split by `type`; active = `count(DISTINCT participant_id)`; cumulative = window `sum` of awarded. |
| R22 bounds | `min`/`max` of `scans.created_at`, duration in minutes. |
| R23–R24 stands | `scans` grouped by `community_id`, split by type; `avg` of points; `communities.is_withdrawn` as a label. See section 5, "adjustments". |
| R25 adjustments | `point_adjustments` `sum(amount)`, `count(*)` and grouped by `reason`; never joined into stand awards. |
| R26–R31 rewards | `rewards` LEFT JOIN `claimed_rewards`; `remaining = rewards.stock` (confirmed: the handover decrements it), handed-over = `count`, points spent = `count * cost`, withdrawn as a label; sorted by count and by points. |
| R32 balance bands | `width_bucket(points, 0, 300, 6)`: band 0 = 0 points, bands 1–5 = 50-point ranges, band 6 = 300+. All seven bands are returned even when empty, so the axis is stable. |
| R33 stands visited | `count(DISTINCT community_id)` per participant, then a distribution over 0…N stands. |
| R34 / R35 | `NOT EXISTS` scan count; top 10 by points descending, name ascending. |
| R36 refusals | `audit_log WHERE outcome='refused'` grouped by `(action, reason)`. |
| R37 claim codes | `count(*)`; `closed_reason='used'`; `closed_reason='replaced'`; still open and `NOT claim_code_is_live()` = expired. |
| R38 call-outs | `argmax` over the arrays already built; `registeredWithoutScan`; stands with zero scans. |
| R42 | Zero vs not-applicable: the reward arrays are empty only when no reward was ever published, which the client renders as "not yet applicable" rather than as zero. |

## 5. Frontend changes

| File | Change |
|---|---|
| `src/lib/api.js` | `getEventStatistics({ from, to })` → `supabase.rpc('event_statistics', { p_from: from ?? null, p_to: to ?? null })`, with the shared `errorLegible` wrapper. |
| `src/lib/csv.js` | New, dependency-free `toCsv(columns, rows)` (RFC 4180 quoting) and `downloadCsv(filename, csv)`. |
| `src/lib/csv.test.js` | Unit tests: quoting, embedded commas/quotes/newlines, header-only output. |
| `src/pages/organizer/StatsArea.jsx` | New. Reads on mount and on `onReturnToScreen` (no interval), manual "Actualizar", the global time filter, call-out cards, charts via `react-chartjs-2`, per-figure CSV, explicit empty states, stale-response guard (a `useRef` counter, same pattern as `AuditArea.jsx`). |
| `src/pages/organizer/StatsArea.test.jsx` | Mock `react-chartjs-2` and `api.js`; assert empty states, the read timestamp, and that export is wired. |
| `src/pages/organizer/OrganizerPanel.jsx` | Add `['estadisticas','Estadísticas']` to `AREAS`; `const StatsArea = lazy(() => import('./StatsArea.jsx'))`; render inside `<Suspense fallback={…}>`. |
| `src/index.css` | Chart container heights, call-out grid, filter row — reusing the existing `stat-card` / `glass-card` system. |
| `package.json` | Add `chart.js` and `react-chartjs-2`. |

Routing and access control: no new route. The section is a tab inside the already-guarded panel,
and the guard remains cosmetic — the real control is `calling_organizer()` inside the RPC, which
rejects a stand's or participant's session before any figure is built.

## 6. Test strategy

| Layer | What is covered | Where |
|---|---|---|
| SQL rule tests | Operator-only access (anon, stand, participant each get `No autorizado`); scans-per-hour and the La_Paz bucket boundary; points per stand split by kind; adjustments excluded from stand awards; reward ranking by count and by points; remaining stock; never-handed-over; balance bands and visited distribution; registered-without-scan; refusal grouping; claim-code issued/used/replaced/expired; empty database returns empty arrays and no error; the time filter excludes out-of-range events. | `tests/sql/18_statistics.sql` (new) |
| Frontend unit tests | CSV quoting and header-only output; StatsArea renders explicit empty states and the read timestamp; a stale response cannot overwrite a newer one. | `src/lib/csv.test.js`, `src/pages/organizer/StatsArea.test.jsx` |
| Manual verification | `./dev.sh --fresh`; seed a small event; log in as organizer and open Estadísticas; cross-check two figures against `psql`; export a CSV and open it; sign in as a stand and request `event_statistics` directly, expecting `No autorizado`. | steps in the PR description |

Every business rule in section 5 of the spec is a SQL assertion in `18_statistics.sql`. This
feature spends and awards no points, so no concurrency test is required (contrast the fulfilment
suite).

## 7. Risks and rollback

| Risk | Detection | Mitigation / rollback |
|---|---|---|
| The charting dependency leaks into the participant bundle | Inspect the built chunks; check that the initial bundle size does not jump | The only import site is the lazy `StatsArea`; if it leaks, the fix is local to the import graph. Never reverts the feature. |
| Chart.js needs a runtime API above Chromium 83 | Load the tab in an old browser | ADR 0006 accepts degradation; the other panel tabs must keep working, which they do because the code is in a separate chunk. |
| The aggregate query is slow | Time it on a full-size fixture | At reference scale it is milliseconds; the three indexes cover the time buckets. If needed, index or materialise without changing the response shape. |
| A figure's definition drifts from the home screen's | Compare `pointsAwarded` here against `event_overview` | Both read `SUM(scans.points)` and exclude adjustments; the SQL test pins this. |
| An operator applies the file mid-event | n/a | The file is additive and data-free, so applying it live is safe; no wipe is required for correctness, only for a clean local rebuild. |

Rollback is removing the `Estadísticas` tab and the file. Nothing it did persisted.

## 8. Out of scope for this plan

- Real-time updating, per-stand filtering, and drill-down to individual records — excluded by the
  spec (sections 2 and 4).
- `tasks.md` — the work is one sitting by one person, so the plan is the task list
  (AGENTS.md section 2).
- Per-activity completion figures — requested in the interview's Q4 but not carried into a
  requirement; deliberately absent rather than silently added.
- Any export format other than CSV — R46.
