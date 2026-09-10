# Spec 023 — Organizer community management

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `023-organizer-community-management` |
| **Actors** | Event operator, Stand admin |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Stands enter the system through a CSV file read once, at the moment Postgres starts for the very
first time. A community that confirms its attendance the night before cannot be added. A password
handed to the wrong person cannot be rotated without a database session. A stand that never turns
up stays in the catalogue all day, offering prizes nobody can collect.

This spec makes the organiser the owner of who the stands are. They create each community, hand
over credentials the system generated, correct the details, reset a password when it goes astray,
and withdraw a stand that is not there. It is the critical path for the whole event: after this,
a community exists because the organiser said so, and there is no other way in.

It also draws a line that did not exist before. The organiser owns **who a community is**; the
community owns **what it does** — its activities, its rewards and its handovers. A stand cannot
rename itself or move its own stand number.

## 2. Scope

**In scope**

- Creating a community and issuing its credentials.
- Correcting a community's details afterwards.
- Resetting a community's password.
- Withdrawing a community from the event and what that does.
- The organiser's authority over any community's rewards, including the two powers spec 021
  deferred here.

**Out of scope**

- The organiser's identity, the panel it lives in, and its home screen. Spec 017.
- A community creating its own activities and rewards, or confirming handovers. Specs 019, 021
  and 018 — those stay with the community.
- Recording who changed what. Spec 024.
- Overriding which activity is a stand's main event. Deliberately excluded: spec 019 freezes that
  field once an activity starts, and no escape valve is granted here. **The consequence is that a
  main event marked on the wrong activity cannot be corrected once it has run.**

## 3. User scenarios

### 3.1 A community is registered

**Given** the organiser preparing the fair
**When** they create a community with its name, its stand number and a login name
**Then** the system produces a password, shows it once, and the organiser copies it and hands it
to that community. It is never shown again.

### 3.2 A community loses its password

**Given** a stand that cannot sign in on the morning of the fair
**When** the organiser resets its password
**Then** a new one is generated and shown once. The previous one stops working immediately.

### 3.3 A detail was wrong

**Given** a community registered as "Codecats" that should read "CodeCats", at stand 7 rather
than 4
**When** the organiser corrects both
**Then** attendees see the corrected details everywhere. Nothing about points changes, and the
community itself could not have made either change.

### 3.4 A community does not turn up

**Given** a community that confirmed but never arrived
**When** the organiser withdraws it
**Then** it can no longer sign in, its codes award nothing, its prizes cannot be claimed and its
activities cannot be started. Every point it awarded before that moment stays exactly where it is.

### 3.5 A prize was priced wrong and the stand cannot fix it

**Given** a stand that published a prize at 20 points instead of 200
**When** they ask the organiser
**Then** the organiser corrects the cost, which is the only way it can be corrected.

### 3.6 A prize should not be on offer

**Given** a prize a community listed by mistake, or one the organiser judges inappropriate
**When** the organiser withdraws it
**Then** it stops appearing as claimable. It is not deleted, so anyone who already received one
keeps their record of it.

## 4. Requirements

### Creating a community

| ID | Requirement | Priority |
|---|---|---|
| R1 | The organiser MUST be able to create a community, and this MUST be the only way one comes into existence. | Must |
| R2 | Creating a community MUST require a display name, a stand number, an icon and a login name. A description is optional. | Must |
| R3 | The login name MUST be unique, compared without regard to case or surrounding whitespace, exactly as sign-in compares it. | Must |
| R4 | The system MUST generate the password. The organiser MUST NOT choose it. | Must |
| R5 | The generated password MUST be shown exactly once, at the moment it is created, and MUST NOT be retrievable afterwards by anyone, including the organiser. | Must |
| R6 | The password MUST be stored only as a hash. | Must |
| R7 | A generated password MUST be strong enough that it does not need to be, and MUST be readable and typable: no characters that are easily confused when copied off a screen. | Must |

### Changing a community

| ID | Requirement | Priority |
|---|---|---|
| R8 | The organiser MUST be able to change a community's display name, stand number, icon and description at any time. | Must |
| R9 | A community MUST NOT be able to change any of those itself. | Must |
| R10 | The login name MUST NOT be changeable after creation. | Must |
| R11 | The organiser MUST be able to reset a community's password, which generates a new one under the same rules as R4 to R7. | Must |
| R12 | Resetting a password MUST invalidate the previous one immediately. | Must |

### Withdrawing a community

| ID | Requirement | Priority |
|---|---|---|
| R13 | The organiser MUST be able to withdraw a community from the event. | Must |
| R14 | A community MUST NOT be deleted, ever. | Must |
| R15 | A withdrawn community MUST NOT be able to sign in. | Must |
| R16 | A withdrawn community's codes MUST award nothing, its activities MUST NOT be startable, and its rewards MUST NOT be claimable. | Must |
| R17 | Withdrawing a community MUST NOT change any balance, remove any scan, or undo any handover. | Must |
| R18 | A withdrawn community's rewards and activities MUST remain visible to attendees, marked as unavailable, rather than vanishing. | Must |
| R19 | The organiser MUST be able to reinstate a withdrawn community. | Must |

### Authority over rewards

| ID | Requirement | Priority |
|---|---|---|
| R20 | The organiser MUST be able to change the cost of any published reward. This delivers R11 of spec 021. | Must |
| R21 | The organiser MUST be able to reduce the stock of any reward. This delivers R14 of spec 021. | Must |
| R22 | The organiser MUST be able to withdraw any reward from the catalogue, whichever community owns it. | Must |
| R23 | Withdrawing a reward MUST be a state it is put into, never a deletion, so a handover already confirmed still names something that exists. | Must |
| R24 | A withdrawn reward MUST NOT be claimable and MUST remain visible, marked as unavailable. | Must |
| R25 | The organiser MUST be able to reinstate a withdrawn reward. | Must |
| R26 | A changed cost MUST still respect the 300-point ceiling of spec 021. | Must |
| R27 | The organiser MUST NOT be able to create or edit a reward on a community's behalf. Registering prizes stays with the stand that owns them. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Who creates communities | The organiser, exclusively | There is no other path in. A single door is what makes the log meaningful and what stops a stand appearing that nobody approved. |
| Who chooses the password | The system | Ten stands provisioned in a hurry the morning of the fair is exactly the situation that produces `meh2026`. Generating it removes the choice, and therefore the mistake. |
| Password visibility | Shown once, never again | Storing something recoverable means storing something stealable. Showing it once and only once is what makes "we only keep a hash" true rather than aspirational. |
| Password alphabet | Excludes characters confused when read off a screen | The credential is copied from one screen and typed on another, often by someone else, in a noisy hall. Every ambiguous character is a failed sign-in at the worst moment. |
| Login name | Set at creation, never changed | It is what was handed to the stand on a slip of paper. Changing it silently invalidates that slip, and there is no channel to tell them. |
| Who owns a community's details | The organiser | Split deliberately: the organiser owns *who a community is*, the community owns *what it does*. A stand renaming itself mid-fair, or moving its own stand number, changes what attendees are looking for on a map the organiser printed. |
| Removal | Withdrawal, never deletion | Scans reference the community that awarded them. Deleting a community would take that history with it and, with the current cascade, silently rewrite what attendees did. Spec 020 R11 says points are never withdrawn; this is how that promise survives a stand that leaves. |
| Reward withdrawal | A state, not a deletion | Same reason. "Total control of the catalogue" is delivered as the power to take anything off the shelf, without breaking the record of what was already handed over. |
| Creating rewards | Not the organiser's | The stand knows what is in its boxes. A second creation path would duplicate spec 021 and put the organiser in the position of guessing stock. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A login name already in use | Refused before anything is created | "Ese nombre de usuario ya existe." |
| A login name differing only in case or spacing | Treated as already in use | as above |
| The organiser navigates away before copying the password | It is gone; the only remedy is a reset | "La contraseña solo se muestra una vez. Restablécela si la perdiste." |
| A community is withdrawn while its admin is signed in | Their next action fails as if signed out | "Tu comunidad ya no está activa." |
| A community is withdrawn while one of its activities is running | The activity stops awarding immediately; it is not left running | attendee sees it as unavailable |
| An attendee tries to claim a withdrawn community's reward | Refused; nothing is spent | "Este premio ya no está disponible." |
| An attendee already claimed a reward later withdrawn | Their record is untouched; they keep what they received | none |
| A withdrawn community is reinstated | It can sign in again; its activities and rewards return to the state they were in | none |
| The organiser sets a cost above 300 | Refused | "El costo no puede superar los 300 puntos." |
| The organiser reduces stock below what was already handed over | Refused. Stock counts what is left, not what existed | "El stock no puede ser menor a cero." |
| The organiser reduces stock to zero | The reward shows as out of stock, exactly as if it had run out | none |
| A password is reset while the stand is signed in | Their current session continues until it expires; the old password no longer signs in | none |

## 7. Security and integrity

This spec creates every credential in the system except the organiser's own.

- **A generated password is only as good as its handling (R4 to R7).** It is produced where it
  cannot be predicted, stored only as a hash, and shown once. Nothing may write it to a log, put
  it in a URL, or return it from any request other than the one that created it.
- **Withdrawal is not deletion, and that is a data-integrity rule (R14, R23).** Scans and
  handovers reference communities and rewards. The current schema cascades deletes, so removing a
  community today would erase the record of what attendees did at it, silently contradicting spec
  020's promise that points are never withdrawn.
- **Withdrawal must be enforced where the rules are (R15, R16, constitution III).** Hiding a
  withdrawn community from a screen achieves nothing: its codes are already in the world and its
  admin already holds a session. Signing in, awarding a point, starting an activity and confirming
  a handover must each check it, in the database.
- **Only the organiser may do any of this (constitution IV).** Every action here is scoped to an
  organiser session resolved server-side. A stand admin calling these endpoints must be refused,
  including on its own community, since R9 exists precisely to stop that.
- **The ceiling binds the organiser too (R26).** Authority to correct a price is not authority to
  break the economy. The 300-point constraint is structural and binds every writer.
- **Reinstatement must not resurrect more than it withdrew (R19, R25).** Bringing a community back
  restores its ability to act; it must not restart a finished activity or refill a stock.

## 8. Acceptance criteria

- [ ] Only the organiser can create a community, and there is no other way one appears.
- [ ] Creating one produces a password shown exactly once and never again.
- [ ] The generated password contains no character that is confusable when read off a screen.
- [ ] A duplicate login name, including one differing only in case or spacing, is refused.
- [ ] The organiser can change a community's name, stand number, icon and description.
- [ ] A community cannot change any of those itself, including through the API.
- [ ] A login name cannot be changed after creation.
- [ ] Resetting a password invalidates the previous one immediately.
- [ ] A withdrawn community cannot sign in.
- [ ] A withdrawn community's codes award nothing and its activities cannot be started.
- [ ] A withdrawn community's reward cannot be claimed.
- [ ] Withdrawing a community changes no balance and removes no scan or handover.
- [ ] No community and no reward can be deleted.
- [ ] The organiser can change any reward's cost, and is refused above 300.
- [ ] The organiser can reduce stock, and is refused below zero.
- [ ] The organiser can withdraw and reinstate any reward.
- [ ] The organiser cannot create or edit a reward on a community's behalf.
- [ ] A stand admin calling any organiser endpoint is refused and receives no data.

## 9. Open questions

None. Two decisions taken during the interview reshaped specs already written, and are recorded
here rather than left implicit:

- **A community loses control of its own profile.** Name, stand number, icon and description move
  to the organiser. The stand console keeps only activities, rewards and handovers.
- **"Total control of the catalogue" is delivered as withdrawal, not deletion.** The organiser can
  take any reward off the shelf; nothing is erased, so a confirmed handover always still names
  something real. Spec 021 is amended to match.

## 10. Current behaviour and the gap

| Requirement | Today |
|---|---|
| R1 to R7 | **Missing.** Communities exist only if they were in `seed/stands.csv` when the database first started. Passwords come from that file in plain text, chosen by whoever wrote it, and are hashed on load. |
| R8, R9 | **Contradicted, both halves.** The community edits its own name, icon, stand number and description from its console (`src/pages/admin/AdminDashboard.jsx`), and the organiser can edit nothing. This spec reverses that. |
| R10 | Met by omission. Nothing changes a login name because nothing changes anything. |
| R11, R12 | **Missing.** Rotating a password means running an `UPDATE ... crypt(...)` by hand, as the README documents. This is the sharpest operational gap in the system today. |
| R13 to R19 | **Missing, and currently dangerous.** There is no withdrawal. Deleting a community is possible directly in the database, and `scans` and `rewards` cascade from it, so doing so during an event would erase attendees' history. |
| R20, R21 | **Missing.** Deferred here by spec 021. |
| R22 to R25 | **Missing.** Rewards have no withdrawn state; spec 021 leaves a stand only the option of setting stock to zero. |
| R26 | Depends on spec 021, which introduces the ceiling. |
| R27 | Met by omission. |

**Consequences the plan must address**

- Communities gain a withdrawn state, and so do rewards. Both are checked at sign-in, at every
  award and at every handover, which touches nearly every rule already written.
- The cascade from `communities` to `scans` and `rewards` is why deletion is forbidden. The plan
  should say whether the cascade itself is worth changing, or whether forbidding deletion is
  enough.
- Password generation with one-time display needs a path that returns the value exactly once and
  stores only its hash. It is the one place in the system where a secret is deliberately returned
  to a client, and the plan must show why that is safe.
- The stand console loses its profile section entirely, leaving the three sections spec 019
  introduced.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), V (secrets never
  reach the client).
- ADR 0002 — the auth service, and why stands authenticate the way they do.
- Glossary: *Stand*, *Event operator*, *Reward*.
- Spec 017 — `organizer-admin-panel`, the panel this lives in.
- Spec 021 — `stand-reward-management`, whose R11 and R14 this delivers, and which R22 to R25
  amend.
- Spec 019 — `stand-activity-catalogue`, whose stand console sections this leaves untouched.
- Spec 020 — `fixed-points-model`, whose R11 is why withdrawal is not deletion.
- Spec 024 — `system-audit-log`, which records everything in this spec.
