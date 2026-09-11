# Spec 018 — In-person reward fulfilment

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `018-in-person-reward-fulfilment` |
| **Actors** | Participant, Stand admin |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Today an attendee taps "Canjear" in the app and their points are gone. The prize itself is a
physical object on a table somewhere, and nothing connects the two: the system has already
charged for a t-shirt that may never be handed over, the stand has no idea a claim happened, and
if the attendee never walks over, nobody can tell the difference between a prize collected and a
prize forgotten.

This spec moves the moment of truth to where the prize actually changes hands. The attendee
browses, walks to the stand, and shows a code. The stand looks at what they are giving away,
enters the code, and confirms. Only then are points spent and stock reduced — in the same instant
the object leaves the table. Nothing is charged for a prize that was not handed over, and nothing
is handed over that was not paid for.

## 2. Scope

**In scope**

- The claim code an attendee shows at a stand: how it comes into existence, how long it lives and
  when it stops working.
- The stand's screen for registering a handover.
- The single moment where points and stock are both spent.
- What each side sees while it happens, and how both screens end.
- Every way the exchange can fail.

**Out of scope**

- Registering rewards, their cost, their stock and the catalogue the attendee browses. Spec 021.
- Earning points. Spec 020.
- Any organiser authority over claims, and any record of them beyond the claim itself. Specs 023
  and 024.
- Fulfilment of anything other than a reward. Activities are not handed over; they are attended.

## 3. User scenarios

### 3.1 A prize changes hands

**Given** an attendee with 250 points standing at a stand that offers a 200-point t-shirt
**When** they open their claim screen and show the code on it
**And** the stand enters that code, selects the t-shirt, and confirms
**Then** the stand hands over the t-shirt, the attendee's balance drops to 50, the remaining stock
drops by one, and both screens close on their own.

### 3.2 The attendee does not have enough

**Given** an attendee with 150 points and a 200-point reward
**When** the stand enters their code and selects that reward
**Then** the stand is told the attendee is 50 points short, nothing is charged, no stock moves,
and no prize is handed over.

### 3.3 The last unit went to somebody else

**Given** a reward with one unit left and two attendees at the stand
**When** the first claim is confirmed
**Then** the second is refused as out of stock, and that attendee keeps every point.

### 3.4 A code is photographed

**Given** somebody photographs an attendee's claim screen
**When** the original attendee completes their claim, or simply closes the screen
**Then** the photographed code is worthless: it was good for that one exchange and nothing else.

### 3.5 The attendee changes their mind

**Given** an attendee who opened their claim screen and walked away
**When** they close it, or go and open it again later
**Then** the earlier code stops working. No points were ever committed, so there is nothing to
release.

### 3.6 A stand tries to hand over somebody else's prize

**Given** a stand admin looking at the claim screen
**When** they look for a reward belonging to another stand
**Then** it is not there to select. A stand can only give away what is on its own table.

## 4. Requirements

### The claim code

| ID | Requirement | Priority |
|---|---|---|
| R1 | An attendee MUST be able to obtain a claim code from within the app at any time. | Must |
| R2 | A claim code MUST be short enough to read aloud and type without error, and MUST avoid characters that are easily confused with one another. | Must |
| R3 | A claim code MUST be usable exactly once. | Must |
| R4 | An attendee MUST have at most one live claim code. | Must |
| R4a | While a code is live, asking for one again MUST return that same code rather than issuing another. | Must |
| R4b | A code that is no longer live MUST be replaced when a new one is asked for, and the old one MUST NOT start working again. | Must |
| R5 | A claim code MUST stop working when it is used, when the attendee closes the screen showing it, or when that screen stops being watched. | Must |
| R6 | A claim code MUST NOT commit, reserve or hold anything: no points, no stock, no reward. | Must |
| R7 | A claim code MUST NOT be guessable from another code, from the attendee's identity, or from when it was created. | Must |
| R8 | A claim code MUST identify the attendee and nothing else. In particular it MUST NOT name a reward: the stand chooses that. | Must |

### Registering the handover

| ID | Requirement | Priority |
|---|---|---|
| R9 | The stand console MUST offer a claims section, alongside activities and rewards, where a handover is registered. | Must |
| R10 | Registering a handover MUST require a claim code and one of the stand's own rewards. | Must |
| R11 | A stand MUST only be able to select rewards it owns. | Must |
| R12 | A stand MUST NOT be able to register a handover for a reward belonging to another stand, by any route. | Must |
| R13 | Before confirming, the stand SHOULD be able to see who the code belongs to and whether they can afford the selected reward. | Should |

### The exchange

| ID | Requirement | Priority |
|---|---|---|
| R14 | Confirming a handover MUST, in a single indivisible step: verify the code is live, verify the attendee has at least the reward's cost, verify stock remains, verify the attendee has not already claimed that reward, deduct the cost, reduce the stock by one, record the claim, and consume the code. | Must |
| R15 | If any of those checks fails, nothing MUST change: no points, no stock, no claim, and the code MUST remain live. | Must |
| R16 | Points MUST NOT be deducted at any earlier moment. Browsing, choosing and showing a code MUST all be free. | Must |
| R17 | An attendee MUST NOT be able to claim the same reward more than once. | Must |
| R18 | A balance MUST NOT go below zero as a result of a handover. | Must |
| R19 | Two confirmations racing for the last unit MUST result in exactly one handover. | Must |
| R20 | Two confirmations racing on the same code MUST result in exactly one handover. | Must |

### What each side sees

| ID | Requirement | Priority |
|---|---|---|
| R21 | While the attendee's claim screen is open, it MUST detect that the handover was confirmed within a few seconds and close by itself. | Must |
| R22 | On confirmation the attendee MUST be shown what they received and their new balance. | Must |
| R23 | The stand's screen MUST close on confirmation and be immediately ready for the next attendee. | Must |
| R24 | Every refusal MUST be shown to the stand in terms they can act on, naming what is wrong. | Must |
| R25 | A refusal that is the attendee's situation rather than a mistake — not enough points, already claimed — MUST NOT read like an error. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Claim code length | 6 characters | Long enough that codes live at the same time cannot collide in practice at this scale, short enough to read off a phone screen and type on another one. Matches the length of the manual scan code, which the stands are already used to. |
| Claim code alphabet | Uppercase letters and digits, excluding `O`, `0`, `I`, `1` and `L` | These are the characters people get wrong when reading a screen across a table. Every excluded pair costs a failed attempt and a retry in front of a queue. |
| Codes live per attendee | Exactly one | Two live codes let an attendee stand at two stands and have both confirmed against a balance that only covers one. The loser would be refused correctly, but only after the prize had been handed over. |
| Asking again while one is live | Returns the same code | Amended after implementation. Issuing a fresh one on every request looked equivalent, and is not: two requests that cross — a screen that remounts, a double tap — issued two codes, and the one left open was not necessarily the one on screen. The attendee would then show a stand a code that had already been replaced. Returning the live one also means reopening the screen does not invalidate a code somebody is already looking at. |
| Code lifetime | Until used, until the attendee closes the screen, or 60 seconds after that screen stops asking about it | Derived, not stated: see section 9. A code that outlives the screen showing it is a code somebody photographed and can still use. Sixty seconds is long enough to survive a phone locking and being woken, short enough that a closed browser does not leave a usable code behind. |
| What a code commits | Nothing | There is no reservation. Two attendees may both walk to a stand for the last unit and one will be disappointed. The alternative — holding stock for someone who may never arrive — makes a prize unavailable to the person actually standing there. |
| Moment of payment | Confirmation of handover | The only moment the system can be sure the prize was given. Charging earlier charges for prizes that were never collected. |
| Claims per reward per attendee | One | Stock is limited and the point of limited stock is to spread prizes across people. Unchanged from what ships today. |
| Who may confirm | The stand that owns the reward | A stand can only give away what is on its table. Letting any stand confirm any reward would let one deduct points for something it cannot hand over. |
| Attendee screen refresh | Every 2 seconds while open | The attendee is standing in front of the stand watching the screen; anything slower feels broken. It runs only while the claim screen is open and asks about one exchange, so the cost is negligible. Consistent with the polling the leaderboard already uses (ADR 0003). |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| The code does not exist, or has been used | Refused, nothing changes | "Código inválido o vencido. Pide al estudiante que lo genere de nuevo." (stand) |
| The code expired because the attendee's screen closed | Same as above | as above |
| The attendee is short of points | Refused, nothing changes, code stays live | "Le faltan N puntos para este premio." (stand) |
| The reward is out of stock | Refused, nothing changes, code stays live | "Ya no quedan unidades de este premio." (stand) |
| The attendee already claimed that reward | Refused, nothing changes, code stays live | "Este estudiante ya canjeó este premio." (stand) |
| The stand selects another stand's reward | Not offered, and refused if attempted anyway | "Solo puedes entregar premios de tu stand." (stand) |
| Two stands confirm the same code at the same instant | Exactly one succeeds; the other sees the code as already used | as the first row |
| Two confirmations race for the last unit | Exactly one succeeds; the other sees it out of stock | as the stock row |
| The attendee earns points between opening the code and confirmation | The higher balance is used: the check runs at confirmation | none |
| The attendee spends points elsewhere in between | The lower balance is used, and the claim may be refused for that reason | as the shortfall row |
| The attendee's phone locks mid-exchange | The code survives if the screen resumes within a minute | none |
| The attendee closes the app after generating a code | The code stops working shortly after | as the first row |
| The attendee generates a second code at another stand | The first stops working immediately | as the first row |
| The network drops between confirming and the attendee's screen noticing | The exchange either happened completely or not at all; the screen catches up when the network returns | none |
| The stand confirms while the attendee's screen is closed | The exchange still happens. The attendee sees the new balance next time they look | none |

## 7. Security and integrity

This is the only place in the system where points are spent, so it is the only place they can be
stolen.

- **The whole exchange is one indivisible step (R14, constitution VI).** Balance, stock, the
  duplicate check and the code are verified and changed together or not at all. The failure this
  prevents is a prize handed over without payment, or points taken for a prize that stayed on the
  table. The conditional writes already used today — `WHERE stock > 0` and `WHERE points >= cost`
  — are the pattern, not the friendly pre-checks in front of them.
- **A single-use code is what makes a shown code safe.** A permanent personal code turns a
  photograph, or a glance over a shoulder, into the ability to spend someone else's points at any
  stand. Because a code is good for one exchange and dies with the screen that showed it, a
  photograph is worth nothing by the time it could be used.
- **Codes must be unguessable (R7).** A code derived from the attendee's identity, or issued in
  sequence, would let a stand admin spend the points of an attendee who never came to their stand.
- **The code identifies a person, never a reward (R8).** The stand chooses from its own rewards,
  so a code cannot be redirected at something the attendee did not intend and the stand does not
  hold.
- **Ownership is resolved from the session (R11, R12, constitution IV).** Which rewards a stand
  may hand over follows from who is calling, never from a stand identifier the client supplied.
- **Nothing is committed before confirmation (R6, R16).** Because a code holds nothing, an
  abandoned claim cannot strand stock or points, and there is no timeout to get wrong. The cost is
  accepted and stated: two people can walk towards the same last unit.
- **The attendee's screen is told, not trusted (R21).** It asks whether the exchange happened; it
  never decides that it did. A screen that believes it succeeded proves nothing about a balance.

## 8. Acceptance criteria

- [ ] An attendee can obtain a claim code, and it contains none of `O`, `0`, `I`, `1` or `L`.
- [ ] Asking for a code while one is live returns the same code, not a second one.
- [ ] Asking for a code after the previous one expired returns a new one, and the expired one stays dead.
- [ ] Two requests arriving together produce one live code, and it is the one returned to both.
- [ ] A confirmed handover deducts exactly the reward's cost and exactly one unit of stock,
      together.
- [ ] After a confirmed handover the same code is refused.
- [ ] The attendee's screen closes by itself within a few seconds of confirmation and shows the
      new balance.
- [ ] The stand's screen closes on confirmation and is ready for the next attendee.
- [ ] A claim by an attendee short of points is refused, changes nothing, and leaves the code
      usable.
- [ ] A claim on an out-of-stock reward is refused and changes nothing.
- [ ] A second claim of the same reward by the same attendee is refused.
- [ ] A stand cannot select or confirm another stand's reward, including through the API.
- [ ] Two confirmations racing on the last unit produce exactly one handover.
- [ ] Two confirmations racing on the same code produce exactly one handover.
- [ ] No balance and no stock ever goes below zero.
- [ ] Browsing the catalogue and generating a code deduct nothing.
- [ ] A code stops working shortly after the attendee closes the app.

## 9. Open questions

None blocking. One rule was **derived rather than stated**, and is flagged for confirmation:

- **The 60-second grace period on a code whose screen stopped asking.** The decision taken was
  that a code lives "until it is used or the screen is closed". Closing the app, locking a phone
  or losing signal are none of those, and left alone they would leave a live code with nothing to
  end it. Tying a code's life to its screen still asking about it is what makes the stated rule
  enforceable; sixty seconds is the tolerance chosen so a phone that locks and wakes does not lose
  its code. If a different tolerance is preferred, only this number changes.

## 10. Current behaviour and the gap

The claim exists today, but at the wrong moment and between the wrong parties.

| Requirement | Today |
|---|---|
| R1 to R8 | **Missing entirely.** There is no claim code and no concept of one. |
| R9 to R13 | **Missing.** The stand has no involvement in a claim; it never learns one happened. |
| R14 | **Partially met, in the wrong place.** `claim_reward` already performs the exchange atomically — conditional `UPDATE ... WHERE stock > 0` and `WHERE points >= cost` inside a subtransaction — but it is called by the *attendee*, from the catalogue, with no stand involved. |
| R15 | Met. The subtransaction rolls back everything on failure. |
| R16 | **Contradicted.** Points and stock are deducted the moment the attendee taps the button in `src/pages/Rewards.jsx`. |
| R17 | Met, structurally, by `UNIQUE (participant_id, reward_id)` on `claimed_rewards`. |
| R18 | Met, by `CHECK (points >= 0)`. |
| R19, R20 | R19 is met by the conditional write. R20 does not apply: there are no codes. |
| R21 to R23 | **Missing.** There is nothing to wait for: the exchange completes inside the attendee's own request. |
| R24, R25 | Met in spirit. The refusals are friendly and specific — "Necesitas N puntos más", "¡Agotado!" — but they address the attendee rather than the stand, and carry emoji (spec 016). |

**Consequences the plan must address**

- `claim_reward` is not extended; it is replaced. The caller changes from attendee to stand, the
  arguments change, and the trigger changes from a tap to a confirmation. Its atomic core is the
  part worth keeping.
- A claim code is new state with a lifetime, and its expiry has to be derived rather than swept:
  nothing in this stack runs on a schedule, so a code's liveness must be a question answered at
  the moment it is presented.
- The attendee's claim screen introduces the second polling loop in the system. It is scoped to
  one open screen and one exchange, unlike the leaderboard's, and must stop when the screen does.
- `claimed_rewards` gains the stand that confirmed the handover, which is also what spec 024 needs
  in order to record it.

## 10b. As built

`supabase/postgres-init/54_fulfilment.sql`. `claim_reward` is gone: leaving it would have left a
second way to spend points, with no stand and no handover.

A code's life is derived from the screen still asking about it — `poll_my_claim_code` bumps
`last_seen_at`, and a code is dead once that is older than `claim_code_grace()`. Nothing sweeps,
for the same reason an activity's state is derived: nothing in this stack runs in the background.

**A bug the browser found that the tests would not have.** The claim screen remounting issued two
codes in the same second, and the one left open was not necessarily the one on display — the
attendee would have shown a stand a code that had already been replaced. `issue_claim_code` now
returns the live code if one exists (R4a), and the screen discards a result that arrives after it
was torn down. It also stopped swallowing every polling failure: a run of them now says so, since
that silence is what hid the bug.

**Verified end to end in the browser**, both sides: the code is issued and displayed; a stand
confirms with the code typed in lower case; points and stock move together; and the attendee's
screen closes itself within a few seconds showing the prize and the new balance. Refusals were
checked for an unaffordable prize, a prize already claimed, and a prize belonging to another
stand — each leaving the code usable.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), VI (defence in
  depth for the point economy).
- ADR 0003 — polling instead of realtime, which R21 follows rather than reopens.
- ADR 0004 — the atomic claim, whose pattern R14 keeps.
- Glossary: *Claim*, *Fulfilment*, *Reward*, *Points*.
- Spec 021 — `stand-reward-management`, which defines what is being handed over.
- Spec 019 — `stand-activity-catalogue`, which introduces the stand console's sections.
- Spec 024 — `system-audit-log`, which records confirmed handovers.
- Spec 016 — `naming-and-hygiene-cleanup`, which removes the emoji from these messages.
