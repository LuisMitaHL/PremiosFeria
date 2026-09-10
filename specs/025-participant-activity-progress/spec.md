# Spec 025 — Participant activity progress

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `025-participant-activity-progress` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Spec 019 gives stands activities with schedules, durations and a moment when they actually begin.
None of that reaches the person it was written for. An attendee standing in the middle of the hall
has no way to know that a workshop started four minutes ago two stands away, that the thing they
wanted to do is over, or that they have completed everything one community had to offer.

This is the screen that answers "what can I do right now". It puts what is happening at the top,
what is coming next below it, and what has already passed at the bottom — and marks what this
attendee has already done, so the fair becomes something with a visible amount left in it rather
than a room to wander around.

## 2. Scope

**In scope**

- A destination in the attendee's navigation dedicated to activities.
- Every activity of every stand, and how they are ordered.
- What each one shows, including which the attendee has already completed.
- How activities that are unavailable are presented.

**Out of scope**

- Creating, starting and finishing activities, and everything about their lifecycle. Spec 019.
- What an activity is worth. Spec 020.
- Scanning. Specs 002 and 003 are unchanged; this screen tells an attendee where to go, it does
  not award anything.
- The summary of activities on the home screen. Spec 013.

## 3. User scenarios

### 3.1 Deciding where to go next

**Given** an attendee who has just finished at one stand
**When** they open the activities screen
**Then** the first thing they see is what is running right now, at which stands, and they can walk
straight there.

### 3.2 Planning ahead

**Given** nothing is running at this moment
**When** the attendee looks at the screen
**Then** they see what is expected next and roughly when, and can decide whether to wait nearby or
keep walking.

### 3.3 Seeing what is left

**Given** an attendee who has been at the fair for two hours
**When** they look down the list
**Then** they can tell which activities they have already completed and which they have not, at a
glance, without opening anything.

### 3.4 Arriving too late

**Given** an activity that finished ten minutes ago
**When** the attendee looks for it
**Then** it is still there, at the bottom, plainly marked as over. It does not disappear, which
would be indistinguishable from it never having existed.

### 3.5 A stand that is not there

**Given** a community the organiser withdrew
**When** the attendee looks at the list
**Then** its activities are shown as unavailable rather than as something to walk towards.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The attendee's navigation MUST offer a destination dedicated to activities, alongside the existing ones. | Must |
| R2 | The screen MUST show the activities of every stand in the fair, not only those of stands the attendee has visited. | Must |
| R3 | Activities MUST be ordered by state: those running now first, then those not yet started, then those finished. | Must |
| R4 | Within those not yet started, activities MUST be ordered by their estimated start time. | Must |
| R5 | Each activity MUST show which stand it belongs to, its name, its description and its duration. | Must |
| R6 | An activity that has not started MUST show its estimated start time. | Must |
| R7 | An activity that is running MUST be distinguishable from every other state without reading the text. | Must |
| R8 | An activity the attendee has already completed MUST be marked as completed, in every state. | Must |
| R9 | A finished activity MUST remain listed, marked as over. | Must |
| R10 | An activity belonging to a withdrawn community MUST be shown as unavailable, and MUST NOT appear as something to go to. | Must |
| R11 | The screen MUST reflect an activity starting or finishing without the attendee reloading it. | Must |
| R12 | The screen MUST NOT award anything, and MUST NOT be a route to awarding anything. | Must |
| R13 | With no activities published anywhere in the fair, the screen MUST say so plainly rather than appear broken. | Must |
| R14 | An activity the attendee cannot act on — not started, finished, unavailable, or already completed — MUST NOT invite them to act on it. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Ordering | Running, then upcoming, then finished | The screen answers one question — what can I do now — and the order is the answer. Any other arrangement makes the attendee search for the only rows that are actionable. |
| Upcoming order | By estimated start time | It is the only ordering an attendee can act on, even though the estimate is not binding (spec 019, R27). |
| Finished activities | Stay listed | An activity that vanishes when it ends is indistinguishable from one that never existed, and an attendee who misses something should be able to see that they missed it. |
| Scope of the list | The whole fair | The point of the screen is to send someone to a stand they have not been to. Limiting it to stands already visited would defeat it. |
| Freshness | Reflects state changes without a reload | The whole value of "running now" is that it is true now. The system has no realtime (ADR 0003), so this follows the same polling approach the leaderboard uses. |
| Awarding | Never from this screen | Points come from scanning a code at the stand. A screen that could complete an activity would let an attendee complete one from across the hall. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| No activities published anywhere | The screen says so plainly | "Todavía no hay actividades publicadas." |
| Nothing is running right now | The running section says so; upcoming activities still show | "Ninguna actividad en curso." |
| An activity starts while the attendee is looking | It moves to the top without a reload | none |
| An activity finishes while the attendee is looking | It moves to the finished group without a reload | none |
| An activity the attendee already completed is running | Shown as running and marked completed; not presented as something to do | none |
| Every activity of a stand is completed | That stand's activities are all marked completed | none |
| A community is withdrawn while the attendee is looking | Its activities become unavailable on the next refresh | none |
| An activity has no attendees and simply ends | Shown as finished like any other | none |
| The attendee has no session | The screen is not reachable, like every other attendee screen | none |

## 7. Security and integrity

This screen only reads, which is the whole of its security story — and the part worth stating.

- **It shows what is public.** Stands, their activities and their states are visible to every
  attendee by design; there is nothing here that one attendee should not see.
- **Except for one thing that is theirs (R8).** Which activities *this* attendee has completed is
  their own history. It must be derived from their own session, never from an identifier the
  screen supplies, and the screen must not be able to ask about somebody else's.
- **It awards nothing (R12).** Points come from a signed code scanned at the stand, validated in
  the database. This screen must not become a second path: no action on it may complete an
  activity, and a request originating from it may not be treated differently from any other.
- **State comes from the database, not the clock (R11).** Whether an activity is running is a
  question the database answers (spec 019, R19). This screen must display that answer, never
  compute its own from a start time and a duration — a phone with a wrong clock would otherwise
  show a finished activity as open and send someone across the hall for nothing.

## 8. Acceptance criteria

- [ ] The attendee's navigation offers an activities destination.
- [ ] The screen lists activities from every stand, including stands never visited.
- [ ] Running activities appear first, then those not started, then those finished.
- [ ] Activities not yet started are ordered by estimated start time.
- [ ] Each activity shows its stand, name, description and duration.
- [ ] An activity not yet started shows its estimated start time.
- [ ] A running activity is distinguishable without reading the text.
- [ ] Activities the attendee completed are marked as such in every state.
- [ ] Finished activities remain listed and are marked as over.
- [ ] Activities of a withdrawn community are shown as unavailable.
- [ ] An activity starting or finishing is reflected without a reload.
- [ ] Nothing on this screen awards points, including through the API.
- [ ] One attendee cannot see which activities another has completed.
- [ ] With no activities published, the screen says so and does not appear broken.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Nothing in this spec exists, because activities do not exist. Spec 019 creates them.

| Concern | Today |
|---|---|
| Navigation | Four destinations: Inicio, Ranking, Scan, Premios (`src/App.jsx`). A fifth is added here. |
| Activities | Not modelled. `scans.type` distinguishes a visit from an activity and nothing more. |
| What an attendee sees of stands | The home screen lists stands with a mark for those visited (`src/pages/Dashboard.jsx`). That is the closest thing to this screen and it is not close. |
| Freshness | Only the leaderboard refreshes on its own, by polling every 5 seconds (`src/lib/api.js`). |

**Consequences the plan must address**

- A fifth destination in a bottom navigation bar sized for four. On a narrow phone this is the
  practical limit, and the labels have to survive it.
- The screen needs each activity's state and whether this attendee completed it, for the whole
  fair, in one read — not one request per stand.
- It introduces the third polling loop in the system, after the leaderboard and the claim screen
  of spec 018. The plan should say whether they share a mechanism.
- Ordering by state means the order changes underneath the attendee as activities start and
  finish. That has to be handled without a row moving under a finger.

## 10b. As built

`src/pages/Activities.jsx`, a fifth destination in the attendee's navigation. Three groups in a
fixed order — running, then upcoming by estimated time, then finished — plus a fourth for the
activities of a withdrawn community. The state always comes from `activity_state`, computed in the
database: a phone with a wrong clock would otherwise show a finished activity as open and send
somebody across the hall for nothing.

**A process deviation worth recording.** This was implemented from an approved spec with **no
`plan.md`**, and the work was delegated. The rule written a few hours earlier says a plan is
optional only when one person does the work in one sitting; this was neither. The spec was detailed
enough that nothing was lost, but the exemption was applied where it did not hold.

**A gap the work exposed.** The acceptance criterion "one attendee cannot see which activities
another has completed" was **not met**, and could not be met from the screen: `scans` carried
`USING (true)`, so anyone holding the publishable key could read any attendee's whole route — where
they went, when, and what they took part in. Fixed by scoping the policy to the scan's own
participant and the stand that awarded it, with an assertion in `tests/sql/06` that goes red
without it.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter).
- ADR 0003 — polling instead of realtime.
- Glossary: *Activity*, *Stand*, *Participant*.
- Spec 019 — `stand-activity-catalogue`, which defines everything this screen displays.
- Spec 020 — `fixed-points-model`, which prices what completing one is worth.
- Spec 013 — `participant-dashboard`, which summarises this screen on the home screen.
- Spec 023 — `organizer-community-management`, whose withdrawal R10 reflects.
