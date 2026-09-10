# Plan 017 — Organizer admin panel

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Rules in the database | Yes | Every figure on the home screen is computed by one function; the panel draws what it returns. |
| IV — Identity is never a parameter | Yes | A third identity, resolved from `auth.uid()` like the other two. Access is refused where the data is served, not by hiding a route. |
| V — Secrets never reach the client | Yes | The organiser's credentials are generated at deployment and never leave the operator's file. The panel ships in the public bundle, so nothing in it is a secret. |
| VI — Defence in depth | Yes | The organiser cannot award points or confirm a handover; that is enforced by not existing, not by a hidden button. |
| IX — Quality gates | Yes | New SQL suite for access. |

## 2. Approach

**A separate table, not a flag on `communities`.** An organiser is not a stand, and putting them in
the same table makes it one `UPDATE` away from a stand that can create stands. `organizers` has one
row, created at first database start from an environment variable the deploy script generates.

The auth service learns a second login path. `stand_login` stays untouched; `organizer_login` is
its mirror against the new table. Keeping them separate is what stops a stand ever authenticating
as an organiser or the reverse — one function, one table, one kind of caller.

The token carries `role: authenticated` like every other, and `user_metadata.organizer: true` for
the client to route on. **That flag decides nothing**: every organiser function resolves the
organiser from `auth.uid()` against the table.

## 3. Database changes

| File | Change |
|---|---|
| `20_schema.sql` | `organizers (id, username UNIQUE, password_hash, auth_user_id UNIQUE, created_at)` |
| `40_rls.sql` | RLS on, **no policy at all** — like `settings` and `claim_codes`. Nothing client-side reads it |
| `55_organizer.sql` (new) | `organizer_login(username, password)`, `calling_organizer()`, `event_overview()` |
| `71_organizer_seed.sql` (new) | Creates the single organiser from `ORGANIZER_USERNAME` / `ORGANIZER_PASSWORD`, hashed with bcrypt cost 12. **Fails the boot loudly if unset**, rather than starting an event nobody can administer |
| `80_column_grants.sql` | Add `password_hash` on `organizers` to the secret list |

`event_overview()` returns one object with every figure the home screen shows, computed in the
database: participants, points awarded, points spent, rewards handed over, stock remaining,
activities running now, the most expensive published reward, and the maximum a diligent attendee
could earn. One read rather than a browser assembling six.

The maximum is computed, never stored: `stands × (visit + activities published)`, using the
constants from `points_config()`.

## 4. Auth service and deployment

| File | Change |
|---|---|
| `auth/server.mjs` | `POST /token` tries `stand_login`, then `organizer_login`. Same uniform failure, same rate limit — an organiser username must not be distinguishable from a stand's by the response |
| `deploy-keys.sh` | Generates `ORGANIZER_USERNAME` and a strong `ORGANIZER_PASSWORD` into `.env.prod`, mode 600 |
| `docker-compose.yml` | Passes both to the database at init |
| `dev.sh` | A known local organiser, printed with the other demo credentials |

## 5. Frontend

| File | Change |
|---|---|
| `src/pages/organizer/OrganizerLogin.jsx` | Its own address, linked from nowhere |
| `src/pages/organizer/OrganizerPanel.jsx` | The shell: navigation to four areas, sign-out on every screen, and the home screen |
| `src/App.jsx` | Routes under `/organizador`. **No link from any attendee or stand screen** |
| `src/lib/AuthContext.jsx` | An organiser session alongside the other two |

The four areas are placeholders until specs 022, 023 and 024.

## 6. Test strategy

`tests/sql/13_organizer_access.sql`: a stand's session cannot call an organiser function; a
participant's cannot; no client role can read `organizers` or its hash; `organizer_login` refuses a
stand's credentials and vice versa; a failed login is indistinguishable from an unknown user;
`event_overview` returns zeroes rather than failing on an empty event, and its figures match hand
-counted fixtures.

## 7. Risks

- **The panel ships in the public bundle.** Anyone can read its code. Nothing in it may be the
  enforcement — every screen must be useless without the session the database checks.
- A single shared account means the log cannot name a person (spec 024). Accepted, recorded.
- Failing the boot when the organiser variables are unset is deliberate: the alternative is an
  event that starts and cannot be administered, discovered on the day.

## 8. Out of scope

What the organiser can actually do: specs 022, 023, 024, and the reward powers spec 021 deferred.
