# Spec 013 — Participant dashboard

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `013-participant-dashboard` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

The home screen is where an attendee lands after registering and where they return between stands.
It exists to answer three things at a glance: how am I doing, what is happening right now, and is
anything within my reach yet.

Today it answers the first badly and the other two not at all. One of its four figures — the count
of prizes claimed — is hardcoded to zero and has been since the screen was written, so an attendee
who has collected two prizes is told they have none. There is no way to see that a workshop is
running two stands away. And nothing tells someone with 210 points that four prizes just became
affordable, which is the single most motivating thing the system knows about them.

## 2. Scope

**In scope**

- The attendee's balance.
- Their progress: stands visited and activities completed, against what the fair offers.
- What is running right now, in summary, with a way through to the full list.
- How many published rewards their current balance can reach.
- The recent-activity feed and the stands list that already exist.

**Out of scope**

- The full activities screen. Spec 025 owns it; this screen only previews it.
- The rewards catalogue. Spec 021 owns it; this screen only counts what is reachable.
- Earning or claiming anything. Nothing on this screen changes a balance.
- The leaderboard. Its own destination, spec 007.

## 3. User scenarios

### 3.1 Arriving back from a stand

**Given** an attendee who has just been awarded points
**When** they open the home screen
**Then** they see their new balance, and that their progress through the fair has moved.

### 3.2 Something is happening

**Given** two activities running at different stands
**When** the attendee opens the home screen
**Then** they can see that something is on right now, and reach the full list in one step.

### 3.3 A prize comes within reach

**Given** an attendee who crosses 200 points
**When** they look at the home screen
**Then** the number of prizes they can afford has gone up, which is the reason to keep going.

### 3.4 Counting what is left

**Given** an attendee who has visited six of ten stands and completed four of fifteen activities
**When** they look at their progress
**Then** they can see both numbers against their totals, and know the fair is not finished with
them.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The screen MUST show the attendee's current balance, prominently. | Must |
| R2 | The screen MUST show how many stands the attendee has visited, against the number of stands in the fair. | Must |
| R3 | The screen MUST show how many activities the attendee has completed, against the number published across the fair. | Must |
| R4 | The screen MUST show how many published rewards the attendee's current balance can afford. | Must |
| R5 | The count in R4 MUST exclude rewards that are out of stock, withdrawn, already claimed by this attendee, or belong to a withdrawn community. | Must |
| R6 | The screen MUST show, in summary, which activities are running at that moment, and MUST offer a way through to the full activities screen. | Must |
| R7 | The screen MUST NOT display a figure it cannot compute. Any number shown MUST be real. | Must |
| R8 | The screen MUST continue to list the fair's stands, marking those the attendee has visited. | Must |
| R9 | The screen MUST continue to show the attendee's recent awards, most recent first, with how long ago each happened. | Must |
| R10 | The screen MUST reflect a change in the attendee's balance without them reloading it. | Should |
| R11 | Every figure MUST be about this attendee, derived from their own session. | Must |
| R12 | With nothing yet to show — no stands, no activities, no awards — the screen MUST say so plainly rather than show zeroes without explanation. | Must |
| R13 | Nothing on this screen MUST award, spend or change anything. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Progress shown against a total | Always | "Six stands visited" means nothing on its own. "Six of ten" is the only form that tells an attendee whether they are nearly done or barely started. |
| Rewards within reach | Affordable, in stock, available, not already claimed | A count that includes prizes they cannot actually get is worse than no count: it promises something the catalogue then takes away. |
| Balance composition | Not shown | Considered and rejected: splitting the balance into earned-by-visit, earned-by-activity and spent is accounting, and the attendee's question is "what can I get", not "where did this come from". The organiser's log answers the accounting question. |
| No fabricated figures | Always | The current screen shows a hardcoded zero for prizes claimed, which is worse than showing nothing: it is confidently wrong, and an attendee holding two prizes has no reason to trust the other three numbers either. |
| Freshness | The balance reflects awards without a reload | An attendee looks at this screen immediately after being scanned. A stale number there reads as a scan that did not work, and sends them back to the stand. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A brand new attendee | Zero balance, zero progress against real totals, and an invitation to start | "Escanea el código de un stand para empezar." |
| No stands exist yet | The stands list says so; progress shows against zero without dividing by it | "No hay stands registrados aún." |
| No activities published anywhere | The activity figures say so rather than showing 0 of 0 | "Todavía no hay actividades publicadas." |
| Nothing is running right now | The summary says so | "Ninguna actividad en curso." |
| No rewards published yet | The reachable count says so rather than showing zero | "Todavía no hay premios publicados." |
| The attendee can afford nothing yet | Zero reachable, with the shortfall to the cheapest available one | "Te faltan N puntos para tu primer premio." |
| The attendee has claimed everything they can afford | Zero reachable, for a different reason, said differently | "Ya canjeaste todos los premios a tu alcance." |
| A reward runs out while the screen is open | The reachable count drops on the next refresh | none |
| The attendee is barred from claiming (spec 022) | The reachable count is not presented as an opportunity | "No puedes canjear premios." |
| The attendee is removed from the event (spec 022) | The screen is not reachable, like every attendee screen | none |

## 7. Security and integrity

The screen reads, and everything it reads is the attendee's own.

- **Every figure is scoped to the session (R11, constitution IV).** Balance, visited stands,
  completed activities and reachable rewards are all this attendee's. None may be requested for
  somebody else, and no identifier supplied by the screen may select whose figures come back.
- **It changes nothing (R13).** No count, no summary and no link may award, spend or alter
  anything. The reachable-rewards count in particular displays what a claim *would* be allowed to
  do; it is never itself a claim and never a shortcut to one.
- **Affordability here is advisory.** The number is computed for display; the decision that matters
  happens at the handover, against a balance read at that moment (spec 018, R14). The two can
  legitimately disagree for a few seconds, and the handover is the one that is right.
- **A figure that cannot be computed is not displayed (R7).** The existing hardcoded zero is the
  precedent this rule exists to prevent: indistinguishable from a real value, and quietly wrong.

## 8. Acceptance criteria

- [ ] The balance is shown and matches the attendee's actual balance.
- [ ] Stands visited is shown against the number of stands in the fair.
- [ ] Activities completed is shown against the number published across the fair.
- [ ] The reachable-rewards count matches what the attendee could actually claim right now.
- [ ] That count excludes out-of-stock, withdrawn and already-claimed rewards, and rewards of
      withdrawn communities.
- [ ] Running activities appear in summary, with a route to the full activities screen.
- [ ] No figure on the screen is hardcoded; every one is derived.
- [ ] The stands list marks the stands the attendee has visited.
- [ ] Recent awards are listed most recent first with a relative time.
- [ ] A new award is reflected without reloading.
- [ ] One attendee's screen never shows another's figures, including through the API.
- [ ] Nothing on the screen awards, spends or changes anything.
- [ ] With no stands, activities or rewards, the screen explains rather than showing bare zeroes.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Part of this ships today, in `src/pages/Dashboard.jsx`.

| Requirement | Today |
|---|---|
| R1 | Met. The balance is the screen's hero element. |
| R2 | Met in substance, in two separate tiles: "Stands visitados" and "Total Stands" side by side rather than one against the other. |
| R3 | **Wrong after spec 019.** The tile counts *stands where an activity was completed* — `activitiesCompletedIds` is a set of `community_id` — because one activity per stand was the rule. With up to three per stand it stops being a count of activities, and there is no published total to compare against. |
| R4, R5 | **Missing, and actively wrong.** `const claimedCount = 0; // Will be updated when rewards page is integrated` (`src/pages/Dashboard.jsx:57-58`) renders a permanent zero in a tile labelled "Premios". |
| R6 | **Missing.** Activities do not exist. |
| R7 | **Contradicted** by the line above — the one explicit TODO in the application. |
| R8 | Met. The stands list marks visited stands. |
| R9 | Met. The ten most recent awards, with relative times. |
| R10 | **Missing.** The screen loads once; a new award appears only on a reload. |
| R11 | Met. Everything is derived from the participant in the session. |
| R12 | Partially met. There is an empty state for stands, but the figures show bare zeroes. |
| R13 | Met. |

**Consequences the plan must address**

- The activities figure changes meaning, not just value: it must count activities, and needs a
  fair-wide published total to sit against. It cannot be built before spec 019.
- The reachable-rewards count depends on cost, stock, withdrawal and prior claims — four things
  spread across specs 021, 022 and 023. It is one question and should be answered in one read
  rather than assembled in the browser.
- Removing the hardcoded zero is the smallest change in this spec and the most visible: it is
  currently lying to every attendee who has collected a prize.
- R10 introduces refreshing on a screen that has never had it. Specs 018 and 025 add their own;
  the plan should decide whether the three share a mechanism.

## 11. References

- Constitution: IV (identity is never a parameter).
- ADR 0003 — polling instead of realtime.
- Glossary: *Participant*, *Points*, *Activity*, *Reward*.
- Spec 019 — `stand-activity-catalogue`, without which R3 and R6 cannot be built.
- Spec 021 — `stand-reward-management`, whose catalogue R4 counts.
- Spec 025 — `participant-activity-progress`, which R6 links to.
- Spec 022 — `organizer-student-management`, whose claim bar R5 and the edge cases respect.
