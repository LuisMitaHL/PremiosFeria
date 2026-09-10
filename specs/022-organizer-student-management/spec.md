# Spec 022 — Organizer student management

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `022-organizer-student-management` |
| **Actors** | Event operator, Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Spec 001 built a registration with one field and no way back. An attendee whose phone identity
changes — a browser update, a private window, a borrowed phone, a flat battery and a friend's
device — types their nickname, is told it is taken, and loses everything they earned. The system
cannot tell them apart from someone trying to take that nickname, and it never will be able to.

A person can. This spec gives the organiser the desk where that is sorted out: they look at who is
in front of them, decide, and hand back the profile. It is the escape valve spec 001 was written
around, and until it exists the promise in 001's refusal message cannot be made.

It also gives the organiser the rest of what a complaint desk needs: seeing what actually happened
to somebody, fixing a nickname, and dealing with an attendee who is spoiling the event for others.

## 2. Scope

**In scope**

- Returning a profile to an attendee whose device is no longer recognised.
- Seeing a participant's balance, scans and handovers.
- Changing a participant's nickname.
- Withholding the ability to claim prizes.
- Removing a participant from the event.
- Adjusting a balance by hand, and the constraints that keep that defensible.
- Delivering R10b of spec 001.

**Out of scope**

- Registration itself. Spec 001.
- Recording these actions. Spec 024 stores the record; this spec says what has to be recorded.
- The organiser's identity and the panel. Spec 017.
- Deciding what counts as an offensive nickname. That is a human judgement made in the room, and
  the system deliberately holds no opinion (spec 001, R12).

## 3. User scenarios

### 3.1 An attendee changed phones

**Given** an attendee who registered as `zorro` this morning and is now on a different phone
**When** they come to the organisation desk and the organiser is satisfied it is them
**Then** the organiser issues a recovery code, the attendee types it on the new phone, and their
profile comes back with every point, scan and handover intact.

### 3.2 An attendee is turned away first

**Given** the same attendee, before they reach the desk
**When** they type `zorro` on the new phone
**Then** they are told the nickname is taken **and that it can be restored at the organisation
stand**. That sentence is what this spec makes true.

### 3.3 Someone is trying it on

**Given** a person who saw `zorro` at the top of the leaderboard and wants that profile
**When** they ask the organiser for it
**Then** the organiser declines. Nothing in the system decides this; the organiser does.

### 3.4 A complaint at the desk

**Given** an attendee who says a stand scanned them but their points did not move
**When** the organiser looks up their profile
**Then** they can see the balance, every scan with its stand and time, and every prize handed
over, and can tell whether the scan happened.

### 3.5 A nickname is a problem

**Given** an attendee whose nickname is offensive and is on a leaderboard being projected
**When** the organiser changes it
**Then** the new nickname replaces it everywhere, and the attendee keeps their points.

### 3.6 A points adjustment

**Given** an attendee whose activity code could not be scanned because the stand's phone failed
**When** the organiser credits them what the activity was worth, recording why
**Then** their balance reflects it, and the record says who did it, when, how much and for what
reason.

## 4. Requirements

### Returning a profile

| ID | Requirement | Priority |
|---|---|---|
| R1 | The organiser MUST be able to find a participant by nickname. | Must |
| R2 | The organiser MUST be able to issue a recovery code for a participant. | Must |
| R3 | A recovery code MUST be usable exactly once, and MUST stop working once used. | Must |
| R4 | A recovery code MUST expire on its own after a short time, whether or not it was used. | Must |
| R5 | A participant MUST have at most one live recovery code. Issuing a new one MUST invalidate the previous one. | Must |
| R6 | Entering a valid recovery code on a device MUST attach that profile to that device and begin a session for it, with every point, scan and handover intact. | Must |
| R7 | Entering a valid recovery code MUST detach the profile from the device it was previously attached to. | Must |
| R8 | A recovery code MUST NOT be guessable from the nickname, from the participant, or from another code. | Must |
| R9 | Recovery MUST NOT create a second profile, and MUST NOT change the nickname. | Must |
| R10 | The refusal in spec 001 R9 MUST now tell the attendee that a profile can be restored at the organiser's stand. This delivers spec 001 R10b. | Must |

### Seeing what happened

| ID | Requirement | Priority |
|---|---|---|
| R11 | The organiser MUST be able to see a participant's current balance. | Must |
| R12 | The organiser MUST be able to see every scan a participant was awarded, with the stand, what it was for, when, and how many points. | Must |
| R13 | The organiser MUST be able to see every prize handed over to a participant, with the stand, the reward and when. | Must |

### Changing a participant

| ID | Requirement | Priority |
|---|---|---|
| R14 | The organiser MUST be able to change a participant's nickname. | Must |
| R15 | A changed nickname MUST satisfy every rule spec 001 places on one: length, uniqueness, and case-insensitive comparison. | Must |
| R16 | Changing a nickname MUST NOT change the balance, the history, or which device the profile is attached to. | Must |
| R17 | The organiser MUST be able to withhold a participant's ability to claim prizes, and to restore it. | Must |
| R18 | A participant who cannot claim MUST still be able to earn points and MUST still appear on the leaderboard. | Must |
| R19 | A participant MUST be told, when a claim is refused for this reason, that it was withheld — not that they are short of points or that stock ran out. | Must |
| R20 | The organiser MUST be able to remove a participant from the event, and to reinstate them. | Must |
| R21 | A removed participant MUST NOT be able to earn or claim anything. | Must |
| R22 | A participant MUST NOT be deleted, ever, and removing one MUST NOT erase their balance or history. | Must |

### Adjusting a balance

| ID | Requirement | Priority |
|---|---|---|
| R23 | The organiser MUST be able to add points to, or subtract points from, a participant's balance. | Must |
| R24 | An adjustment MUST require a reason, entered by the organiser, and MUST NOT be possible without one. | Must |
| R25 | An adjustment MUST NOT take a balance below zero. | Must |
| R26 | Every adjustment MUST be recorded with its amount, its reason and its moment, and MUST be distinguishable from points earned by scanning. | Must |
| R27 | An adjustment MUST be the only way a balance changes other than earning and claiming. There MUST be no other override. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Who decides a recovery is genuine | The organiser, in person | The system cannot tell an attendee who changed phones from someone who wants their profile — the evidence is the person standing there. Building any automatic test would only produce a rule to be gamed. |
| Recovery code | Single use, short-lived, one live per participant | The same shape as the claim code in spec 018, for the same reason: a code that is shown, read aloud or photographed must be worthless a moment later. One mechanism, one set of rules to reason about. |
| Recovery detaches the old device | Always | Two devices holding the same profile means two people earning into one balance, and no way to tell which is the owner. Recovery moves a profile; it does not copy it. |
| Nickname changes | Subject to every rule in spec 001 | A nickname is still the recovery key and still appears on a projected leaderboard. The organiser correcting one must not be able to create the duplicate or the overlong name that spec 001 forbids. |
| Withholding claims | Keeps earning, blocks spending | This is the sanction spec 001 warns about at registration. Removing someone entirely for an offensive nickname is disproportionate; letting them collect prizes anyway makes the warning meaningless. |
| Removal | Never a deletion | Scans and handovers reference the participant. The same rule that protects communities and rewards protects people: nothing that happened is erased. |
| Adjustments require a reason | Always | An adjustment is the one place where the leaderboard stops being a consequence of what happened in the hall. A number with no reason is indistinguishable from a favour; the reason is what makes the log worth keeping. |
| Adjustments are distinguishable | Always | Anyone reading a balance later must be able to see which part was earned and which was granted. A blended total cannot be audited. |
| Adjustments cannot go below zero | Always | Spec 020 R12 binds every writer, including the organiser. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A recovery code is entered twice | The second attempt is refused | "Código inválido o vencido." |
| A recovery code is entered after it expired | Refused | as above |
| A recovery code is entered on the device the profile is already on | Accepted; nothing changes except that the code is consumed | none |
| The original device opens the app after a recovery | It no longer holds that profile and is treated as a new visitor | none |
| The organiser issues a second recovery code | The first stops working immediately | as the first row |
| A nickname change collides with an existing nickname | Refused; nothing changes | "Ese nombre ya está en uso." |
| A nickname change is longer than 24 characters | Refused | "El nombre no puede tener más de 24 caracteres." |
| A participant whose claiming is withheld tries to claim | Refused at the stand, with the real reason | "Este estudiante no puede canjear premios." (stand) |
| A removed participant scans a code | Nothing awarded | "Tu perfil ya no está activo." |
| A removed participant is reinstated | Earns and claims again; balance and history unchanged | none |
| An adjustment would take a balance below zero | Refused; nothing changes | "El ajuste dejaría el saldo en negativo." |
| An adjustment is submitted with no reason | Refused | "Indica el motivo del ajuste." |
| An adjustment lands while a handover is being confirmed | Both apply, in whichever order they arrive; neither is lost and the balance never goes negative | none |
| Two organisers act on the same participant at once | Both apply, or one is refused, but never a partial result | varies |

## 7. Security and integrity

Everything here is an exception to a rule the rest of the system enforces, which is exactly why it
is the most dangerous spec in the set.

- **Recovery is an account takeover, performed deliberately (R6, R7).** That is what it is for,
  and it is why every safeguard sits on the code rather than on the profile: single use, short
  life, one at a time, unguessable. A leaked recovery code hands somebody else's points to
  whoever types it first.
- **Only the organiser may issue one (constitution IV).** Issuing is scoped to an organiser
  session resolved server-side. Nothing a participant or a stand can call may produce a recovery
  code for any profile, including their own.
- **Detaching the old device is part of the operation, not a follow-up (R7).** Attaching a second
  device without detaching the first would leave two people earning into one balance with no way
  to tell whose it is.
- **Adjustments are the one sanctioned override, and they are bounded (R23 to R27).** They require
  a reason, cannot go below zero, are recorded distinguishably, and are the *only* path other than
  earning and claiming. Any second path — a direct update, a repair script, a hidden endpoint —
  defeats the audit this spec exists to make possible.
- **Spec 020 R11 is narrowed, not broken.** That rule forbids points disappearing as a *side
  effect* of editing or deleting something. A deliberate, reasoned, recorded adjustment is a
  different act, and spec 020 is amended to say so. What stays forbidden is a balance changing
  because somebody renamed an activity.
- **Withholding a claim is enforced where claims are decided (R17, R19).** The stand's screen
  cannot be the gate: the check belongs in the same indivisible step that spends the points
  (spec 018 R14).
- **Reading a participant's history is a privilege, not a page.** The organiser sees every scan
  and handover of any attendee. That path must not be reachable by a stand or a participant.

## 8. Acceptance criteria

- [ ] The organiser can find a participant by nickname.
- [ ] A recovery code works exactly once and is refused afterwards.
- [ ] A recovery code expires on its own if unused.
- [ ] Issuing a second recovery code invalidates the first immediately.
- [ ] Entering a valid code on a new device restores the profile with balance, scans and handovers
      intact, and creates no second profile.
- [ ] After a recovery, the original device no longer holds the profile.
- [ ] A participant or a stand cannot issue a recovery code by any route.
- [ ] The refusal in spec 001 now names the organiser's stand.
- [ ] The organiser can see a participant's balance, every scan with its stand and time, and every
      prize handed over.
- [ ] The organiser can change a nickname, and is refused on a duplicate or an overlong one.
- [ ] A nickname change leaves balance, history and device attachment untouched.
- [ ] A participant whose claiming is withheld still earns points and still appears on the
      leaderboard.
- [ ] A withheld claim is refused at the stand with the real reason, not a wrong one.
- [ ] A removed participant can neither earn nor claim, and is restored intact on reinstatement.
- [ ] No participant can be deleted.
- [ ] An adjustment without a reason is refused.
- [ ] An adjustment that would go below zero is refused.
- [ ] An adjustment is recorded with amount, reason and moment, and is distinguishable from earned
      points.
- [ ] No path other than earning, claiming and adjustment changes a balance.

## 9. Open questions

None. One requirement was **derived rather than stated**, and is flagged:

- **R24, requiring a reason for every adjustment.** The decision taken was that adjustments are
  allowed and recorded in the log. A recorded amount with no reason tells a later reader what
  changed but not whether it should have, which is the only question worth asking of an
  adjustment. If a reason is too much friction at a busy desk, this is the requirement to drop —
  and the log becomes correspondingly less useful.

## 10. Current behaviour and the gap

Nothing in this spec exists. There is no organiser, and therefore no desk.

| Concern | Today |
|---|---|
| Recovery | Impossible. A lost session is a lost profile, permanently. Re-registering produces a second profile at zero points — and after spec 001 will not even do that, because the nickname will be taken. |
| Looking up a participant | Nothing exists. `participants` is world-readable and the leaderboard selects every column, but there is no screen and no notion of looking someone up. |
| Nickname changes | Impossible. |
| Sanctions | No concept of withholding or removal. |
| Adjustments | Balances change only through the award and claim functions. There is no other writer — a property worth preserving deliberately rather than by accident. |

**Consequences the plan must address**

- Recovery codes are the second single-use code in the system, after spec 018's. They should share
  a shape, and probably a mechanism, rather than being invented twice.
- Participants gain two independent states — removed, and barred from claiming — checked in the
  same places a withdrawn community is checked, which spec 023 already touches.
- Adjustments must be recorded so a balance can be decomposed into earned and granted. That is a
  new kind of entry alongside scans, and spec 024 reads it.
- Attaching a profile to a new device changes the identity a session resolves from, which is the
  one thing every other rule treats as immutable. It needs its own guarded path, and nothing else
  may reuse it.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), VI (structural
  guarantees).
- Glossary: *Participant*, *Device identity*, *Nickname*, *Points*.
- Spec 001 — `participant-registration`, whose R10b this delivers and whose nickname rules R15
  inherits.
- Spec 017 — `organizer-admin-panel`, the panel this lives in.
- Spec 018 — `in-person-reward-fulfilment`, whose claim code shares this code design, and whose
  exchange enforces R17.
- Spec 020 — `fixed-points-model`, amended by R23 to R27.
- Spec 023 — `organizer-community-management`, which applies the same withdrawal pattern to stands.
- Spec 024 — `system-audit-log`, which stores what R26 requires.
