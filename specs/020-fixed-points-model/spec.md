# Spec 020 — Fixed points model

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `020-fixed-points-model` |
| **Actors** | Participant, Stand admin |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Points are the only currency in the fair, and today every stand mints its own. A stand can set a
visit at 30 points while its neighbour sets 5, so two attendees who walked the same route end up
with wildly different totals, and the leaderboard stops measuring effort and starts measuring
which stands you happened to visit. There is no incentive for a stand to be modest, and no way
for the organiser to know what the fair is worth in total.

This spec fixes the value of everything the system awards. A visit is worth the same everywhere.
An activity is worth one of two amounts, decided by whether it is the stand's headline event, not
by the stand's generosity. From that point on the leaderboard compares attendees, and reward
costs can be set against an economy whose size is known in advance.

## 2. Scope

**In scope**

- What a visit awards, and how often the same stand can award one to the same attendee.
- What an activity awards, and how many times an attendee can complete it.
- Which of a stand's activities may carry the higher award.
- Removing the stand's ability to set any of these.
- What happens to points already awarded when the thing that awarded them changes.

**Out of scope**

- The activities themselves — creating them, their names, schedules and limit of three per
  stand. That is spec 019; this spec only says what completing one is worth.
- How a scan is validated, signed or entered manually. Specs 002, 003 and 011 are unchanged by
  this: only the amount they award changes.
- What rewards cost, and the ceiling on that cost. Spec 021.
- Changing these values during an event. They are constants; see R3 and section 5.

## 3. User scenarios

### 3.1 Two attendees walk different routes

**Given** attendee A visits five stands and attendee B visits five different stands
**When** neither completes any activity
**Then** both have exactly the same number of points, because a visit is worth the same
everywhere.

### 3.2 An attendee completes a stand's headline activity

**Given** a stand whose main event is a workshop, plus two other activities
**When** an attendee completes all three
**Then** they receive 30 points for the main event and 10 for each of the others.

### 3.3 An attendee tries to repeat an activity

**Given** an attendee already completed a stand's workshop
**When** they scan that activity's code again, or type its manual code
**Then** nothing is awarded and they are told they already took part in that activity. Their
balance does not change.

### 3.4 An attendee passes a stand again later

**Given** an attendee was awarded a visit at a stand
**When** they scan that stand's visit code again within half an hour
**Then** nothing is awarded and they are told how long is left before that stand counts again.

**When** they scan it again after half an hour has passed
**Then** they are awarded a visit as normal.

### 3.5 A stand corrects an activity after people have done it

**Given** twelve attendees have completed an activity
**When** the stand renames it, or removes it entirely
**Then** none of those twelve loses a point. The leaderboard does not move.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | A visit MUST award the same number of points at every stand. | Must |
| R2 | A visit MUST award 10 points. | Must |
| R3 | No award value in this spec MUST be settable by a stand, by an attendee, or by anything sent from a client. | Must |
| R4 | An attendee MUST be able to be awarded a visit at the same stand again, no sooner than 30 minutes after the previous awarded visit at that stand. | Must |
| R5 | There MUST be no limit on how many visits an attendee accumulates at one stand beyond the interval in R4. | Must |
| R6 | Completing an activity MUST award 30 points when that activity is its stand's main event, and 10 points otherwise. | Must |
| R7 | A stand MUST have at most one main event. | Must |
| R8 | An attendee MUST be able to be awarded points for a given activity at most once, for the whole event. | Must |
| R9 | A repeated attempt at an already completed activity MUST be refused with a message saying the attendee already took part in it, identically whether it arrives by camera or by manual code. | Must |
| R10 | The amount awarded MUST be determined by the system at the moment of the award, and MUST NOT be read from anything the client supplied. | Must |
| R11 | Points already awarded MUST NOT be withdrawn when the activity or stand that awarded them is renamed, edited or deleted. | Must |
| R12 | A balance MUST never be negative. | Must |
| R13 | The refusals in R4 and R9 MUST NOT be reported as errors: the attendee did nothing wrong, and the message MUST say what happened and, for R4, when they can return. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Visit award | 10 points, event-wide | The value the system already used by default, so the feel of the game does not change. Making it event-wide is the whole point of this spec: a visit has to mean the same thing everywhere for the leaderboard to compare people rather than routes. |
| Visit cooldown | 30 minutes, per stand | Long enough that standing in front of a QR is a bad use of an afternoon, short enough that genuinely passing a stand again later is rewarded. The previous 5 minutes made camping viable; a hard limit of one visit would punish attendees who legitimately come back. |
| Visit cap per stand | None | The cooldown already makes farming unattractive, and a hard cap would refuse an attendee who spent the whole fair helping at one stand. Accepted risk, quantified below. |
| Main event award | 30 points | Three times a visit, so the headline activity is worth crossing the fair for. |
| Ordinary activity award | 10 points | Equal to a visit: taking part in something is worth at least showing up, without competing with the main event. |
| Main events per stand | At most 1 | Without a limit, every stand marks all three activities as main events and the distinction disappears — there is no cost to doing so. One per stand also caps a stand's activity value at 50 points (30 + 10 + 10), which keeps stands comparable. |
| Completions per activity | 1 per attendee, for the event | An activity has a schedule and a duration; doing it twice is not a thing that happens. Repeating it is farming. |
| Award values are constants | Change requires a deployment | These values define the economy that reward costs are set against. Changing them mid-event would silently revalue every prize and every position on the leaderboard. |
| Points already awarded | Never withdrawn | A leaderboard that moves backwards destroys trust in it faster than any other failure. Editing a typo in an activity name must never cost anyone a place. |

### What the economy is worth

The ceiling on reward costs (spec 021) has to be set against these numbers, so they are recorded
here. At the reference scale of 10 stands over a 6-hour fair:

| Source | Per stand | Across 10 stands |
|---|---|---|
| Activities (1 main event + 2 others) | 50 | 500 |
| Visits, one pass | 10 | 100 |
| Visits, theoretical maximum (12 cooldown windows) | 120 | 1200 |

A realistic attendee who walks the fair once and takes part in everything lands around **600
points**. The theoretical maximum is far higher, but reaching it means re-scanning ten stands
every half hour for six hours and doing nothing else.

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown to the attendee |
|---|---|---|
| Second visit to a stand within 30 minutes | Nothing awarded, balance unchanged | "Ya visitaste este stand. Espera N minuto(s) para volver a registrar una visita." |
| Second visit exactly at 30 minutes | Awarded | none |
| Repeating a completed activity | Nothing awarded, balance unchanged | "Ya participaste en esta actividad." |
| Repeating a completed activity by manual code | Identical to the camera path | as above |
| A stand marks a second activity as its main event | Refused; the stand is told it already has one | (stand-facing, defined in spec 019) |
| A stand has no main event | Allowed. All its activities award 10 | none |
| A payload arrives asking for more points than the rule allows | The rule's value is awarded, not the requested one | none — the attendee sees the correct award |
| A payload arrives asking for negative points | Nothing is subtracted; the award is never below zero | none |
| An activity is deleted after completions | Those points stay. The attendee's history may show an activity that no longer exists | none |
| A stand is deleted after awards | Those points stay | none |
| An attendee's balance would go below zero | Impossible: refused before it can happen | (claim-side; spec 018) |

## 7. Security and integrity

This spec defines the amounts, so it is the definition of what cheating would be worth.

- **The award is computed, never accepted (R10, constitution III).** The client is public: the
  payload it presents is untrusted input. Whatever number arrives, the amount written is the one
  the rule says. This already holds today and must survive the change from per-stand values to
  fixed ones — it is easier to get right now, because the correct value no longer depends on
  which stand is involved.
- **Both limits must be structural (constitution VI).** Neither the 30-minute cooldown nor the
  one-completion-per-activity rule may rest on a check performed before the write. Two scans
  arriving in the same instant must not both succeed. Uniqueness of completions has an obvious
  structural form; the cooldown needs the acting attendee's row to be locked before it is
  evaluated, exactly as the current implementation already does for the 5-minute rule.
- **Removing per-stand configuration removes an attack surface.** A stand admin can no longer
  raise their own award values, so the ceiling checks that exist to contain that are no longer
  containing anything a stand controls. The clamp stays anyway, because the payload is still
  untrusted.
- **Never subtract on a scan.** A scan is a credit or nothing. No path through this spec may
  reduce a balance; spending happens only in spec 018.
- **R11 is an integrity rule, not a convenience.** Withdrawing points after the fact would make
  the leaderboard non-monotonic, and there is no way for an attendee to tell that from a bug.

## 8. Acceptance criteria

- [ ] A visit awards 10 points at every stand, with no stand able to change it.
- [ ] A second visit to the same stand 29 minutes later is refused and says how long is left.
- [ ] A second visit to the same stand 31 minutes later is awarded.
- [ ] A stand's main event awards 30 points; its other activities award 10.
- [ ] A stand cannot mark a second activity as its main event.
- [ ] A stand with no main event has all its activities award 10.
- [ ] Completing an activity twice is refused, and the message is the same by camera and by
      manual code.
- [ ] A payload requesting 9999 points awards the rule's value instead.
- [ ] A payload requesting negative points never reduces a balance.
- [ ] Two scans of the same activity arriving simultaneously produce exactly one award.
- [ ] Two visit scans at the same stand arriving simultaneously produce exactly one award.
- [ ] Renaming an activity leaves every existing balance untouched.
- [ ] Deleting an activity leaves every existing balance untouched.
- [ ] No stand-facing screen offers a control for any award value.

## 9. Open questions

None blocking. One value is deliberately owned elsewhere:

- The maximum a reward may cost is a rule of spec 021. It has to be set against the figures in
  section 5, and 021 cannot be approved without it.

## 10. Current behaviour and the gap

Every rule in this spec replaces something that ships today.

| Requirement | Today |
|---|---|
| R1, R2, R3 | **Contradicted.** Each stand carries its own `visit_points`, default 10, constrained to 0–30, and its admin edits it from the stand console (`src/pages/admin/AdminDashboard.jsx`). |
| R4 | **Changes value.** A 5-minute cooldown is enforced in `validate_and_scan`, with the participant row locked first. The mechanism is correct and stays; only the interval changes. |
| R5 | Already true. Nothing caps total visits. |
| R6, R7 | **Does not exist.** There are no activities as entities. `activity` is a scan type, and its award comes from the stand's own `activity_points`, default 25, constrained to 0–100. There is no notion of a main event. |
| R8 | **Changes meaning.** Today an attendee may complete one activity *per stand*, enforced by the partial unique index `scans_one_activity_per_stand` on `(participant_id, community_id)`. It becomes one completion *per activity*, so the guarantee has to move to the activity. |
| R9 | Partially met. The refusal exists and reads "Ya registraste esta actividad en este stand"; it will need to name the activity rather than the stand, and lose its emoji (spec 016). |
| R10 | **Already met, and must stay met.** `validate_and_scan` re-clamps with `GREATEST(0, LEAST(...))` against the stand's ceilings. This came from audit finding F3 and is not to be relaxed. |
| R11 | Untested. Nothing deletes activities today because they do not exist; scans cascade on stand deletion, which **would** remove the history, though the balance itself is a separate column and survives. |
| R12 | Already met, by `CHECK (points >= 0)`. |
| R13 | Partially met. The messages exist and are friendly, but carry emoji. |

**Consequences the plan must address**

- The per-stand award columns and their `CHECK` constraints are removed, and the stand console
  loses that section. The `CHECK` values 30 and 100 disappear with them — the new constants are
  10, 10 and 30.
- The uniqueness guarantee has to move from `(participant_id, community_id)` to the activity, and
  that cannot happen before activities exist (spec 019). **019 and 020 are one deployment.**
- Existing rows recorded under the old model cannot be migrated meaningfully. The initialisation
  scripts run once on an empty volume, so this ships as a fresh deployment between events, never
  during one.
- The QR payload currently carries the award amount and the scan type. With fixed values it no
  longer needs to carry the amount at all, and with per-activity awards it needs to carry which
  activity. Both are signature changes, coordinated with specs 019 and 011.

## 11. References

- Constitution: III (rules in the database), VI (defence in depth for the point economy).
- ADR 0004 — business rules in Postgres, and the audit findings behind the clamps.
- Glossary: *Points*, *Visit*, *Activity*.
- Spec 019 — `stand-activity-catalogue`, which creates the activities this spec prices. Ships
  together with this one.
- Spec 021 — `stand-reward-management`, which sets reward costs against the economy defined here.
- Spec 011 — `qr-projection`, which must let a stand choose which activity it is showing.
- Spec 016 — `naming-and-hygiene-cleanup`, which removes the emoji from these messages.
