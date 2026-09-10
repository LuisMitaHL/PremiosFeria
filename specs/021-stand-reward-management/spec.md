# Spec 021 — Stand reward management

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `021-stand-reward-management` |
| **Actors** | Stand admin, Participant, Event operator |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 (amended after spec 023) |

## 1. Purpose

Rewards are why anyone collects points. Today they can only be loaded from a CSV file the
operator drops in before Postgres starts for the first time, which means a stand that turns up on
the day with a box of t-shirts cannot offer them, and a stand that runs out cannot say so. The
people who own the prizes have no way to touch the catalogue that lists them.

This spec gives each stand its own catalogue: they register what they brought, how much of it
they have, and what it costs. Attendees see the whole fair's rewards in one place, with what they
can afford and what is gone. What a stand may change afterwards is deliberately narrow — the
price is a promise made to everyone saving towards it, and a promise that can be raised is not
one.

## 2. Scope

**In scope**

- A stand registering its own rewards.
- What a reward is: its name, cost, stock, icon and optional description, and their limits.
- Who may change a cost, and who may change a stock, after publication.
- The ceiling on what a reward may cost, set against the economy defined in spec 020.
- What an attendee sees in the catalogue, including what is out of stock and what they cannot
  yet afford.

**Out of scope**

- Claiming a reward. Spec 018 owns the whole exchange, including when stock and points are
  actually deducted.
- The organiser's screens for adjusting a cost or reducing a stock. Spec 023 builds those; this
  spec only says that the authority is theirs and nobody else's.
- Photographs of prizes. The system has no file storage, and adding it would block the entire
  reward flow behind new infrastructure. Icons only, as today.
- Seeding rewards from CSV at first boot. Spec 012 documents that; it stops being the only way in
  but is not removed here.

## 3. User scenarios

### 3.1 A stand publishes what it brought

**Given** a stand setting up before the fair
**When** they register "Polera Community Day XL" at 200 points, 3 in stock, with an icon
**Then** it appears in every attendee's catalogue, attributed to that stand.

### 3.2 More prizes arrive mid-fair

**Given** a reward with 1 unit left
**When** the stand receives four more and raises the stock to 5
**Then** attendees see five available.

### 3.3 A stand runs out

**Given** a reward whose last unit has been handed over
**When** an attendee opens the catalogue
**Then** they can see the reward existed and is now out of stock, and cannot claim it.

### 3.4 A stand wants to stop offering something

**Given** a stand that decides not to give away a prize after all
**When** they set its stock to zero
**Then** it shows as out of stock. There is no other way to withdraw it, and it is never deleted.

### 3.5 An attendee is saving towards a prize

**Given** an attendee with 150 points looking at a 200-point reward
**When** they open the catalogue
**Then** they can see they do not have enough yet, and they can be sure that number will not go
up while they earn the difference.

### 3.6 A price was set wrong

**Given** a stand that registered a prize at 20 points instead of 200
**When** they try to correct it
**Then** they cannot: the price is fixed at creation. They ask the organiser, who changes it.

## 4. Requirements

### Registering a reward

| ID | Requirement | Priority |
|---|---|---|
| R1 | A stand MUST be able to register rewards of its own, with no limit on how many. | Must |
| R2 | Registering a reward MUST require a name, a cost, an initial stock and an icon. A description is optional. | Must |
| R3 | A name MUST be between 3 and 40 characters; a description MUST be at most 100 characters; a cost MUST be between 0 and 300 points; a stock MUST be zero or more. | Must |
| R4 | These limits MUST be enforced where the data is stored, not only in the form. | Must |
| R5 | The icon MUST be chosen from a fixed set the system offers. Free text MUST NOT be accepted in its place. | Must |
| R6 | A reward MUST belong to exactly one stand, and MUST be attributed to it wherever it is shown. | Must |
| R7 | A reward MUST NOT be deleted, ever. | Must |

### Cost

| ID | Requirement | Priority |
|---|---|---|
| R8 | The cost MUST be set by the owning stand at the moment the reward is registered. | Must |
| R9 | A stand MUST NOT be able to change a reward's cost afterwards, in any direction. | Must |
| R10 | A cost MUST NOT exceed 300 points. | Must |
| R11 | Only the event organiser MUST be able to change a published cost. **Deferred: the screen for it is spec 023, so until that ships a cost cannot be changed at all.** | Must (deferred) |

### Stock

| ID | Requirement | Priority |
|---|---|---|
| R12 | A stand MUST be able to increase the stock of its own rewards at any time. | Must |
| R13 | A stand MUST NOT be able to decrease a stock. | Must |
| R14 | Only the event organiser MUST be able to decrease a stock. **Deferred alongside R11.** | Must (deferred) |
| R15 | Stock MUST decrease by exactly one when a claim is confirmed, as defined by spec 018. | Must |
| R16 | Stock MUST never fall below zero. | Must |
| R17 | Setting stock to zero MUST be the only way **a stand** withdraws a reward from circulation. | Must |
| R17a | The organiser MUST be able to withdraw any reward outright, as a state rather than a deletion. Defined by spec 023, R22 to R25. | Must (delivered by 023) |

### The attendee's catalogue

| ID | Requirement | Priority |
|---|---|---|
| R18 | An attendee MUST be able to see the rewards of every stand in one place, each showing its name, cost, icon, owning stand and whether it is available. | Must |
| R19 | A reward with zero stock MUST be shown as out of stock and MUST NOT be claimable. | Must |
| R19a | A reward withdrawn by the organiser, or belonging to a withdrawn community, MUST likewise be shown as unavailable and MUST NOT be claimable. | Must |
| R20 | A reward with zero stock MUST remain visible rather than disappearing from the catalogue. | Must |
| R21 | A reward an attendee cannot yet afford MUST be visibly distinguishable from one they can, before they attempt anything. | Must |
| R22 | Attempting to claim a reward the attendee cannot afford MUST be refused with a message saying the balance is insufficient. | Must |
| R23 | The refusals in R19 and R22 MUST be decided where the claim is decided, not only by disabling a control on screen. | Must |
| R24 | An attendee SHOULD be able to see how many points they still need for a reward they cannot afford. | Should |

### Stand console

| ID | Requirement | Priority |
|---|---|---|
| R25 | Rewards MUST be one of the three sections of the stand console, alongside activities and claims. | Must |
| R26 | The rewards section MUST show each reward's remaining stock, so the stand knows what it still has to hand over. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Maximum cost | 300 points | Half of what a full pass through the fair yields under spec 020 (~600). An attendee who does half the fair can already aim at the most expensive prize, and one who does all of it can take two. A ceiling at 600 would make the top prize reachable only by someone who missed nothing all day, and anything above it would be claimed by nobody. |
| Minimum cost | 0 points | A stand may want to give something away to anyone who turns up. Nothing breaks: the claim still has to be confirmed in person. |
| Rewards per stand | Unlimited | Stock already bounds what a stand can hand over, so a count limit would constrain how they describe their prizes without constraining anything real. |
| Cost after publication | Stand cannot change it; organiser can | An attendee saves towards a number. A price a stand can raise is not a promise, and the attendee has no way to know it moved. Lowering only would be safe, but a single rule — the stand sets it once, the organiser corrects mistakes — is simpler to hold in mind and leaves a record of who changed what. |
| Stock increases | Stand, freely | It is their own inventory. More boxes arrive; nothing about what a prize costs anyone changes. |
| Stock decreases | Organiser only | Reducing stock takes away something attendees can already see and may be walking towards. Removing by attrition — letting it run out — is honest; removing it silently is not. |
| Withdrawal by a stand | Set stock to zero | An out-of-stock reward is already a state the catalogue handles, so no second concept is needed for the stand. Nothing is deleted, so a confirmed claim always points at a reward that still exists. |
| Withdrawal by the organiser | An explicit state, never a deletion | Spec 023 gives the organiser the power to take anything off the shelf, including a prize that is in stock. It is a state for the same reason nothing else here is deleted: a handover already confirmed must still name something real. |
| Name length | 3 to 40 characters | Same limit as an activity name, for the same reason: it has to render in a card and in a list. |
| Description length | Up to 100 characters, optional | Prize names usually explain themselves. Requiring a description for a keyring is friction with no benefit. |
| Icon | From a fixed set | The system has no file storage, and adding it would block the entire reward flow behind new infrastructure. A fixed set also keeps every card the same shape. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A stand registers a reward costing 301 | Refused | "El costo no puede superar los 300 puntos." (stand) |
| A stand registers a reward with no icon | Refused | "Elige un ícono para el premio." (stand) |
| A stand tries to change a cost | Refused, and told who can | "Solo el organizador puede cambiar el costo de un premio." (stand) |
| A stand tries to lower a stock | Refused, and told who can | "Solo el organizador puede reducir el stock." (stand) |
| A stand raises stock while a claim is being confirmed | Both succeed; the stock reflects the increase minus the claim | none |
| The last unit is claimed while an attendee is looking at the catalogue | The catalogue shows it out of stock on its next refresh; any attempt is refused | "Ya no quedan unidades de este premio." |
| Two attendees try to claim the last unit at once | Exactly one succeeds; the other is refused | as above |
| An attendee with 150 points views a 200-point reward | Shown as unaffordable, with the shortfall | "Necesitas 50 puntos más." |
| An attendee attempts to claim it anyway, bypassing the screen | Refused | as above |
| A reward is registered with 0 stock | Appears immediately as out of stock | none |
| A stand registers two rewards with the same name | Both exist. Names are labels, not identifiers | none |
| A stand has no rewards | Its section is empty and it contributes nothing to the catalogue | none |

## 7. Security and integrity

A reward's cost and stock are the two halves of what a claim spends, so both belong to the point
economy.

- **The cost ceiling must be structural (constitution VI).** R10 is not advice to the form. A
  stand admin holds a session and can call the API directly, so the 300-point limit has to be a
  constraint where the value is stored.
- **Authority is per row, not per role (constitution IV).** A stand may only touch its own
  rewards, resolved from the session and never from an identifier the client sent. This is the
  rule that already scopes stand profile edits and code signing.
- **The direction of a change is itself a rule.** R9 and R13 are not "the button is missing":
  raising a cost or lowering a stock has to be refused where the write happens, or a stand admin
  does both with a single API call.
- **Stock is spent, not displayed (R15, R16).** The decrement belongs to the confirmed claim in
  spec 018 and must be a conditional write, so the last unit cannot be handed to two people.
  Nothing here may offer another path that decrements it.
- **Affordability is decided at the claim, not in the catalogue (R23).** The catalogue is a
  courtesy: it greys out what cannot be claimed so nobody crosses the fair for nothing. The
  refusal that matters happens where the points are spent, against a balance read at that moment.
- **Never deleting means a claim always resolves.** Because rewards are withdrawn only by running
  out of stock, a claim recorded today still names something that exists tomorrow, and the
  organiser's log (spec 024) never points at a hole.

## 8. Acceptance criteria

- [ ] A stand can register a reward with a name, cost, stock and icon, and no description.
- [ ] A reward costing 300 is accepted; one costing 301 is refused, including through the API.
- [ ] A 41-character name and a 101-character description are each refused.
- [ ] A reward with no icon is refused.
- [ ] A stand can raise its own stock.
- [ ] A stand cannot lower a stock, and cannot change a cost in either direction, including
      through the API.
- [ ] A stand cannot touch another stand's rewards.
- [ ] A reward at zero stock appears in the catalogue marked as out of stock and cannot be claimed.
- [ ] An attendee sees which rewards they cannot afford, and how many points they are short.
- [ ] Claiming an unaffordable reward is refused even when the request bypasses the screen.
- [ ] Two simultaneous claims on the last unit result in exactly one handover.
- [ ] Stock never becomes negative.
- [ ] No reward can be deleted.

## 9. Open questions

None. Three requirements — R11, R14 and R17a — are deferred rather than open: the authority is
decided, but the organiser's screens that exercise it belong to spec 023.

**Amended after spec 023 was written.** Two things changed there and are reflected above:
the organiser can withdraw a reward outright (R17a, R19a), and a community no longer edits its own
profile — which removes the stand console section that would otherwise have sat beside this one.

## 10. Current behaviour and the gap

| Requirement | Today |
|---|---|
| R1, R2 | **Missing.** A stand cannot register anything. Rewards enter only through `seed/rewards.csv`, loaded once at first Postgres init (`supabase/postgres-init/70_seed.sql`). |
| R3, R4 | Partially met. `rewards` already constrains `cost >= 0` and `stock >= 0`. There is no upper bound on cost and no length limit on name or description. |
| R5 | Met in substance. The column is called `emoji` but holds a Lucide icon name, and the stand console already offers a fixed set of 16 for the stand's own icon (`src/pages/admin/AdminDashboard.jsx`). The column name is legacy — see the glossary. |
| R6 | Met. `rewards.community_id` references the owning stand and the catalogue already joins it. |
| R7 | Met by omission. Nothing deletes rewards, because nothing manages them. |
| R8 to R11 | **Missing.** Cost is whatever the CSV said, and nothing can change it — including the organiser, who has no panel. |
| R12 to R14 | **Missing.** Stock is whatever the CSV said. There is no way to replenish, which is the sharpest operational gap today. |
| R15, R16 | Met, and must stay met. `claim_reward` decrements with `UPDATE ... WHERE stock > 0` inside a subtransaction, backed by `CHECK (stock >= 0)`. Spec 018 moves *when* this happens, not *how* it is guarded. |
| R18 to R21 | Largely met. `src/pages/Rewards.jsx` renders a grid with the owning stand, remaining stock, cost, and badges for claimed and out-of-stock, disabling the button when the balance is short. |
| R22, R23 | Met. `claim_reward` refuses with "Necesitas N puntos más" and "¡Agotado!" — messages that keep their meaning but lose their emoji under spec 016. |
| R25, R26 | **Missing.** The stand console has no sections; spec 019 introduces them. |

**Consequences the plan must address**

- Two new abilities on an existing table, each with a direction that must be enforced server-side.
  The current RLS on `rewards` grants no writes at all, so both need a deliberate path.
- The cost ceiling is a new constraint on a table that may already hold rows above it if it was
  seeded that way. Schema changes require a fresh deployment regardless.
- R11 and R14 land with spec 023. Until then a wrong price is corrected by a database operator,
  exactly as stand passwords are today.
- The catalogue itself changes little. Most of the work is the stand-facing section and the two
  write paths.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), VI (structural
  guarantees for the point economy).
- Glossary: *Reward*, *Claim*, *Stand*, and the note on the legacy `emoji` column.
- Spec 020 — `fixed-points-model`, whose figures set the 300-point ceiling.
- Spec 018 — `in-person-reward-fulfilment`, which spends the cost and the stock defined here.
- Spec 019 — `stand-activity-catalogue`, which introduces the stand console's sections.
- Spec 023 — `organizer-community-management`, which delivers R11 and R14.
- Spec 012 — `csv-provisioning`, the seeding path this spec supplements rather than replaces.
- Spec 016 — `naming-and-hygiene-cleanup`, which removes the emoji from the refusal messages.
