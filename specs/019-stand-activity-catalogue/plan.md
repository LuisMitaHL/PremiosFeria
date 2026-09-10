# Plan 019 — Stand activity catalogue

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Ships with** | Spec 020 — one deployment, one schema change |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Business rules live in the database | Yes | The whole lifecycle — start, finish, the limit of three, one running at a time — is enforced in RPC and constraints. The stand's screen only draws it. |
| IV — Identity is never a parameter | Yes | Every action resolves the owning stand from `auth.uid()`; no RPC takes a stand identifier as a claim of who is calling. |
| V — Secrets never reach the client | Yes | Activity codes are signed by `sign_scan_code` as before. |
| VI — Defence in depth | Yes | The limit of three, one main event, one running at a time and one completion per activity are all constraints or conditional writes. See section 3. |
| VII — Chromium 83 target | Yes | New screens use the same plain React and CSS as the rest. |
| IX — Quality gates | Yes | A new SQL suite for the lifecycle. |

## 2. Approach

An activity's state is **derived, never stored as a status column**. A row holds `started_at` and
`finished_at`; the state follows:

```
started_at IS NULL                                    -> scheduled
started_at IS NOT NULL, not yet ended                 -> running
finished_at IS NOT NULL, or the duration has elapsed  -> finished
```

"The duration has elapsed" is `now() >= started_at + duration`. This is what makes R10 — finishing
automatically, with nothing running — true without a scheduler, a job or an open browser. Nothing
in this stack runs on a timer, so a stored status would need something to change it, and an
activity nobody closed would keep awarding points all day.

A `SQL` function `activity_state(activities)` returns the state, so the RPC, the stand's screens and
the attendee's screen cannot disagree about what "running" means.

The alternative — a `status` column updated by whoever notices — was rejected for exactly the reason
above.

## 3. Database changes

Requires a wipe, together with spec 020. **Cannot be applied during an event.**

New table in `20_schema.sql`:

```
activities
  id              UUID PK
  community_id    UUID NOT NULL REFERENCES communities ON DELETE CASCADE
  name            TEXT NOT NULL  CHECK (char_length(btrim(name)) BETWEEN 3 AND 40)
  description     TEXT NOT NULL  CHECK (char_length(btrim(description)) <= 100)
  estimated_start TIME NOT NULL
  duration_min    INT  NOT NULL  CHECK (duration_min BETWEEN 1 AND 60)
  is_main_event   BOOLEAN NOT NULL DEFAULT false
  started_at      TIMESTAMPTZ
  finished_at     TIMESTAMPTZ
  created_at      TIMESTAMPTZ DEFAULT now()
  CHECK (finished_at IS NULL OR started_at IS NOT NULL)   -- cannot end what never began
```

The structural guarantees, each an index rather than an `IF`:

| Rule | Guarantee |
|---|---|
| At most 3 per stand, ever | `CHECK` cannot count rows. A `BEFORE INSERT` trigger counting with `FOR UPDATE` on the owning community row — the lock is what makes two simultaneous inserts serialise |
| At most one main event | Partial unique index on `(community_id) WHERE is_main_event` |
| At most one running | Partial unique index on `(community_id) WHERE started_at IS NOT NULL AND finished_at IS NULL` — combined with the derived state, an activity past its duration is finished but still occupies this index, so it must be closed before another starts. **See the risk in section 7.** |
| One completion per activity | Spec 020's `scans_one_completion_per_activity` |

RLS: `activities` readable by everyone (the attendee's screen lists the whole fair); no client
INSERT or UPDATE policy at all — every write goes through an RPC, exactly as `scans` does.

New RPC in a new `52_activities.sql`:

| Function | Does |
|---|---|
| `create_activity(name, description, estimated_start, duration_min, is_main_event)` | Owning stand from `auth.uid()`; enforces the limit and the main-event rule; returns the row or a reason |
| `update_activity(id, ...)` | Refuses unless the activity is still scheduled and belongs to the caller |
| `start_activity(id)` | Refuses if not scheduled, not owned, or another is running |
| `finish_activity(id)` | Refuses if not running or not owned |
| `activity_state(activities)` | The derived state, used everywhere |

`sign_scan_code` gains an activity argument and refuses to sign one that is not running.
`validate_and_scan` resolves the activity from the payload and refuses with the state's own reason.

## 4. Frontend changes

| File | Change |
|---|---|
| `src/pages/admin/AdminDashboard.jsx` | Becomes a shell with three sections: Actividades, Premios, Canjes. The profile editing it has today moves out entirely (spec 023 gives it to the organiser). Rewards and claims are placeholders until specs 021 and 018 |
| `src/pages/admin/ActivitiesSection.jsx` | New. Cards per activity with its state, and the action its state allows: start, show code, finish. The create form, disabled at three |
| `src/lib/api.js` | `getActivitiesForCommunity`, `getAllActivities`, and the four RPC wrappers |

## 5. Test strategy

| Layer | What is covered | Where |
|---|---|---|
| SQL | The full lifecycle: create, the limit of three including after finishing, one main event, start, automatic finish by elapsed duration, finish early, no reopening, no second running, no editing once started | `tests/sql/09_activity_lifecycle.sql` |
| SQL | Concurrency: two simultaneous creates at the limit; two simultaneous starts | same file |
| SQL | Awarding only while running, by camera and by manual code | `tests/sql/10_activity_awards.sql` |
| Frontend | Nothing that a SQL test does not cover better; the screens are thin | — |
| Manual | Create three activities, start one, watch it expire, try a fourth | Chrome DevTools against `./dev.sh` |

Automatic finishing is tested by moving `started_at` into the past — the same technique the cooldown
tests already use — never by waiting.

## 6. Risks and rollback

- **The one-running index and automatic finishing interact.** An activity past its duration is
  *finished* by the derived state but still matches `started_at IS NOT NULL AND finished_at IS NULL`.
  Left alone, a stand could not start a second activity until it closed the first, which contradicts
  R10. `start_activity` therefore closes any expired activity of that stand before it checks. This
  is the subtlest part of the change and gets its own test.
- **Codes are invalidated** by the payload change. Deployment only.
- Rollback is a redeploy plus a wipe.

## 7. Out of scope for this plan

The attendee's activities screen (spec 025), the projection screen's rework (spec 011), and the
other two sections of the stand console (specs 021 and 018). This plan builds the entity, its rules
and the stand's activities section.
