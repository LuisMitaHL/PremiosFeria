# Spec 024 — System audit log

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `024-system-audit-log` |
| **Actors** | Event operator |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

During a fair, most problems arrive as a sentence: "it says I already did that activity", "the
stand scanned me and nothing happened", "my prize was there five minutes ago". Each one is a
question about something that happened in a specific second to a specific person, and today there
is no way to answer it. The tables hold what is true now, not what occurred; a refusal leaves no
trace at all, and a refusal is what most complaints are about.

This spec records what the system did and what it declined to do, so the person at the
organisation desk can look instead of guess. It is a reading surface, not a control: nothing in
here changes anything, and everything in here is written by the actions specified elsewhere.

## 2. Scope

**In scope**

- Every action that changes something, recorded as it happens.
- Every refusal, with the reason it was refused.
- What each entry holds, including the value something had before it changed.
- Reading and filtering the log.
- The guarantees that make a log worth trusting: nobody edits it, nobody deletes from it, and no
  action is recorded that did not happen.

**Out of scope**

- Looking up one participant's scans and handovers. Spec 022 already gives the organiser that
  view, built from the data itself rather than from the log.
- Exporting anything. Decided against: the log lives and dies with the deployment.
- Application diagnostics — errors, timings, container logs. Those belong to whoever operates the
  host, not to this screen.
- Any authority. Reading the log grants nothing; the powers are in specs 021, 022 and 023.

## 3. User scenarios

### 3.1 "It says I already did that activity"

**Given** an attendee insisting they never scanned a stand's workshop
**When** the organiser filters the log to activity completions in the last hour
**Then** they can see whether that completion was recorded, and at what second.

### 3.2 "The stand scanned me and nothing happened"

**Given** an attendee whose balance did not move
**When** the organiser looks at refusals in that window
**Then** they can see the scan arrived and was refused, and why — the cooldown had not elapsed,
the activity had already finished, the code was from an expired window.

### 3.3 A prize costs the wrong amount

**Given** a reward that everyone agrees used to cost 200 and now costs 20
**When** the organiser filters to reward changes
**Then** they can see the change, when it happened, and what the cost was before it.

### 3.4 An adjustment is questioned

**Given** someone asking why an attendee near the top of the leaderboard has more points than
their scans account for
**When** the organiser filters to point adjustments
**Then** they can see the amount, the moment, and the reason that was given.

### 3.5 Reconstructing a busy ten minutes

**Given** a period when several things went wrong at once
**When** the organiser narrows the log to that time range
**Then** they can read what happened in order, across every stand and every attendee.

## 4. Requirements

### What is recorded

| ID | Requirement | Priority |
|---|---|---|
| R1 | Every action that changes stored state MUST be recorded. | Must |
| R2 | The recorded actions MUST include, at minimum: a participant registering; a profile being recovered; points being awarded; a handover being confirmed; an activity being created, started or finished; a reward being registered, repriced, restocked, withdrawn or reinstated; a community being created, edited, withdrawn or reinstated; a password being reset; a participant being renamed, barred from claiming, removed or reinstated; and a balance being adjusted. | Must |
| R3 | Every refusal of one of those actions MUST be recorded, with the reason it was refused. | Must |
| R4 | A failed sign-in MUST be recorded, without recording what was attempted. | Must |
| R5 | Nothing MUST be recorded that is not an action or a refusal — the log MUST NOT become a general diagnostic stream. | Must |

### What an entry holds

| ID | Requirement | Priority |
|---|---|---|
| R6 | Every entry MUST hold what happened, who did it, what or whom it affected, and the moment it happened. | Must |
| R7 | An entry for a change MUST hold the value the changed thing had **before** the change. | Must |
| R8 | An entry MUST record the actor as the identity that performed the action: a participant, a stand, or the organiser. | Must |
| R9 | An entry MUST NOT contain a password, a password hash, a claim code, a recovery code, or any other secret — in any field, including a previous value. | Must |
| R10 | An entry for a refusal MUST record the same fields as a successful one, plus the reason. | Must |

### Reading it

| ID | Requirement | Priority |
|---|---|---|
| R11 | Only the organiser MUST be able to read the log. | Must |
| R12 | The log MUST be filterable by kind of action. | Must |
| R13 | The log MUST be filterable by who performed the action. | Must |
| R14 | The log MUST be filterable by time range. | Must |
| R15 | Filters MUST be usable together. | Must |
| R16 | Entries MUST be readable in the order they happened. | Must |
| R17 | The log MUST remain usable to read when it holds the volume a full event produces, without loading all of it at once. | Must |

### Trusting it

| ID | Requirement | Priority |
|---|---|---|
| R18 | An entry MUST NOT be editable by anyone, including the organiser. | Must |
| R19 | An entry MUST NOT be deletable by anyone, including the organiser. | Must |
| R20 | An action and its entry MUST both happen or neither MUST happen. It MUST NOT be possible for a change to take effect unrecorded. | Must |
| R21 | The inability to record MUST NOT be recoverable by proceeding: if the entry cannot be written, the action MUST fail. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| What is logged | Every change and every refusal | Most complaints at a fair are about something that did **not** happen. A log of successes alone answers none of them, and "there is no record" is indistinguishable from "it was refused". |
| Previous values | Recorded on every change | Without them the log says a price changed but not from what, which is exactly the question anyone asks. It is the difference between a log that resolves an argument and one that confirms there was one. |
| Actor granularity | Participant, stand, or "the organiser" | Spec 017 gives the organising team a single shared account, so every organiser action is attributed to that account and never to a person. This is the accepted cost of that decision and the first thing to change if the log ever needs to name someone. |
| Filtering by who was affected | Not provided here | Spec 022 already gives the organiser a per-participant view of scans and handovers, built from the data rather than the log. Duplicating it as a filter would mean two answers to the same question that could disagree. |
| Export | None | The log serves the event and is discarded with it. **The consequence is accepted and stated: once the deployment is torn down, nothing about the fair survives, and a complaint raised the following week cannot be investigated.** |
| Editing and deleting | Never, by anyone | A log its readers can alter is not evidence. The organiser is the only reader and must also be unable to rewrite it, or their own actions become deniable. |
| Recording is part of the action | Always | An action that succeeds without its entry leaves a system whose history is quietly wrong, and nothing would ever reveal it. Failing loudly is better than recording selectively. |
| Secrets | Never in an entry | Passwords, claim codes and recovery codes all pass through actions that are logged. A log holding them turns the one screen the organiser reads all day into the softest target in the system. |
| Volume | Every scan and every refusal, for a full event | At the reference scale — around 10 stands and 300 attendees over an afternoon — this is tens of thousands of entries, which is small for a database and large for a screen. Hence R17. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| A stand or participant requests the log | Refused; no entries are returned | none |
| Filters match nothing | An empty result, stated plainly, not an error | "No hay movimientos que coincidan." |
| The log holds tens of thousands of entries | Reads stay responsive; entries are fetched in parts | none |
| An action succeeds but its entry cannot be written | The action fails and nothing changes | the action's own failure message |
| Two actions happen in the same instant | Both are recorded, and their order is unambiguous when read | none |
| An action is refused | An entry with the reason, and no change to anything | the action's own refusal message |
| A sign-in fails | An entry recording the failure, with nothing about what was attempted | "Credenciales incorrectas." |
| An entry refers to something later withdrawn | The entry still resolves, because nothing in the system is deleted | none |
| The organiser tries to edit or delete an entry | Refused; there is no path that would allow it | none |

## 7. Security and integrity

A log is only worth what its weakest guarantee is worth.

- **Append-only means append-only (R18, R19).** No screen, no endpoint, no privilege edits or
  removes an entry. The organiser is the only reader, and if they could also rewrite it their own
  actions — repricing a prize, adjusting a balance — would be deniable, which defeats the reason
  those actions are logged at all.
- **Recording is inside the action, not after it (R20, R21).** An entry written separately can be
  lost while the change survives, and nothing would ever reveal the gap. Both must commit
  together, in the same step that already guarantees the point economy's atomicity
  (constitution VI).
- **The log must not become the leak (R9).** Registering a community generates a password;
  claiming and recovery generate codes. All three are actions that get logged, and all three must
  be recorded by what they are, never by their value — including in a previous-value field, which
  is the easy place to forget.
- **Reading is scoped to the organiser (R11, constitution IV).** The log contains every
  participant's movements and every stand's operations. Access follows from the session, resolved
  server-side; a stand admin calling the endpoint directly must get nothing.
- **Refusals are as sensitive as successes (R3, R4).** They reveal who tried what and when. Failed
  sign-ins in particular must record that an attempt failed without recording the attempt, or the
  log becomes a list of guessed passwords.
- **The log grants nothing.** It is a reading surface. No action in the system may be triggered
  from it, and its existence must not become a reason to weaken any other rule.

## 8. Acceptance criteria

- [ ] A participant registering, a profile being recovered, points being awarded and a handover
      being confirmed each produce an entry.
- [ ] An activity created, started and finished each produce an entry.
- [ ] A reward registered, repriced, restocked, withdrawn and reinstated each produce an entry.
- [ ] A community created, edited, withdrawn, reinstated and password-reset each produce an entry.
- [ ] A participant renamed, barred from claiming, removed, reinstated and adjusted each produce
      an entry.
- [ ] Every refusal of the above produces an entry carrying the reason.
- [ ] A failed sign-in produces an entry, and that entry contains nothing that was attempted.
- [ ] Every entry holds what happened, who did it, what it affected and when.
- [ ] An entry for a change holds the previous value.
- [ ] No entry anywhere contains a password, a hash, a claim code or a recovery code.
- [ ] A stand's session reading the log receives nothing.
- [ ] A participant's session reading the log receives nothing.
- [ ] The log filters by kind, by actor and by time range, and by all three together.
- [ ] Entries read back in the order they happened.
- [ ] Reading stays responsive with an event's worth of entries, without fetching all of them.
- [ ] No path exists that edits an entry.
- [ ] No path exists that deletes an entry.
- [ ] An action whose entry cannot be written does not take effect.

## 9. Open questions

None. Two decisions carry consequences recorded in section 5 rather than left implicit: the log
cannot name which member of the organising team acted, because there is one shared account; and
nothing survives the teardown, because there is no export.

## 10. Current behaviour and the gap

Nothing in this spec exists.

| Concern | Today |
|---|---|
| History of changes | None. Every table holds current state only. A reward's cost has no history; a community's name has no history. |
| History of actions | Partial and accidental. `scans` and `claimed_rewards` record that something happened, because the row *is* the thing that happened. Nothing else does. |
| Refusals | Invisible. Every refusal in the system returns a message and leaves no trace, which is why "the stand scanned me and nothing happened" is unanswerable today. |
| Access | Not applicable; there is nothing to read. |

**Consequences the plan must address**

- Every rule already specified becomes a writer to this log, so this is the spec with the widest
  reach in the set. It should land after the actions it records, not before.
- R20 means recording happens inside the same transaction as the change. Every action that changes
  state already runs inside one, which makes this achievable — but it also means no action may be
  added later that writes outside that pattern.
- The log is written on every scan, including refused ones, so its write path is the busiest in
  the system during the event. It must not become the thing that makes scanning slow.
- Reads are filtered and ordered over a large table by one user. R17 is a real requirement, not a
  nicety.
- Nothing in the system deletes rows, which is what makes an entry's references still resolve
  later. That property is now load-bearing for this spec.

## 10b. As built

Two files. `45_audit.sql` holds the table and the writer, numbered before `50` because every
function from there on writes to it; `59_audit_read.sql` holds the reader, which needs
`calling_organizer()` from `55`. The screen is `src/pages/organizer/AuditArea.jsx`, in the panel's
"Registro" area.

**Recording is an `INSERT` in the caller's transaction.** Not a queue, not a trigger on each
table. Table triggers were considered and rejected early: they see rows change, not actions
refused, and R3 makes refusals the larger half of this log — they also cannot record *why*.

**The `EXCEPTION` blocks turned out to be the real hazard, not the happy path.** Four functions
already wrapped a conditional write in `BEGIN ... EXCEPTION`, and one of those handlers is
`WHEN OTHERS`. An `audit()` call inside such a block has its failure caught and converted into an
ordinary refusal — the caller is told a reason that never happened, and the change is silently
rolled back. Worse, the log's own `CHECK` constraint raises `check_violation`, which two of those
handlers catch by name. Every entry is therefore written **outside** the block: the refusal reason
travels out in a variable and is recorded after the block closes. R21 is the requirement that
forced this, and it is the one place where getting it wrong would have been invisible.

**Ordering is an identity column.** `now()` is identical for everything in one transaction, so two
actions in the same instant could not be read back in order. Paging is by key rather than
`OFFSET`: the organiser reads newest-first while the fair keeps writing at that end, and an
`OFFSET` over a table growing at the head repeats and skips rows.

**Three holes were found by handing the work out and reading the results back.**

The first: `audit()` is a `SECURITY DEFINER` function in `public`, which is exactly what PostgREST
publishes, and Postgres grants `EXECUTE` to `PUBLIC` by default. Any client holding the publishable
key could have called `/rpc/audit` and written entries — "scan.award ok" attributed to anyone —
into the one screen the organiser reads all afternoon. Revoking the table was not enough; the
functions needed revoking too. A log a third party can write to is worth no more than one they can
edit.

The second: the secret guard walked only the top level of `before` and `detail`, so
`{"community": {"password_hash": ...}}` passed it — and nesting is exactly what copying a row
produces, which is the mistake the guard exists to catch. It now walks every level, arrays
included.

The third: `actor_id` held a community id on resolved paths and the token's subject on unresolved
ones. Filtering the log by a stand would have silently omitted that stand's refused attempts,
which are the entries someone would go looking for. `audit_actor_id()` resolves everything into one
identifier space.

**The scope filter is a static list, not a query.** It was built from `audit_kinds()`, which
returned only the scopes that already had entries; the browser check showed the filter offering
"Todo" and "Inicios de sesión" and nothing else, and silently ignoring a selection for a scope that
had not happened yet. A filter that appears gradually cannot be learned. The list now lives in the
client and `audit_kinds()` is dropped rather than left unused.

**Two things are deliberately not recorded**, both stated in the plan: `poll_my_claim_code`, which
runs every two seconds per attendee and changes nothing worth a line, and
`close_expired_activities`, which nobody performs — it is derived cleanup that any read can
trigger, and logging it would attribute a change to whichever attendee happened to open a screen.

**Verified in the browser** against a running fair: a failed sign-in for a stand and for the
organiser, a registration, an awarded scan and a refused one, a reprice from 250 to 90, a refused
reprice at 5000 carrying "El costo no puede superar los 300 puntos.", and a withdrawal and
reinstatement — each filtered by scope, by actor, by outcome and by time range, alone and
combined, with "No hay movimientos que coincidan." when nothing matches.

**A gap in spec 023 surfaced while wiring the panel.** Its R20 to R25 give the organiser control
over any reward's cost, stock and withdrawal, and the functions existed, but the panel's "Premios"
area was still an empty placeholder — 023 was marked implemented on the strength of its backend.
That screen is built here rather than papered over.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), V (secrets never
  reach the client), VI (structural guarantees).
- Glossary: *Participant*, *Stand*, *Event operator*, *Scan*, *Claim*.
- Spec 017 — `organizer-admin-panel`, whose single shared account bounds what R8 can record.
- Spec 022 — `organizer-student-management`, which owns the per-participant view this spec
  deliberately does not duplicate, and whose adjustments R2 records.
- Spec 023 — `organizer-community-management`, most of whose actions this records.
- Specs 018, 019, 020, 021 — the actions that write here.
