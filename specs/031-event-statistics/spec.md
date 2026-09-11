# Spec 031 — Event statistics

| | |
|---|---|
| **Status** | Approved |
| **Branch** | `031-event-statistics` |
| **Actors** | Event operator |
| **Created** | 2026-09-11 |
| **Last updated** | 2026-09-11 |

## 1. Purpose

The fair produces a large amount of data and today almost none of it is read back. The organiser
can see six live totals on the home screen and can read the log one entry at a time, but there is
no way to ask the questions an event actually raises once it is over: when was the hall full, which
stands carried the fair and which stood empty, which prizes people took and which nobody wanted,
whether the point economy closed, and where the friction was.

This spec adds a reading surface that turns the event's own record into those answers. It is
analysis, not control: it is opened after the doors close, it changes nothing, and every figure it
shows is a question asked of data that already exists.

## 2. Scope

**In scope**

- A statistics area of the operator panel, reachable only by the event operator.
- Figures over attendance and timing, stands and points, rewards and the economy, participants,
  and refusals.
- A small fixed set of summary call-outs drawn from those figures.
- One time filter that every figure obeys.
- Exporting any figure as comma-separated values.
- The empty, partial and failure behaviour of all of it.

**Out of scope**

- Real-time or live updating. Decided against: the section is a post-event read, and a figure
  that reorders itself while it is being read is worse than one that is a few minutes old.
- Per-stand statistics. The stand's own screens cover its operation; isolating one stand here
  would duplicate them and was deliberately not asked for.
- Drilling down to individual scans, handovers or attendees. The students area already answers
  per-person questions from the data itself; a second answer could disagree with it.
- Recording demand for a prize before it is handed over. No request event is recorded anywhere
  (see section 5, "Demand"), so measuring it would require new instrumentation during the fair.
- Generating a document, such as a PDF, or an archive of exports.
- Changing any data. This spec adds no rule and no authority.

## 3. User scenarios

### 3.1 The organiser asks when the hall was full

**Given** the fair has ended
**When** the organiser opens statistics and looks at scans over time
**Then** they can see the busiest hours, separately for visits and for activities, and compare
them against registrations over time.

### 3.2 A stand's contribution is questioned

**Given** a stand that claims it carried the fair
**When** the organiser looks at points awarded per stand and scans per stand
**Then** they can see what each stand actually awarded, and which stands stood empty.

### 3.3 A prize nobody took

**Given** a prize that was registered and re-priced but never handed over
**When** the organiser looks at rewards never handed over
**Then** the prize is listed, and the organiser can decide whether to carry it next time.

### 3.4 The economy did not close

**Given** far more points awarded than spent
**When** the organiser looks at points awarded against points spent over time
**Then** the two curves show where they separated, and by how much the fair ended unspent.

### 3.5 Most complaints were about refusals

**Given** attendees insisting their scans did not work
**When** the organiser looks at refused actions by reason
**Then** the refusals are grouped by the reason they were refused, and the largest group says what
to fix.

### 3.6 Reading, then keeping a copy

**Given** the section is open on the whole event
**When** the organiser narrows the filter to the last hour of the fair and exports a figure
**Then** the exported file contains exactly the data shown for that hour, not the whole event.

### 3.7 A stand tries to open the section

**Given** a stand admin signed in to the stand's own panel
**When** they reach the statistics address or ask for its figures directly
**Then** they receive nothing, exactly as if they had no session.

## 4. Requirements

### Reaching it and who may

| ID | Requirement | Priority |
|---|---|---|
| R1 | Only the event operator MUST be able to reach statistics. | Must |
| R2 | Access MUST be enforced where the figures are served: a participant's or a stand's session asking directly MUST receive no figures. | Must |
| R3 | Statistics MUST be part of the operator panel and reachable from its navigation. | Must |
| R4 | No screen shown to a participant or to a stand MUST link to statistics. | Must |
| R5 | The code that renders figures SHOULD NOT be loaded until statistics is opened. | Should |

### How it is read

| ID | Requirement | Priority |
|---|---|---|
| R6 | Statistics MUST be read when the operator opens it. | Must |
| R7 | The operator MUST be able to refresh the figures on demand. | Must |
| R8 | Statistics MUST NOT refresh itself on a timer. | Must |
| R9 | Statistics SHOULD re-read when the operator returns to it after leaving. | Should |
| R10 | Every figure MUST be a snapshot from the moment of reading, and the section MUST show when it was read. | Must |
| R11 | Statistics MUST NOT be usable without a connection, and MUST NOT present stored figures as current. | Must |

### Time

| ID | Requirement | Priority |
|---|---|---|
| R12 | All time-based figures MUST be grouped in one fixed event timezone, independent of the device's timezone. | Must |
| R13 | The time filter MUST default to the whole event. | Must |
| R14 | The operator MUST be able to narrow the filter to an exact start and end moment. | Must |
| R15 | The filter MUST apply to every figure in the section together. | Must |
| R16 | Day boundaries MUST be the event timezone's midnight. | Must |
| R17 | Statistics MUST NOT offer filtering by stand. | Must |

### Attendance and timing figures

| ID | Requirement | Priority |
|---|---|---|
| R18 | Statistics MUST show scans over time, split by scan kind. | Must |
| R19 | Statistics MUST show how many distinct participants were active in each time group. | Must |
| R20 | Statistics MUST show registrations over time. | Must |
| R21 | Statistics MUST show cumulative points awarded over time. | Must |
| R22 | Statistics MUST show the first scan, the last scan, and the effective duration between them. | Must |

### Stand figures

| ID | Requirement | Priority |
|---|---|---|
| R23 | Statistics MUST show points awarded per stand, split by scan kind. | Must |
| R24 | Statistics MUST show scans per stand and the average points per scan. | Must |
| R25 | Statistics MUST show points added by manual adjustments as their own figure, never as points awarded by a stand. | Must |

### Economy and reward figures

| ID | Requirement | Priority |
|---|---|---|
| R26 | Statistics MUST rank rewards by how many times they were handed over. | Must |
| R27 | Statistics MUST rank rewards by how many points were spent on them. | Must |
| R28 | Statistics MUST show points awarded and points spent over time. | Must |
| R29 | Statistics MUST show, per reward, stock handed over against stock remaining. | Must |
| R30 | Statistics MUST list rewards that were never handed over. | Must |
| R31 | Statistics MUST show handovers over time. | Must |

### Participant figures

| ID | Requirement | Priority |
|---|---|---|
| R32 | Statistics MUST show the distribution of balances across participants. | Must |
| R33 | Statistics MUST show how many stands each participant visited. | Must |
| R34 | Statistics MUST show how many participants registered and never scanned. | Must |
| R35 | Statistics MUST show a table of the participants with the most points. | Must |

### Refusal and operational figures

| ID | Requirement | Priority |
|---|---|---|
| R36 | Statistics MUST group refused actions by the reason they were refused. | Must |
| R37 | Statistics MUST show claim codes issued, used, replaced and expired. | Must |

### Summary call-outs

| ID | Requirement | Priority |
|---|---|---|
| R38 | Statistics MUST show a fixed set of summary call-outs: the busiest time group, the stand that awarded the most points, the most handed-over reward, the number registered without a scan, and the stands with no scans. | Must |
| R39 | Every call-out MUST cover the same filtered data as the figures below it. | Must |

### Presentation

| ID | Requirement | Priority |
|---|---|---|
| R40 | Every figure MUST have an explicit empty state. | Must |
| R41 | Statistics MUST NOT fail, error or disappear when there is no data. | Must |
| R42 | Where "none" and "not yet applicable" differ, statistics MUST distinguish them. | Must |

### Export

| ID | Requirement | Priority |
|---|---|---|
| R43 | Every figure MUST be exportable as comma-separated values of the data behind it. | Must |
| R44 | An export MUST honour the active time filter. | Must |
| R45 | An export MUST succeed with no data, producing a file with only its header. | Should |
| R46 | Statistics MUST NOT require a document format or an archive to export. | Must |

### Integrity

| ID | Requirement | Priority |
|---|---|---|
| R47 | Statistics MUST NOT change any stored data. | Must |
| R48 | Statistics MUST NOT expose any secret: no password, no hash, no fingerprint, no claim or recovery code value, and no signing secret. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Event timezone | One fixed zone, `America/La_Paz` | The operator's laptop may be set to another zone and the attendees' phones certainly are. Grouping by whatever zone each reader happens to be in would give two people two different answers to the same question. |
| Time group | One hour | The fair lasts hours, not minutes. Hourly groups show the shape of the event without the noise a finer grain would add on a screen this size. |
| Day boundary | Midnight in the event timezone | Correct even if an event runs past local midnight, which would otherwise merge two days into one group. |
| Event span | One calendar day expected | The reference fair runs for the hours it lasts. Grouping still works across midnight, so a longer event is not wrong, only unplanned for. |
| Freshness | Snapshot at the moment of reading, refreshed on demand | Post-event analysis has no use for a live feed, and a value that changes while it is being read invites wrong conclusions. R8 and R10 make the snapshot explicit. |
| Demand | Completed handovers, only | The system records no request, no view and no selection; a claim code is issued before the attendee chooses a prize. "Most handed over" is the only demand that was ever recorded, and the spec says so rather than implying a richer measurement. |
| Withdrawn stands, removed and barred participants | Included, and labelled | Withdrawal and sanction change what a stand or person may do next, not what they did. Removing them from the record would delete a stand's contribution from the fair's history. |
| Manual adjustments | Their own figure, never counted as a stand's award | An adjustment has no stand. Folding it into points awarded per stand would credit a stand with points it did not award and make the comparison between stands wrong. |
| Points awarded | Scan awards only, excluding adjustments | Consistent with the home screen's definition, so the two surfaces cannot disagree. |
| Top participants | The first ten | Matches what the public leaderboard projects, and keeps the table readable at a glance. |
| Stands with no scans | Shown | An empty stand is the single most actionable tendency a fair can reveal, so it is a call-out and not merely a zero in a chart. |
| Refusal reasons | Grouped as recorded by the log | The reasons are already enumerated by the log; inventing finer categories here would produce groups the data cannot fill. |
| Balance distribution | Fixed 50-point bands, the top band open-ended | Balances at the reference scale reach the low hundreds. Fixed bands keep two fairs comparable, and an open top band keeps the shape honest when an outlier appears. |
| Browser floor | The statistics area may exceed it, by ADR | The compatibility floor exists for attendees on old Android browsers. Statistics is operator-only, on a laptop, and loaded only when opened. ADR 0006 records the exclusion explicitly. |
| Export format | Comma-separated values, one file per figure | The realistic need is to keep the numbers after teardown, not to print them. A document or archive format would add a dependency for no gain. |
| Empty data | Explicit and non-failing | An operator who opens statistics before the fair, or after a quiet one, must see a stated absence and not an error or a blank screen. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| No scans happened | Every figure shows its empty state; call-outs read zero | a stated absence, in Spanish, per figure |
| No rewards were published | Reward and economy figures say "not yet applicable" rather than showing a misleading zero | a statement distinguishing absent from zero |
| A stand was withdrawn before the event ended | Its scans and awards still count, and it is labelled as withdrawn | a visible label |
| A participant was removed or barred | Their activity still counts, labelled as such | a visible label |
| Only manual adjustments exist, no scans | Points awarded by stands reads zero; the adjustment figure is non-zero | none |
| The filter matches no data | Every figure shows its empty state; exports still produce a header-only file | a stated absence |
| The operator exports a figure | The file contains exactly the data on screen, under the active filter | none |
| The session expires while the section is open | The next read returns to sign-in, without appearing to have worked | "Tu sesión expiró. Vuelve a iniciar sesión." |
| A participant's or stand's session requests figures directly | Refused; nothing is returned | none |
| The browser is older than the rendering floor | The section may not render; every other area of the panel keeps working | a statement that the browser is unsupported |
| Two reads overlap | The later read replaces the earlier one; a stale response never overwrites a newer one | none |
| The event record holds a whole fair's volume of scans and refusals | Reads stay responsive; figures are computed without loading every record | none |

## 7. Security and integrity

Statistics is the widest reading surface in the system: it can describe every stand and every
attendee at once. Reading is the only thing it does.

- **Access is scoped to the operator, where the data is served (R1, R2, constitution IV).** The
  section spans the whole event, so who may read it is resolved from the session server-side, the
  same way every other operator power is. Hiding the entry point is not the control; a stand's or
  participant's session reaching the figures directly must receive nothing.
- **It is a reading surface (R47).** No figure may trigger any action, and its existence must not
  become a reason to weaken a rule elsewhere. It grants the operator no authority beyond what
  specs 021 to 024 already define.
- **It must not become the leak (R48, constitution V).** The data behind it passes through nearly
  every table. Passwords, hashes, fingerprints, claim and recovery code values and the signing
  secret must be absent from every figure and every export, including figures about issuing and
  redeeming codes.
- **Aggregation, not rows.** The figures are answers about the whole event, and they are computed
  where the data is rather than by pulling the fair's records into a browser. This is both a
  performance rule and a privacy one: what is never sent cannot leak.
- **Refusals are as sensitive as successes (R36).** Grouped refusal figures reveal how often
  people failed and why, which is exactly the operational truth the organiser needs, and exactly
  the kind of thing that must stay behind the operator's session.
- **The rendering code ships publicly (R5).** It lives in the same downloadable application as
  everything else. Nothing in it may be a secret and nothing in it may be the enforcement.
- **One filter, no per-stand slicing (R17).** Because every figure describes the same slice, a
  figure can never be read as a statement about one stand while looking like a statement about
  the event.

## 8. Acceptance criteria

- [ ] The operator can open statistics from the panel's navigation.
- [ ] A stand's session requesting the figures directly receives nothing.
- [ ] A participant's session requesting the figures directly receives nothing.
- [ ] No screen shown to a participant or a stand links to statistics.
- [ ] The section reads when opened and can be refreshed on demand.
- [ ] The section does not update on a timer.
- [ ] The section shows the moment its figures were read.
- [ ] The time filter defaults to the whole event and narrows to an exact start and end.
- [ ] Narrowing the filter changes every figure together.
- [ ] Times are grouped in one fixed event timezone regardless of the device's zone.
- [ ] Scans over time are shown separately for visits and activities.
- [ ] Distinct active participants, registrations and cumulative points are shown over time.
- [ ] The first scan, last scan and effective duration are shown.
- [ ] Points awarded per stand are shown, split by scan kind.
- [ ] Scans per stand and the average points per scan are shown.
- [ ] Manual adjustments appear as their own figure and never inside stand awards.
- [ ] Rewards are ranked by handovers and by points spent.
- [ ] Points awarded and points spent are shown over time.
- [ ] Handed-over and remaining stock are shown per reward.
- [ ] Rewards never handed over are listed.
- [ ] Handovers over time are shown.
- [ ] The balance distribution, stands visited per participant, the registered-with-no-scan count
      and a top-ten participant table are shown.
- [ ] Refused actions are grouped by reason.
- [ ] Claim codes issued, used, replaced and expired are shown.
- [ ] The five call-outs are shown and cover the same filtered data as the figures.
- [ ] A withdrawn stand and a removed participant still appear, labelled.
- [ ] With no scans, every figure shows a stated absence and the section does not error.
- [ ] With no rewards published, the reward figures say so rather than showing zero.
- [ ] Every figure exports comma-separated values that honour the active filter.
- [ ] Exporting an empty figure produces a header-only file.
- [ ] No figure or export contains a password, hash, fingerprint, code value or signing secret.
- [ ] The section changes no stored data.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Nothing in this spec exists.

| Concern | Today |
|---|---|
| Event-wide figures | The home screen shows six whole-event totals, recomputed every ten seconds. They are a live pulse, not an analysis. |
| Reading history | The log area reads individual entries, newest first, filterable by kind, actor, outcome and time. It aggregates nothing. |
| Time handling | The log sends an exact instant rather than a relative window, because the phone's clock and the server's are not the same clock. Statistics inherits that rule. |
| Charting | There is no charting dependency in the application at all. |
| Aggregation | A few totals are already computed where the data is, for the home screen. Nothing is grouped over time or grouped per stand. |
| Compatibility | The build targets Chromium 83 for every surface, because attendees run old Android browsers. |

**Consequences the plan must address**

- The figures are aggregates over nearly every table, read by one person. They must be computed
  where the data is, never by moving the fair's rows into the browser.
- A client-side rendering dependency enters the bundle for the first time. It must not reach the
  participant or the stand, so it loads only when this section is opened, and the existing
  compatibility floor must be revisited for it explicitly.
- The freshness contract is the opposite of the rest of the panel's: read on demand, not on a
  timer. It must reuse the reading pattern the log already uses, not the polling pattern the home
  screen uses.
- Exports are produced from the same data as the figures, so the two cannot disagree.
- The operator gate already exists and applies unchanged; no new authority is introduced.

## 11. References

- Constitution: III (business rules where the data is), IV (identity is never a parameter),
  V (secrets never reach the client), VII (compatibility floor), IX (quality gates).
- ADR 0003 — polling over realtime, which this section deliberately does not use.
- ADR 0006 — the statistics area may exceed the Chromium 83 floor.
- Glossary: *Event operator*, *Stand*, *Participant*, *Scan*, *Visit*, *Activity*, *Points*,
  *Reward*, *Claim*.
- Spec 017 — `organizer-admin-panel`, the shell this section joins, and the authority it may not
  exceed.
- Spec 020 — `fixed-points-model`, whose constants define what points are awarded.
- Spec 021 — `stand-reward-management`, which defines rewards and their stock.
- Spec 022 — `organizer-student-management`, the sanctioned per-person view.
- Spec 023 — `organizer-community-management`, which defines withdrawal.
- Spec 024 — `system-audit-log`, the source of refusals and the reading pattern reused here.
- Spec 007 — `live-leaderboard`, the public ranking the top-participants table mirrors.
