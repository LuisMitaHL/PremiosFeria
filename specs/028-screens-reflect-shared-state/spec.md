# Spec 028 — Screens reflect shared state

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `028-screens-reflect-shared-state` |
| **Actors** | Participant, Stand admin, Event operator |
| **Created** | 2026-09-11 |
| **Last updated** | 2026-09-11 |

## 1. Purpose

A fair is three groups of people looking at the same state from different screens at the same
time. A community registers a prize at its table; three hundred attendees are holding the
catalogue open. The organiser corrects a price; the stand is looking at that price. None of that
works if a screen only tells the truth at the moment it was opened.

Some screens already refresh themselves — the leaderboard, the attendee's home, the activity
catalogue — because each spec that introduced one said so. The screens nobody said it about do
not, and the result is a reader with no way of telling a current screen from one that is twenty
minutes old. This spec makes it a property of the application rather than a decision repeated per
screen.

## 2. Scope

**In scope**

- Every screen that shows state other people can change.
- When such a screen becomes current again after the device or tab was inactive.
- What a screen does when refreshing fails.

**Out of scope**

- How fast. ADR 0003 settled that: polling, five seconds, absorbed by the CDN microcache. This
  spec does not reopen it.
- Real-time delivery. Still no socket, for the reasons in ADR 0003.
- Screens showing only what the reader themselves just did — a result page, a confirmation.
- The claim screen's own two-second cadence (spec 018), which is about one exchange and is faster
  on purpose.

## 3. User scenarios

### 3.1 A prize registered while the hall is looking

**Given** attendees with the prize catalogue open
**When** a community registers a new prize at its table
**Then** it appears for them without anybody being told to reload.

### 3.2 A price corrected from the organisation desk

**Given** a stand looking at its own prizes
**When** the organiser corrects the cost of one of them
**Then** the stand sees the corrected price, rather than quoting the old one to an attendee.

### 3.3 A phone that was in a pocket

**Given** an attendee who locked their phone with the catalogue open and walked to another stand
**When** they take it out again
**Then** what they see is current, not whatever it was when the screen went dark.

### 3.4 A stand created while the organiser is looking

**Given** the organiser on the communities list
**When** a stand is registered, or an attendee joins, or something reaches the log
**Then** the list they are reading includes it.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | A screen showing state that other people can change MUST reflect those changes without the reader reloading. | Must |
| R2 | Such a screen MUST become current again when the reader returns to it after the tab or the device was inactive. | Must |
| R3 | R1 and R2 MUST hold for: the attendee's prize catalogue, the stand's own prizes, and the organiser's prizes, communities, students and log. | Must |
| R4 | Every screen that refreshes MUST use one shared mechanism, not its own timer. | Must |
| R5 | Refreshing MUST stop when the screen is closed. | Must |
| R6 | A refresh that fails MUST NOT replace what the reader is looking at with an error or an empty screen. | Must |
| R7 | A refresh MUST NOT discard what the reader has typed, chosen or opened. | Must |
| R8 | A refresh MUST NOT change any state; these screens read. | Must |
| R9 | A screen whose content is a list the reader scans line by line MAY refresh only on return, rather than on a timer, where refreshing under their eyes would lose their place. | May |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Cadence | Five seconds, plus on return | ADR 0003. The CDN microcache absorbs the reads, which is what makes the same number safe for every screen rather than only for the leaderboard. |
| One mechanism | Always | Three screens with three timers are three numbers nobody revisits together when one is tuned. The one screen that had its own timer is the one that went stale in a background tab. |
| Returning to the screen | Always refreshes | Browsers throttle timers in background tabs heavily, so a timer alone fails exactly the case that matters: the phone that was in a pocket. This is the half that is easiest to leave out. |
| A failed refresh | Keeps the last good content | The reader is standing at a stand mid-conversation. Replacing a working screen with an error because one poll lost the network is worse than showing content five seconds old. |
| Reading only | Always | A screen that refreshes is a screen that acts on its own. If it could also change something, it would eventually change something nobody asked for. |
| The log | Refreshes on return only | It is read line by line looking for a moment in time; re-sorting it under the reader every five seconds loses their place. Returning to it is when staleness matters. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A refresh fails while the screen is open | The last good content stays; no error replaces it | none |
| A refresh fails on the first load | The screen says it could not load, because there is no last good content | the screen's own error |
| The reader has a form half filled | The refresh updates the list behind it and leaves the form alone | none |
| The reader has a detail panel open | It stays open, showing refreshed content | none |
| The screen is closed mid-request | The result is discarded; nothing is written to a screen that is gone | none |
| The tab is in the background for an hour | On return, the screen is current before the reader reads it | none |
| Two refreshes overlap | The later answer wins, never an earlier one arriving late | none |

## 7. Security and integrity

- **Refreshing reads and nothing else (R8).** Every screen here calls the same functions it used
  to populate itself. None of them gains a capability by being repeated.
- **Identity is resolved per request, not cached at mount.** A screen that refreshes for an hour
  must not keep answering for whoever was signed in when it opened; each read resolves the caller
  from the session exactly as a first read does.
- **Refreshing does not widen what a reader can see.** The organiser's screens refresh through the
  organiser's own functions, which refuse anyone else; a stand's screens refresh through
  `calling_community()`. A stale screen and a fresh one show the same rows to the same person.

## 8. Acceptance criteria

- [x] A prize registered at a stand appears in the attendee's catalogue without a reload.
- [x] A price corrected by the organiser appears on the stand's own prize list without a reload.
- [x] A community, a student and a log entry each appear on the organiser's lists without a reload.
- [x] A screen left in a background tab is current when the reader returns to it.
- [x] Closing a screen stops its refreshing.
- [x] A failed refresh leaves the content that was already on screen.
- [x] A refresh does not clear a half-filled form or close an open panel.
- [x] No screen in this spec writes anything.

## 9. Open questions

None. One decision is recorded rather than left implicit: the log refreshes on return only (R9),
because it is read by scanning for a moment in time, and re-ordering it under the reader costs more
than the staleness does.

## 10. Current behaviour and the gap

| Screen | Before this spec |
|---|---|
| Leaderboard, attendee's home | Refresh on a timer and on return, through `startPolling`. |
| Attendee's activities | Refreshed on a timer only — its own `setInterval`, not the shared helper — so a backgrounded tab went stale and returning to it did not help. |
| Attendee's prize catalogue | **Loaded once.** A prize registered while it was open never appeared. |
| Stand's own prizes | Reloaded after the stand's own action only. A price the organiser corrected was invisible to the stand quoting it. |
| Organiser's prizes, communities, students | **Loaded once.** |
| Organiser's log | **Loaded once.** |

**Consequences the plan must address**

- The mechanism exists (`startPolling`) and is already the one ADR 0003 describes. This is not a
  new capability; it is applying the existing one where it was never applied.
- A refresh that replaced content with an error on a lost packet would make several screens worse,
  not better. Failure handling is the part of this that has to be right.
- The organiser's screens hold open panels and half-filled forms. Refreshing a list underneath them
  must not reset them.

## 10b. As built

`startPolling` already existed and already did the right thing; it had simply never been applied to
six of the screens that needed it. The change is five lines per screen, and almost all the thought
went into the two rules that are easy to get wrong.

**Returning to the screen is now the whole of `startPolling`'s second half.** It used to add its
listeners itself; `onReturnToScreen` is that half extracted, so a screen can take it alone. Both
now ignore `visibilitychange` when the page is being *hidden* — the event fires in both directions,
and re-reading at the moment somebody leaves is a request nobody will look at.

**A failed refresh is silent (R6).** Each screen keeps a flag for whether it has ever loaded
successfully, and reports an error only while it has nothing to show. Verified by stopping
PostgREST for nine seconds — two failed polls — with the catalogue and the organiser's panel open:
both kept their content, neither showed an error, and both were current again once it came back.

**A refresh leaves the reader's work alone (R7).** The lists and the things the reader is editing
live in separate state, so a list updating underneath a half-filled form or an open detail panel
does not touch either. Verified with a community form half typed across two refresh cycles,
including across the outage above.

**The activity catalogue moved to the shared helper (R4).** It had its own `setInterval`, which is
exactly why it behaved differently: a private timer never learns that the tab came back, and
browsers throttle timers hard in background tabs, so a phone that had been in a pocket showed
activities from whenever it went dark. It was the one screen that looked like it refreshed and did
not.

**The log refreshes on return only (R9).** It is the one screen here read line by line, looking for
a moment in time; re-sorting it under the reader every five seconds would cost more than the
staleness does.

**Verified in the browser end to end:** with the attendee's catalogue open and untouched, a stand
registered a prize and it appeared; with the organiser's prize list open, another appeared. Both
without a reload, which is the defect that prompted this spec.

## 11. References

- ADR 0003 — polling instead of realtime, and the five seconds this spec reuses.
- Constitution: IV (identity is never a parameter).
- Spec 007 — `live-leaderboard`, the first screen to refresh itself and the origin of the helper.
- Spec 013 — `participant-dashboard`, whose R10 asked for the same thing on the attendee's home.
- Spec 025 — `participant-activity-progress`, whose R11 asked for it on the activity catalogue.
- Spec 018 — `in-person-reward-fulfilment`, whose claim screen keeps its own faster cadence.
- Spec 021 — `stand-reward-management`, whose edge-case table already assumed a catalogue that
  refreshes, which is the assumption this spec makes true.
