# Spec 019 — Stand activity catalogue

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `019-stand-activity-catalogue` |
| **Actors** | Stand admin, Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Today an activity is not a thing. It is a flag on a scan: a stand can award "an activity" once,
to anyone, at any moment, and nobody — not the attendee, not the organiser — can say what that
activity actually was. An attendee walking the fair has no way to know that the robotics stand is
running a workshop at three o'clock, or that they have twenty minutes to get there.

This spec turns activities into real things a stand publishes and runs. A stand describes what it
is going to do and when it expects to do it, then starts it when it actually begins and closes it
when it ends. Attendees see what is about to happen, what is happening right now and where to go
for it. Points are awarded only to the people who were actually there while it was running, which
is the entire point of an activity as opposed to a visit.

## 2. Scope

**In scope**

- A stand creating, describing and limiting its own activities.
- The lifecycle of an activity: scheduled, running, finished.
- Starting an activity when it really begins, and closing it early or automatically.
- When an activity can and cannot award points.
- What an attendee sees about a stand's activities.
- The section structure of the stand console, since activities are the first of its three areas.

**Out of scope**

- How many points an activity awards. Spec 020 prices them; this spec decides when a completion
  can happen at all.
- Rewards and claims, the other two sections of the stand console. Specs 021 and 018.
- The signing, rotation and manual entry of the QR itself. Specs 002, 003 and 011 are unchanged
  in mechanism; they gain an activity to point at.
- Any authority for the organiser over a stand's activities. Spec 023.

## 3. User scenarios

### 3.1 A stand publishes what it will do

**Given** a stand preparing before the fair opens
**When** they add an activity with a name, a description, an estimated start time, how long it
will last, and whether it is their headline event
**Then** it appears in their list as scheduled, and attendees can see it is coming and when it is
expected to begin.

### 3.2 A stand runs late

**Given** an activity scheduled for 10:00 that lasts 10 minutes
**When** the stand is not ready until 10:10 and starts it then
**Then** the activity runs for 10 minutes from 10:10, not from 10:00. The estimated time was
always only a hint to attendees.

### 3.3 An attendee joins something that is running

**Given** an attendee looking at their activity list
**When** a stand's activity is running
**Then** they can see it is happening now, go to that stand, scan its code and be awarded points.

### 3.4 An activity ends on its own

**Given** an activity that was started and given a duration of 10 minutes
**When** 10 minutes pass and nobody at the stand touches anything
**Then** it finishes by itself. Scanning its code awards nothing from that moment on.

### 3.5 A stand finishes early

**Given** an activity that is running
**When** everyone has taken part and the stand closes it
**Then** it finishes immediately, no further scans are awarded, and it cannot be reopened.

### 3.6 An attendee arrives too late

**Given** an activity that has finished
**When** the attendee looks at that stand
**Then** they can see the activity happened and that they can no longer take part. It does not
silently disappear.

### 3.7 A stand uses up its three activities

**Given** a stand that has created three activities and finished all of them
**When** they try to add a fourth
**Then** they are refused. Three is the limit for the whole event, and closing one does not buy
another.

## 4. Requirements

### Creation and limits

| ID | Requirement | Priority |
|---|---|---|
| R1 | A stand MUST be able to create at most 3 activities for the entire event. | Must |
| R2 | Creating an activity MUST require all of: a name, a description, an estimated start time, a duration, and whether it is the stand's main event. | Must |
| R3 | A stand MUST be able to have no activities at all. | Must |
| R4 | A stand MUST have at most one main event, as required by spec 020. | Must |
| R5 | An activity MUST NOT be deleted, ever. | Must |
| R6 | Finishing an activity MUST NOT free its slot: a stand that has created 3 can never create a 4th, whatever state those 3 are in. | Must |

### Lifecycle

| ID | Requirement | Priority |
|---|---|---|
| R7 | An activity MUST be in exactly one of three states: **scheduled**, **running**, **finished**. | Must |
| R8 | A newly created activity MUST be scheduled. | Must |
| R9 | A stand MUST be able to start a scheduled activity at any moment, independently of its estimated start time. | Must |
| R10 | An activity MUST become finished automatically once its duration has elapsed, counted from the moment it was started, without anyone doing anything. | Must |
| R11 | A stand MUST be able to finish a running activity before its duration elapses. | Must |
| R12 | A finished activity MUST NOT return to any other state. | Must |
| R13 | A stand MUST have at most one running activity at a time. Starting a second while one runs MUST be refused. | Must |
| R14 | State transitions MUST only ever go scheduled → running → finished. | Must |

### Awarding

| ID | Requirement | Priority |
|---|---|---|
| R15 | An activity MUST award points only while it is running. | Must |
| R16 | An attempt on a scheduled activity MUST be refused and MUST say it has not started yet. | Must |
| R17 | An attempt on a finished activity MUST be refused and MUST say it is over. | Must |
| R18 | R15 to R17 MUST hold identically whether the attempt arrives by camera or by manual code. | Must |
| R19 | The state MUST be evaluated where the award is decided, not where the button is drawn, so a stale screen cannot award points for an activity that has ended. | Must |

### Editing

| ID | Requirement | Priority |
|---|---|---|
| R20 | An activity MUST be editable only while it is scheduled. | Must |
| R21 | From the moment an activity starts, every one of its fields MUST be frozen, including whether it is the main event. | Must |
| R22 | The reason for R21 MUST hold in practice: no two attendees may ever be awarded different amounts for the same activity. | Must |

### What people see

| ID | Requirement | Priority |
|---|---|---|
| R23 | An attendee MUST be able to see, for each stand, its activities and which of the three states each is in. | Must |
| R24 | A scheduled activity MUST show its estimated start time to the attendee. | Must |
| R25 | A running activity MUST be distinguishable at a glance, so an attendee can decide to go there now. | Must |
| R26 | A finished activity MUST remain visible, marked as no longer available. | Must |
| R27 | The estimated start time MUST NOT gate anything. It is information, never a condition. | Must |
| R28 | The stand console MUST present activities as one of three distinct sections, alongside rewards and claims. | Must |
| R29 | Each of a stand's activities MUST offer, from its own entry in that section, the action appropriate to its state: start it, show its code while running, or finish it. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Activities per stand | 3, for the whole event | Enough for a headline event and two smaller things; few enough that an attendee can complete a stand and move on. Counting finished ones against the limit is what stops a stand cycling through activities to hand out unlimited points. |
| Minimum activities | 0 | Not every community has something to run. Requiring one would produce activities invented to satisfy the rule. |
| Main events per stand | At most 1 | Defined by spec 020, where the award values live. |
| Running at once | At most 1 per stand | A stand projects one code and can attend to one thing. It also makes "happening now" unambiguous for the attendee. |
| Duration | In whole minutes, from the real start | The estimated time is a hint; the clock that matters starts when the stand says it began. |
| Estimated start | A time of day, no date | The deployment covers a single event. A date would be a field to fill in with the same answer every time. |
| Editable window | While scheduled only | The alternative allows two attendees to earn different amounts for the same activity, which is indefensible to the one who earned less. |
| Deletion | Never; finishing is the only ending | A deleted activity would take its history with it, and R11 of spec 020 says awards are never withdrawn. |
| Reopening | Never | Closing early is how a stand says "this is over". If it could be undone, an attendee who was told they were too late might find out they were not. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A stand tries to create a 4th activity | Refused | "Ya creaste el máximo de 3 actividades." (stand) |
| A stand tries to create a 4th after finishing one | Refused, same as above | as above |
| A stand marks a second activity as main event | Refused | "Ya tienes un evento principal." (stand) |
| A stand starts a second activity while one runs | Refused | "Termina la actividad en curso antes de iniciar otra." (stand) |
| An attendee scans an activity that has not started | Nothing awarded | "Esta actividad todavía no ha iniciado." |
| An attendee scans an activity that has finished | Nothing awarded | "Esta actividad ya terminó." |
| An attendee scans an activity they already completed | Nothing awarded | "Ya participaste en esta actividad." (spec 020) |
| An attendee scans in the same instant the duration elapses | Exactly one outcome, decided where the award is decided, never both | one of the above |
| A stand never starts an activity | It stays scheduled all day and awards nothing; the attendee keeps seeing an estimated time that passes | none |
| A stand starts an activity and never finishes it | It finishes by itself when the duration elapses | none |
| A stand edits an activity that is running | Refused | "No puedes editar una actividad que ya inició." (stand) |
| The estimated start time passes without the activity starting | Nothing changes: still scheduled, still startable | attendee sees it as not yet started |
| A duration of zero or negative | Refused at creation | "La duración debe ser de al menos un minuto." (stand) |
| A stand has no activities | The attendee sees that stand with no activities, without it looking broken | none |

## 7. Security and integrity

An activity is a gate on awarding points, so its state is part of the point economy.

- **State decides the award, and only the database may decide state (constitution III).** R19
  exists because the obvious mistake here is to disable a button. An attendee whose phone still
  shows an activity as running, or who replays a code captured while it was, must be refused by
  the same rule that decides the award, not by a screen they control.
- **Automatic finishing must not depend on anything running.** R10 has to hold with no scheduler,
  no background job and no open browser. If it depends on someone's screen being awake, an
  activity nobody closes stays open all day and keeps awarding points. Whether an activity has
  ended must be derivable from data already stored.
- **The one-running rule and the limit of three must be structural (constitution VI).** Two rapid
  taps on "start", or two admins on two phones, must not both succeed; nor must a fourth activity
  slip in. A check performed before the write is not the gate.
- **Freezing on start protects the award, not the text (R21, R22).** The field that actually
  matters is the main-event flag, because it is worth 20 points. Freezing everything is simpler to
  enforce and to reason about than freezing one field, and the cost — a typo that can no longer be
  fixed — is small and visible.
- **Only the owning stand may act on its activities.** Creating, starting, editing and finishing
  are scoped to the stand that owns them, resolved from the session and never from an identifier
  sent by the client (constitution IV). This is the rule that already guards code signing.
- **No deletion means no orphaned awards.** An award always points at something that still exists,
  so spec 020's promise that points are never withdrawn holds with no special case.

## 8. Acceptance criteria

- [ ] A stand can create an activity with all five fields, and cannot create one with any missing.
- [ ] A stand cannot create a 4th activity, including after finishing one.
- [ ] A stand can operate with zero activities.
- [ ] A stand cannot mark a second activity as its main event.
- [ ] A new activity is scheduled and awards nothing.
- [ ] Starting an activity 10 minutes after its estimated time gives it its full duration from
      that moment.
- [ ] A running activity awards points to an attendee who scans it.
- [ ] The activity finishes on its own once the duration elapses, with nobody's screen open.
- [ ] A stand can finish a running activity early, and scans stop being awarded immediately.
- [ ] A finished activity cannot be started again.
- [ ] A stand cannot start a second activity while one is running.
- [ ] An activity cannot be edited once it has started.
- [ ] An attendee can tell apart a scheduled, a running and a finished activity.
- [ ] A scheduled activity shows its estimated start time.
- [ ] A finished activity stays visible, marked as unavailable.
- [ ] Two simultaneous start actions produce exactly one running activity.
- [ ] Two simultaneous creations at the limit produce exactly three activities, not four.
- [ ] A scan arriving as the duration elapses either awards once or is refused, never both.

## 9. Open questions

The three limits below are **proposed, not decided**. They are presentation limits rather than
game rules, but they are still values, and this spec cannot be approved until they are confirmed.

- `[NEEDS CLARIFICATION: activity name length]` — proposed 3 to 40 characters. Long enough for
  "Taller de introducción a Rust", short enough for a card and for the attendee's list.
- `[NEEDS CLARIFICATION: description length]` — proposed up to 200 characters. Enough to say what
  it is and who it is for, short enough that the list stays scannable.
- `[NEEDS CLARIFICATION: duration bounds]` — proposed 1 to 240 minutes. The upper bound exists
  only so a mistyped duration cannot leave an activity open past the end of the fair.

## 10. Current behaviour and the gap

Nothing in this spec exists today. There is no activity entity of any kind.

| Concern | Today |
|---|---|
| Activities | Not modelled. `scans.type` is `visit` or `activity`, and that is the whole of it. An activity has no name, no schedule and no identity. |
| The limit | One activity **per stand**, enforced by the partial unique index `scans_one_activity_per_stand` on `(participant_id, community_id)`. Spec 020 replaces this with one completion per activity. |
| Lifecycle | Does not exist. A stand's activity code is valid from the moment the stand exists until the fair ends. |
| Stand console | One screen of statistics, profile editing and recent scans (`src/pages/admin/AdminDashboard.jsx`). There are no sections. |
| Attendee view | Cannot see activities, because there is nothing to see. The dashboard shows stands visited (`src/pages/Dashboard.jsx`). |
| Projection | A toggle between visit and activity (`src/pages/admin/QRDisplay.jsx`), which becomes a choice among the visit code and each activity's code — spec 011. |

**Consequences the plan must address**

- A new table, its policies and the rules guarding its lifecycle. It ships in the same deployment
  as spec 020, because 020's uniqueness guarantee has nowhere to live until activities exist.
- The signed payload has to identify the activity, which changes what is signed and therefore
  invalidates codes across the change. Coordinated with specs 002, 003 and 011.
- Automatic finishing must be derived, not scheduled: a running activity ends at its start plus
  its duration, and whether it has ended is a question asked at the moment of the award.
- The stand console gains its section structure here; specs 021 and 018 fill the other two.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), VI (structural
  guarantees).
- Glossary: *Activity*, *Stand*, *Scan*.
- Spec 020 — `fixed-points-model`, which prices activities and caps main events. **Ships together
  with this spec.**
- Spec 011 — `qr-projection`, which must let a stand show the code of a specific activity.
- Specs 021 and 018 — the other two sections of the stand console.
- Spec 025 — `participant-activity-progress`, which builds the attendee's view on R23 to R26.
- Spec 023 — `organizer-community-management`, for any authority the organiser has over these.
