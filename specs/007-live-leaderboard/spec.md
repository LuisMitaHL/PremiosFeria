# Spec 007 — Live leaderboard

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `007-live-leaderboard` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 (open question resolved) |

## 1. Purpose

Points only matter because somebody else has more of them. The leaderboard is what turns walking
around a fair into a competition: an attendee scans a stand, opens this screen, and sees whether
it moved them. It is the reason the last two stands get visited.

It has to be current enough to feel alive without pretending to be instant, and it has to survive
three hundred phones looking at it at once — on a stack deliberately built without a realtime
service.

## 2. Scope

**In scope**

- The ordering of participants by points, and what each row shows.
- The podium, and why the top three are treated differently.
- Finding yourself in it.
- How current it is, and how that is achieved without a realtime service.

**Out of scope**

- Earning points. Spec 020.
- The attendee's own progress and figures. Spec 013.
- Whether a removed or restricted participant appears here. Spec 022 introduces those states; the
  question is open, see section 9.

## 3. User scenarios

### 3.1 Checking a scan landed

**Given** an attendee who has just been awarded points at a stand
**When** they open the leaderboard
**Then** within a few seconds their position reflects it, without them reloading anything.

### 3.2 Finding yourself

**Given** an attendee somewhere in the middle of a long list
**When** they look at the leaderboard
**Then** their own row is marked, so they do not have to read names to find it.

### 3.3 The top of the fair

**Given** the leaderboard open on any phone
**When** an attendee looks at it
**Then** the top three are presented as a podium, distinct from the list beneath.

### 3.4 Coming back to it

**Given** an attendee who put their phone in a pocket ten minutes ago with the leaderboard open
**When** they take it out again
**Then** what they see is current, not ten minutes stale.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | Participants MUST be listed in descending order of points. | Must |
| R2 | Every registered participant MUST appear, not only the top of the list. | Must |
| R2a | A participant removed from the event MUST NOT appear. | Must |
| R2b | A participant whose claiming is withheld MUST still appear, unchanged. | Must |
| R3 | The top three MUST be presented distinctly from the rest. | Must |
| R4 | Each row MUST show the participant's nickname and their points. | Must |
| R5 | The attendee's own row MUST be marked so they can find it without reading. | Must |
| R6 | The leaderboard MUST update without the attendee reloading the page. | Must |
| R7 | It MUST become current again when the attendee returns to it after the screen or the tab was inactive. | Must |
| R8 | Updating MUST NOT require a persistent connection to the server. | Must |
| R9 | The load of many attendees watching at once MUST NOT reach the database once per viewer. | Must |
| R10 | Refreshing MUST stop when the attendee leaves the screen. | Must |
| R11 | With no participants registered, the screen MUST say so rather than appear broken. | Must |
| R12 | The leaderboard MUST NOT expose anything about a participant beyond what it displays: the request itself MUST ask only for the nickname and the points. | Must |
| R13 | Nothing on this screen MUST change anything. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Refresh interval | 5 seconds | The attendee glances at this between stands; a few seconds of staleness is invisible to them and removes the need for a whole service. Faster would cost more and change nothing they can perceive. |
| Refresh on returning | Always | A phone coming out of a pocket showing a ten-minute-old board is worse than one showing nothing, because it looks current. |
| How it stays fresh | Asking again, not being told | A realtime service is a second stateful component to run and keep alive through a CDN, for one screen that does not need to be instant. See ADR 0003. |
| Absorbing the load | Cached briefly in front of the database | Three hundred phones asking every five seconds is three hundred queries per window if nothing sits in front. A short-lived cache collapses that to roughly one, which is what makes the interval affordable. |
| Everyone appears | Every participant still in the event | A cut-off list tells most attendees nothing about themselves, and they are the majority of the audience. Someone removed from the event is no longer in it, and should not hold a place on a screen projected to the hall. |
| Withheld claiming | Does not affect the leaderboard | The sanction is on spending, not on earning. Someone with an unfortunate nickname still walked the fair, and the board records what happened. |
| Ties | Not broken deliberately | Two attendees on the same points are equal, and any tiebreak — who got there first, alphabetical — would be arbitrary and invisible. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| Nobody has registered yet | The screen says so | "Todavía no hay participantes." |
| Fewer than three participants | The podium shows who exists, without empty places | none |
| Several attendees have the same points | They appear together, in whatever order the data gives; no tiebreak is invented | none |
| The attendee has zero points | They appear at the bottom, marked as themselves | none |
| The list is long | It remains readable and scrollable on a phone | none |
| The network drops | The last known board stays on screen and refreshing resumes when the network returns | none |
| The attendee leaves the screen | Refreshing stops | none |
| A participant registers while the board is open | They appear on the next refresh | none |
| A participant is removed while the board is open | They disappear on the next refresh, and the positions below them move up | none |
| A participant whose claiming is withheld | Appears normally, indistinguishable from anyone else | none |

## 7. Security and integrity

The leaderboard is the most public surface an attendee sees, and it is built on a table that is
readable by everyone.

- **Only what is displayed should be exposed (R12).** The participant table is world-readable by
  design, so the leaderboard can be public. That makes what is *requested* the boundary: asking
  for whole rows hands every reader every column, including the device identity used for recovery
  (spec 001) — which nobody but the owner and the organiser has any business seeing.
- **It changes nothing (R13).** No action here awards, spends or alters anything. It is a read.
- **Position is not authority.** Nothing in the system may depend on a participant's rank; it is a
  view over points, and points are decided elsewhere.
- **Refreshing must stop when the screen does (R10).** A loop that outlives its screen becomes
  three hundred phones asking forever, and it is a bug that only appears at scale, on the day.

## 8. Acceptance criteria

- [ ] Participants appear in descending order of points.
- [ ] Every registered participant appears.
- [ ] The top three are presented distinctly.
- [ ] Each row shows a nickname and a points total.
- [ ] The attendee's own row is marked.
- [ ] A new award is reflected within a few seconds without reloading.
- [ ] Returning to the screen after it was inactive shows current data.
- [ ] No persistent connection is opened.
- [ ] Refreshing stops when the attendee leaves the screen.
- [ ] With no participants, the screen explains rather than appearing broken.
- [ ] The data fetched contains nothing that is not displayed: no device identity, no timestamps.
- [ ] A removed participant does not appear, and the positions below them close up.
- [ ] A participant whose claiming is withheld appears exactly as anyone else does.
- [ ] Nothing on the screen changes any state.

## 9. Open questions

None. The question raised while writing this spec — what the participant states introduced by
spec 022 mean for this screen — was resolved: **a removed participant does not appear** (R2a),
while one whose claiming is withheld appears unchanged (R2b).

## 10. As-built notes

| Requirement | Implemented in |
|---|---|
| R1 | `src/lib/api.js`, `getLeaderboard` — ordered by points, descending. |
| R2, R3, R4, R5 | `src/pages/Leaderboard.jsx` — a podium reordered as second, first, third, then the full list with coloured medals, initials as avatars, and a "Tú" badge on the attendee's own row. |
| R6, R7, R8 | `src/lib/api.js:259-270`, `startLeaderboardPolling` — a 5-second interval plus refetches on `focus` and `visibilitychange`, consumed at `src/pages/Leaderboard.jsx:25`. No socket. |
| R9 | Not in this repository: `nginx-cdn.conf.example` microcaches `GET` responses under `/rest/v1/` for 5 seconds, with a herd lock. |
| R10 | The effect's cleanup clears the interval and the listeners. |
| R13 | The screen only reads. |

**Known deviations**

- **R12 is not met.** `getLeaderboard` selects every column of every participant, which includes
  `fingerprint` and `registered_at`. Anyone with the public key can read them, and the display
  uses only the nickname and the points. This matters more after spec 001, which makes the device
  identity half of the key that recovers a profile. **Fixed ahead of the rest of this spec, since
  it is a privacy defect in shipped code rather than a change of behaviour.**
- R2a and R2b cannot be met until spec 022 introduces the states they refer to.
- `src/pages/Leaderboard.jsx:35` computes a slice of the list that is never rendered — dead code
  that spec 016 removes.
- R9 depends entirely on a CDN configuration this repository only provides as an example. If it is
  misconfigured, the full polling load reaches Postgres directly.

## 11. References

- ADR 0003 — polling instead of realtime, which this screen is the reason for.
- Constitution: IV (identity is never a parameter).
- Glossary: *Leaderboard*, *Points*, *Participant*.
- Spec 001 — `participant-registration`, whose device identity R12's deviation exposes.
- Spec 013 — `participant-dashboard`, which shows the attendee their own figures.
- Spec 022 — `organizer-student-management`, which owns the open question in section 9.
- Spec 016 — `naming-and-hygiene-cleanup`, which removes the dead code noted above.
