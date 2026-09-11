# Spec 030 — Guided tour

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `030-guided-tour` |
| **Actors** | Participant, Stand admin |
| **Created** | 2026-09-11 |
| **Last updated** | 2026-09-11 |

## 1. Purpose

Three hundred attendees arrive at a fair, open an application they have never seen, and nobody is
standing next to them to explain it. Ten stands are handed a login and a table. Both groups have to
be productive within about a minute, and the cost of not being is not confusion — it is an attendee
who never scans anything and a stand whose activity nobody attends.

The screens are already built to be read without instructions. This spec is about the first minute,
where even a well-labelled screen is a screen you have not seen before: it walks each of the two
audiences through their own application once, pointing at the things they will need.

## 2. Scope

**In scope**

- A walkthrough for the attendee, and a separate one for the stand.
- When each one runs, and what happens when it is over.
- What it points at, and how it behaves on a phone.

**Out of scope**

- The organiser's panel. One person, who already knows the system.
- Documentation, help pages, a manual. Those exist for the team, in `README.md` and the specs.
- Teaching anything the screens do not already do. A tour that explains a confusing screen is a
  workaround for a screen that should have been fixed.
- Any change to what the screens themselves do.

## 3. User scenarios

### 3.1 An attendee who just registered

**Given** somebody who has chosen a nickname and reached their home screen for the first time
**When** the screen loads
**Then** they are walked through where to scan, where the activities are, where the prizes are and
where the ranking is, and can leave the walkthrough at any point.

### 3.2 A stand opening its console

**Given** a community signing in on the table's laptop for the first time
**When** the console loads
**Then** they are walked through projecting their code, creating their activities, registering
their prizes and confirming a handover.

### 3.3 Somebody who already knows

**Given** an attendee who has seen the walkthrough
**When** they open the application again, on the same phone
**Then** it does not run again.

### 3.4 Somebody in a hurry

**Given** an attendee who wants to start scanning immediately
**When** the walkthrough appears
**Then** one visible action ends it, and it does not come back.

## 4. Requirements

### When it runs

| ID | Requirement | Priority |
|---|---|---|
| R1 | The attendee's tour MUST run automatically the first time they reach their home screen with a profile. | Must |
| R2 | The stand's tour MUST run automatically the first time a community reaches its console. | Must |
| R3 | A tour MUST NOT run again on a device where it has been completed or skipped. | Must |
| R4 | A tour MUST NOT run before the screen it describes has finished loading, so that it never points at something that is not there yet. | Must |
| R5 | The two tours MUST be independent: seeing one MUST NOT count as seeing the other. | Must |

### What it does

| ID | Requirement | Priority |
|---|---|---|
| R6 | Each step MUST point at a real element on the screen and say what it is for. | Must |
| R7 | The element a step points at MUST be visibly distinguished from the rest of the screen. | Must |
| R8 | The attendee MUST be able to move forward through the steps. | Must |
| R9 | Ending the tour MUST be possible from every step, in one action. | Must |
| R10 | The tour MUST say how far along it is. | Should |
| R11 | The last step MUST end the tour without the reader having to find the exit. | Must |
| R12 | A tour MUST NOT change anything, navigate anywhere, or act on the reader's behalf. | Must |

### The attendee's tour covers

| ID | Requirement | Priority |
|---|---|---|
| R13 | Their points, and that the whole point is to collect them. | Must |
| R14 | Scanning a stand's code, which is how points are collected. | Must |
| R15 | The activities screen, and that activities are worth more while they are running. | Must |
| R16 | The prize catalogue, and that a prize is collected in person at the stand. | Must |
| R17 | The ranking. | Should |

### The stand's tour covers

| ID | Requirement | Priority |
|---|---|---|
| R18 | Projecting the rotating code, which is how the stand awards points. | Must |
| R19 | Creating activities, and that there are at most three with one main event. | Must |
| R20 | Registering prizes and their cost. | Must |
| R21 | Confirming a handover from the attendee's code. | Must |

### On a phone

| ID | Requirement | Priority |
|---|---|---|
| R22 | The tour MUST be usable at the narrowest width the application supports. | Must |
| R23 | A step MUST NOT cover the element it is pointing at. | Must |
| R24 | If the element a step points at is off screen, it MUST be brought into view before the step is shown. | Must |
| R25 | The tour MUST work on the oldest browser the application supports. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Who gets one | The attendee and the stand | Three hundred people arrive unaccompanied, and ten stands are handed credentials and a table. The organiser is one person who already knows the system. |
| When | Automatically, the first time | Whoever does not know how to use an application is exactly whoever will not go looking for a help button. |
| Replaying it | Not built | Recorded as an accepted cost: somebody who dismisses it by accident cannot get it back, and will have to find their way around the screens as they would have without it. The screens are built to be readable on their own, so this is a smaller loss than it would be in an application that depends on its tour. |
| Remembering | On the device | Which phone has seen a walkthrough is a fact about the phone, not about the fair. Nothing about it belongs on the server. |
| Two separate tours | Always | A stand admin is a person with a laptop and a table; an attendee is a person with a phone and a queue behind them. One tour covering both would be wrong for each. |
| Not a substitute | Always | If a step has to explain why a screen is confusing, the screen is the thing to change. A tour that carries that weight hides the problem and then gets skipped. |
| Changing nothing | Always | A walkthrough that navigates or acts leaves the reader somewhere they did not choose to be, and on the stand's console it could start an activity nobody meant to start. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| The device cannot remember it was seen | The tour runs again on the next visit | none |
| An element a step points at does not exist | That step is skipped rather than pointing at nothing | none |
| The screen is narrower than the step's text | The step stays within the screen and readable | none |
| The element is below the fold | It is scrolled into view first | none |
| The reader rotates the phone mid-tour | The step re-points at its element | none |
| The reader navigates away mid-tour | The tour ends and counts as seen | none |
| A notice from spec 029 arrives mid-tour | It waits, or appears without covering the step | none |
| An attendee registers on a device where somebody else already did the tour | It does not run; the device has seen it | none |

## 7. Security and integrity

- **A tour reads the screen and nothing else (R12).** It takes no action on the reader's behalf.
  This matters most on the stand console, where the things it points at start activities and
  confirm handovers: a walkthrough that clicked anything to demonstrate it would award points or
  spend somebody's balance.
- **It shows no data that the screen is not already showing.** Steps describe controls, not
  content, so a tour cannot become a second path to something the screen itself would not display.
- **What it stores is whether it ran.** Not who ran it, not what they did.
- **It must not become a way to reach a screen.** The stand's tour describes the console's sections
  to somebody already signed into that console; it is not a route into it.

## 8. Acceptance criteria

- [ ] An attendee reaching their home screen for the first time is walked through it.
- [ ] A community reaching its console for the first time is walked through it.
- [ ] Neither tour runs a second time on the same device.
- [ ] Seeing one tour does not suppress the other.
- [ ] Every step points at an element that is on the screen and visibly marks it.
- [ ] Every step can be left in one action.
- [ ] The last step ends the tour.
- [ ] Nothing is changed, submitted or navigated by the tour.
- [ ] The attendee's tour covers points, scanning, activities and prizes.
- [ ] The stand's tour covers the projected code, activities, prizes and confirming a handover.
- [ ] At the narrowest supported width, no step covers what it points at or runs off the screen.
- [ ] A step whose element is off screen scrolls it into view first.
- [ ] A step whose element is missing is skipped rather than pointing at nothing.
- [ ] With device storage unavailable, the tour still runs and can still be finished.

## 9. Open questions

None. One decision carries a consequence recorded in section 5 rather than left implicit: there is
no way to replay a tour, so somebody who dismisses it cannot get it back.

## 10. Current behaviour and the gap

Nothing in this spec exists.

| Concern | Today |
|---|---|
| Learning the attendee's application | The screens carry their own explanatory text — the registration screen says what a nickname is for, the prize screen says a prize is collected in person — but nothing introduces them. |
| Learning the stand console | Nothing. A community is handed a username and a password. |
| Any first-run behaviour | None. Every visit is the same as every other. |
| Remembering anything per device | Only the current participant's identifier (`src/lib/storage.js`). |

**Consequences the plan must address**

- Pointing at an element means the element has to be findable from outside the component that
  renders it, and has to stay findable when that component is edited. A step bound to a class name
  used for styling breaks the next time somebody restyles the screen.
- The Chromium 83 floor (ADR 0005) rules out anything depending on newer layout or selector
  features, and argues against a tour library, which would also be a dependency carried for one
  minute of the first visit.
- The attendee's tour points at the bottom navigation, which lives in the application shell rather
  than in any screen.
- Spec 029 puts notices on the same screens. The two have to agree about what sits on top.

## 11. References

- Constitution: VII (the Chromium 83 floor), IX (quality gates).
- ADR 0005 — the compatibility target and why it exists.
- Glossary: *Participant*, *Stand*, *Activity*, *Reward*.
- Spec 013 — `participant-dashboard`, the attendee's first screen and where their tour starts.
- Spec 014's successors, specs 019 and 021 — the stand console sections its tour describes.
- Spec 018 — `in-person-reward-fulfilment`, whose handover confirmation the stand's tour covers.
- Spec 029 — `activity-start-notice`, which shares the same screens.
- Spec 016 — `naming-and-hygiene-cleanup`, whose design-system rule the tour's appearance follows.
