# Spec 011 — QR projection

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `011-qr-projection` |
| **Actors** | Stand admin, Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

This is the screen a stand puts on a laptop or a monitor and points at the room. Everything an
attendee earns comes through it: they hold up a phone, it reads the code, and points move. It
already works, and it already rotates the code every fifteen seconds so a photograph is useless a
moment later.

What changes is what it can show. Today a stand has two codes — a visit and "an activity" — and a
toggle between them. Spec 019 gives a stand up to three real activities with their own identities
and their own lifecycles, so the screen has to be able to say *which* activity it is showing, and
must refuse to show one that is not running.

## 2. Scope

**In scope**

- Choosing what to project: the stand's visit code, or the code of one of its running activities.
- Where each of those is reached from, now that the stand console has sections.
- What the projected screen shows: the code, the manual fallback, and the countdown.
- Which codes may be projected at all, and when.

**Out of scope**

- The rotation window, the signature and how a code is verified. Spec 002 for the camera path,
  spec 003 for the manual code. Unchanged in mechanism.
- What a scan awards. Spec 020.
- The lifecycle of an activity: starting it, finishing it, the limit of three. Spec 019.
- The rest of the stand console. Specs 019, 021 and 018 own its three sections.

## 3. User scenarios

### 3.1 The stand projects its visit code

**Given** a stand set up for the day
**When** they open the visit code from wherever they are in the console
**Then** it fills the screen, rotates every fifteen seconds, and shows the manual code beneath it
for anyone whose camera will not work.

### 3.2 An activity begins

**Given** a stand that has just started its workshop
**When** they open that activity's code from its card
**Then** the screen projects the workshop's own code, labelled with the workshop's name so nobody
in the room has to guess what they are scanning.

### 3.3 The activity ends

**Given** a projected activity code
**When** the activity finishes, whether because the stand closed it or its duration elapsed
**Then** the screen stops offering that code. It does not keep rotating a code that awards nothing.

### 3.4 Back to normal

**Given** an activity that has finished
**When** the stand returns to the visit code
**Then** the room can go back to earning visits, which is what most of the fair is.

### 3.5 Someone tries to project what is not theirs

**Given** a stand admin who edits the address to another stand's code
**When** the screen tries to produce it
**Then** nothing is signed and nothing is shown. The code was never theirs to project.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | A stand MUST be able to project its visit code, reachable from anywhere in its console. | Must |
| R2 | A stand MUST be able to project the code of any of its activities that is currently running. | Must |
| R3 | An activity's code MUST be reached from that activity, so it is never ambiguous which one is being projected. | Must |
| R4 | Exactly one code MUST be projected at a time, filling the screen. | Must |
| R5 | A projected activity code MUST be labelled with that activity's name. | Must |
| R6 | The projected screen MUST show the manual code alongside the projected code. | Must |
| R7 | The projected screen MUST show how long remains before the code rotates. | Must |
| R8 | The code MUST be replaced when its window elapses, without anyone touching the screen. | Must |
| R9 | A stand MUST NOT be able to project a code belonging to another stand. | Must |
| R10 | A stand MUST NOT be able to project the code of an activity that has not started or has finished. | Must |
| R11 | When a projected activity finishes, the screen MUST stop showing its code rather than continue rotating one that awards nothing. | Must |
| R12 | R9 and R10 MUST be enforced where the code is produced, not by hiding a control. | Must |
| R13 | The visit code MUST remain available whatever an activity is doing, since visits are independent of activities. | Must |
| R14 | The projected code SHOULD stay legible from across a room: the code itself is the screen's content, not an element on a page. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| The visit code is always at hand | A fixed control, from anywhere in the console | It is what a stand projects for most of the fair. Activities are the exception — they run for minutes at a time — so the common case must not be the one buried in a section. |
| An activity's code is reached from its activity | Always | With three activities, a chooser detached from them invites projecting the wrong one, which awards the wrong number of points to everyone in the room. Reaching it from the activity itself makes that impossible. |
| One code at a time | Always | A projected code is read from several metres away. Two codes on one screen halves both, and the attendee has to work out which is which. |
| Only a running activity's code may be projected | Always | Projecting a code that awards nothing produces a queue of people scanning and being refused, and the stand finds out from the complaints. |
| Rotation | Unchanged | Fifteen seconds, with one window of tolerance, as specs 002 and 003 define. This spec changes what is signed, never how. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| The projected activity finishes while it is on screen | The screen stops offering the code and says the activity is over | "Esta actividad ya terminó." (stand) |
| The stand's connection drops | The last code stops rotating and the screen says so, rather than showing a stale code as if it were valid | "Sin conexión. El código no se está actualizando." (stand) |
| A stand opens another stand's code by editing the address | Nothing is signed and nothing is projected | "No tienes acceso a este código." (stand) |
| A stand opens the code of an activity that has not started | Refused | "Esta actividad todavía no ha iniciado." (stand) |
| A stand opens the code of a finished activity | Refused | "Esta actividad ya terminó." (stand) |
| The stand's community is withdrawn while projecting | The code stops being produced | "Tu comunidad ya no está activa." (stand) |
| A stand has no activities | Only the visit code is available, with nothing looking broken | none |
| The screen is left projecting overnight | It keeps rotating the visit code; nothing accumulates and nothing leaks | none |

## 7. Security and integrity

The projected screen is the most public surface in the system: it is pointed at a room full of
people, several of whom will photograph it.

- **The screen displays a signature it did not create (constitution V).** The code is signed in
  the database, where the secret lives, and this screen only renders what came back. It has never
  held the secret and must not start — this is audit finding F3 and it is not to be reopened.
- **Rotation is what makes a photograph worthless.** A captured code is valid for one further
  window at most. Nothing here may extend that, cache a code, or keep showing one after its window
  has passed.
- **Ownership and state are checked where the code is produced (R12, constitution IV).** Hiding a
  button is not a control: a stand admin can call the signing path directly. Which stand is asking
  comes from the session, and whether the activity is running is a question the database answers.
- **Being unable to sign must look like being unable to sign (R11, and the connection row above).**
  The dangerous failure is a screen that keeps displaying the last code it received, because it
  looks exactly like a working one to everybody in the room.
- **Labelling is integrity, not decoration (R5).** An unlabelled activity code invites a stand to
  project the wrong one, which silently awards 30 points where 10 were meant, or the reverse.

## 8. Acceptance criteria

- [ ] The visit code is reachable from every section of the stand console.
- [ ] A running activity's code is reachable from that activity, and is labelled with its name.
- [ ] Only one code is on screen at a time, filling it.
- [ ] The manual code appears alongside the projected code.
- [ ] The remaining time before rotation is visible and counts down.
- [ ] The code changes when its window elapses, with nobody touching the screen.
- [ ] A stand cannot project another stand's code, including by editing the address.
- [ ] A stand cannot project the code of an activity that has not started.
- [ ] A stand cannot project the code of a finished activity.
- [ ] A projected activity that finishes stops being projected.
- [ ] A withdrawn community's codes stop being produced.
- [ ] Losing connectivity is shown as such rather than leaving a stale code on screen.
- [ ] A stand with no activities can still project its visit code.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Most of this ships today, in `src/pages/admin/QRDisplay.jsx`.

| Requirement | Today |
|---|---|
| R1 | Met in substance, differently. The console has no sections yet; the code is reached from the single admin screen. |
| R2, R3, R5 | **Missing.** There is one activity code per stand, chosen with a Visita/Actividad toggle, and it has no name because activities have none. |
| R4, R6, R7, R8, R14 | Met. Full-screen code, the six-character manual code beneath it, a countdown bar that pulses under five seconds, and rotation every fifteen seconds. |
| R9 | Met twice over: the screen compares the community against the address (`QRDisplay.jsx:95`), and the signing function refuses when the caller does not own the stand. The second is the one that counts. |
| R10, R11 | **Missing.** Activities have no state, so a stand's activity code is valid from the moment the stand exists until the fair ends. |
| R12 | Met for ownership, absent for state. |
| R13 | Met. |

**Consequences the plan must address**

- The signed payload has to identify the activity, which changes what is signed and invalidates
  every code across the change. Coordinated with specs 002, 003, 019 and 020.
- The signing path gains a second refusal — the activity is not running — which must be evaluated
  at signing time, not cached from when the screen opened.
- With fixed award values (spec 020), the payload no longer needs to carry the amount. Dropping it
  removes the reason the clamp exists, though the clamp stays.
- The screen is where the console's sections and the visit code meet, so it lands with spec 019.

## 10b. As built

Shipped with specs 019 and 020. An activity's code is reached from that activity's card, which
carries the activity in the address, so it is never ambiguous which one is on screen (R3). The
screen labels the projected code with the activity's name and what it is worth (R5).

`sign_scan_code` gained an activity argument and refuses to sign one that is not running, in the
database rather than by hiding a button (R10, R12). When it refuses, the screen replaces the code
with the reason instead of leaving the last one up — a screen still showing a code that no longer
awards anything looks exactly like a working one to everybody in the room (R11).

**Not yet built.** R1's "reachable from anywhere in the console" is currently the existing button
on the stand's identity card; the visit code is one tap from every section rather than a persistent
control. R13 holds — the visit code stays available whatever an activity is doing.

**Observed lag.** A projected activity that finishes keeps its code on screen until the next
15-second refresh. The code is refused on scan throughout.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), V (secrets never
  reach the client).
- ADR 0004 — business rules in Postgres, and audit finding F3 on server-side signing.
- Glossary: *Signed payload*, *Rotation window*, *Short code*, *Activity*.
- Spec 019 — `stand-activity-catalogue`, which gives activities the identity and state this screen
  needs. Ships with it.
- Spec 020 — `fixed-points-model`, which changes what the payload carries.
- Specs 002 and 003 — the scanning paths this screen feeds, unchanged in mechanism.
- Spec 023 — `organizer-community-management`, whose withdrawal stops code production.
