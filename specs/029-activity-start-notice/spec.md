# Spec 029 — Activity start notice

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `029-activity-start-notice` |
| **Actors** | Participant |
| **Created** | 2026-09-11 |
| **Last updated** | 2026-09-11 |

## 1. Purpose

An activity is worth points only while it is running, and it runs for half an hour somewhere in a
hall with ten stands. An attendee looking at the leaderboard has no way of knowing that a workshop
two tables away just opened its doors. Today the only way to find out is to navigate to the
activity screen and read it.

This spec puts a notice on the attendee's screen when an activity starts, so that the thing they
could go and do finds them rather than waiting to be looked up.

It is **not** a notification system. Nothing is delivered to a phone whose app is closed, nothing
is stored on the server, and nothing is registered with the browser or the operating system. It is
a component that appears in the running application, and the spec is deliberate about not letting
it be mistaken for more than that.

## 2. Scope

**In scope**

- A notice that appears on the attendee's screen when an activity starts.
- Which activities produce one, and which deliberately do not.
- What the attendee can do with it, and how it goes away.
- Not repeating a notice the attendee has already been shown.

**Out of scope**

- Real notifications: the Push API, the Notifications API, service-worker delivery, e-mail, or
  anything that reaches a closed application. Explicitly rejected; see section 5.
- Notifying stands or the organiser. Their screens already refresh (spec 028) and they are the
  ones causing the changes.
- Any new state on the server. The activity lifecycle is derived (spec 019) and this spec adds
  nothing to it.
- Notices for prizes, points or leaderboard positions.

## 3. User scenarios

### 3.1 A workshop opens two tables away

**Given** an attendee with the application open on any of their screens
**When** a stand starts its activity
**Then** a notice appears naming the activity and the stand, and tapping it takes them to the
activity list.

### 3.2 The same activity, twice

**Given** an attendee who has already been shown that MEH started its workshop
**When** their screen refreshes again, or they close the application and come back
**Then** they are not shown it a second time.

### 3.3 Something they have already done

**Given** an attendee who already scanned the code for that workshop
**When** the workshop is still running
**Then** they are not told to go to it.

### 3.4 Arriving late

**Given** an attendee who opens the application at four in the afternoon
**When** two activities have been running since before they opened it
**Then** they are told about them — they have not seen them, and both are still something they can
go and do.

## 4. Requirements

### When one appears

| ID | Requirement | Priority |
|---|---|---|
| R1 | An activity that is running MUST produce a notice on the attendee's screen. | Must |
| R2 | An activity that has been created but not started MUST NOT produce one. | Must |
| R3 | An activity that has finished MUST NOT produce one. | Must |
| R4 | An activity belonging to a withdrawn community MUST NOT produce one. | Must |
| R5 | An activity the attendee has already completed MUST NOT produce one. | Must |
| R6 | An attendee MUST be shown a given activity's notice at most once on a device. | Must |
| R7 | If several activities are owed a notice at the same time, they MUST be shown one after another rather than at once. | Must |

### What it says and does

| ID | Requirement | Priority |
|---|---|---|
| R8 | The notice MUST name the activity and the stand it belongs to. | Must |
| R9 | The notice MUST say that the activity is running now, not that it exists. | Must |
| R10 | The notice MUST distinguish a main event from an ordinary activity, because they are worth different amounts. | Should |
| R11 | Acting on the notice MUST take the attendee to the activity list. | Must |
| R12 | The notice MUST be dismissable, and MUST also go away on its own. | Must |
| R13 | The notice MUST NOT cover the navigation or whatever the attendee is in the middle of doing. | Must |

### Where it appears

| ID | Requirement | Priority |
|---|---|---|
| R14 | Notices MUST appear only on the attendee's screens. | Must |
| R15 | Notices MUST NOT appear on the stand console, the projected code screen, or the organiser's panel. | Must |
| R16 | Notices MUST NOT appear before the attendee has a profile. | Must |

### What it is not

| ID | Requirement | Priority |
|---|---|---|
| R17 | Nothing in this spec MUST request permission to send notifications, register a push subscription, or use the browser's notification interface. | Must |
| R18 | The application MUST NOT tell the attendee they will be notified, since nothing reaches a closed application. | Must |
| R19 | This spec MUST NOT add state to the server. | Must |
| R20 | A device that cannot remember what it has shown MUST still work, at worst by repeating a notice. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| What triggers it | The activity starting, not its creation | A stand creates its three activities in one sitting while setting up, hours before any of them happens. Announcing those at nine in the morning is three interruptions about things at four in the afternoon, and it teaches the attendee to ignore the next one. Starting is the moment there is something to walk to. |
| Real notifications | Not built | They need permission the attendee will refuse, a service worker delivering while the app is closed, and a server that knows who to reach. The fair lasts an afternoon and everyone is in the same building, already holding the application open. The cost is not the code, it is that a half-built notification system is one that fails silently. |
| Already completed | No notice | Telling somebody to go and do what they already did is the fastest way to make them stop reading notices. |
| Withdrawn stand | No notice | Its codes award nothing (spec 023, R16), so sending somebody there wastes their afternoon. |
| Once per device | Always | The answer to "did I already tell you this" lives on the phone, because that is where the reading happened. It is a display preference, not a fact about the fair, so it does not belong in the database. |
| Arriving late | Still told | Something that has been running for ten minutes is still something to go and do. The rule is "have you seen this", not "did it happen while you were watching". |
| Several at once | Queued | Two notices on screen at the same time is a dialog, not a notice, and the second one is read by nobody. |
| Where the truth comes from | The same polling as everything else | The activity lifecycle is derived (spec 019) and screens already refresh (spec 028). A notice is a comparison between what the client sees now and what it has already shown. Nothing new runs anywhere. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| Three activities start while the attendee is on the leaderboard | Three notices, one after another | each one's own |
| The attendee is mid-scan when one starts | The notice waits or sits clear of the scanner; the scan is not interrupted | none |
| The device cannot store what it has shown | Notices still work; a notice may repeat | none |
| The attendee dismisses a notice | It is counted as shown and does not come back | none |
| The activity finishes while its notice is on screen | The notice stays; acting on it lands on an activity marked finished | the activity screen's own |
| The attendee has no profile yet | No notices at all | none |
| The network is down when a notice would appear | No notice; the next successful read produces it | none |
| Ten activities are running and none has been shown | They are queued, not shown at once | each one's own |

## 7. Security and integrity

- **Nothing here is a capability.** A notice reads what the activity screen already reads and
  shows it sooner. It grants no access, awards no points and changes nothing.
- **What an attendee has completed is their own.** R5 needs to know which activities this attendee
  has done, which is read for the participant in the open session and never for an identifier the
  screen is handed (constitution IV, as spec 025 already establishes for the same data).
- **The device remembers only identifiers it was already shown.** The list of activities already
  notified is a set of activity ids, which are public — the same ids the activity list renders.
  Nothing about another attendee is stored on the device.
- **No permission is requested (R17).** An application that asks for notification permission on
  first open is one a fraction of the audience denies immediately and a larger fraction distrusts.
  Asking for nothing costs nothing here, because nothing needs it.

## 8. Acceptance criteria

- [x] Starting an activity puts a notice on an attendee's screen without them navigating anywhere.
- [x] Creating an activity produces no notice; starting that same activity does.
- [x] Finishing an activity produces no notice.
- [x] A withdrawn community's activity produces no notice.
- [x] An activity the attendee already completed produces no notice.
- [x] The same activity does not produce a second notice, including after closing and reopening.
- [x] Two activities starting together produce two notices in sequence, never two at once.
- [x] The notice names the activity and the stand, and says it is running.
- [x] Acting on the notice lands on the activity list.
- [x] The notice can be dismissed and also goes away on its own.
- [x] No notice appears on the stand console, the projected screen or the organiser's panel.
- [x] No notice appears for somebody without a profile.
- [x] The application never requests notification permission and registers no push subscription.
- [x] With device storage unavailable, notices still appear.

## 9. Open questions

None. Two decisions are recorded rather than left implicit: the trigger is the activity starting
rather than being created, for the reason in section 5; and an attendee who opens the application
while something is already running is told about it, because the question this answers is "have you
seen this", not "were you watching when it happened".

## 10. Current behaviour and the gap

Nothing in this spec exists.

| Concern | Today |
|---|---|
| Knowing an activity started | Only by opening the activity screen and reading it. It refreshes itself (spec 028), so it is current — but only while it is the screen being looked at. |
| Any notice anywhere | None. The application has no component that appears on its own. |
| Notifications | None, and none is wanted. No service worker messaging, no permission request, no subscription. |

**Consequences the plan must address**

- The trigger has to be derived by the client, because the server has no idea an activity started:
  the lifecycle is computed from `started_at` and the duration (spec 019), and nothing runs in the
  background (ADR 0003). "Started" means "running now, and I have not shown this one yet".
- That comparison needs somewhere to remember what has been shown. It is per-device, so it is
  `localStorage`, with the failure mode R20 describes.
- The notice has to sit above every attendee screen without being part of any of them, and without
  covering the navigation or the scanner.

## 10b. As built

`src/components/ActivityNotice.jsx`, mounted once in the application shell inside the layout that
already separates the attendee's screens from the stand's and the organiser's — which is what makes
R14 and R15 true without either of them being checked anywhere. `src/lib/devicePrefs.js` holds what
this device has been shown.

**No server change at all.** The trigger is a comparison, not an event: the activity lifecycle is
derived (spec 019) and nothing runs in the background (ADR 0003), so "it started" can only mean
"it is running now and this phone has not been told". The component reuses the polling from spec
028, so the fair pays for one more read rather than for a delivery mechanism.

**It asks for no permission and registers nothing.** No Push API, no Notifications API, no service
worker message. This is stated as a requirement (R17) rather than left as an implementation
accident, because the obvious next step for anybody touching this file is to "make it a real
notification", and doing that properly is a different system: a subscription per device, a server
that knows who to reach, and a permission prompt a good share of the audience denies on sight.

**A notice is marked shown when it appears, not when it is dismissed.** If somebody closes the
application with one on screen, they saw it. Marking on dismissal would show it again to everyone
whose attention it actually caught.

**Three activities produce three notices in sequence, never three at once (R7).** A queue, one
visible at a time. Two notices on screen simultaneously stop being notices and become a dialog, and
nobody reads the second one.

**It sits above the navigation rather than over the middle of the screen**, and below it in
stacking order, so it can never block moving to another screen — including on the scanner, where
the middle of the screen is the camera.

**Verified in the browser:** creating an activity produced nothing, starting it put the notice on
the attendee's home within one polling cycle, reloading did not repeat it, and starting a main
event produced a notice that said so. Screenshotted at phone width to confirm it clears the
navigation.

**A defect this uncovered, fixed separately.** Verifying that a failed refresh keeps its content
(spec 028, R6) meant stopping the API for nine seconds, and what that revealed was worse than what
was being tested: `AuthContext` treated "the profile query failed" and "no profile belongs to this
session" as the same answer, and cleared the device's session for both. A network gap in a hall
with one access point would have signed attendees out at random.

## 11. References

- Constitution: IV (identity is never a parameter), VII (the Chromium 83 floor, which is why this
  uses nothing newer than the rest of the application).
- ADR 0003 — polling instead of realtime, which is why the trigger is a comparison rather than an
  event.
- Glossary: *Activity*, *Main event*, *Participant*, *Stand*.
- Spec 019 — `stand-activity-catalogue`, which owns the lifecycle this observes and the rule that
  it is derived rather than stored.
- Spec 025 — `participant-activity-progress`, the screen this sends the attendee to, and the owner
  of what an attendee has completed.
- Spec 028 — `screens-reflect-shared-state`, whose polling this reuses.
- Spec 023 — `organizer-community-management`, whose R16 is why a withdrawn stand produces nothing.
