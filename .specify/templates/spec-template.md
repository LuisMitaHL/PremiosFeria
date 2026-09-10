# Spec NNN — <Feature name>

| | |
|---|---|
| **Status** | Draft \| In review \| Approved \| Implemented \| Superseded by NNN |
| **Branch** | `NNN-slug` |
| **Actors** | Participant \| Stand admin \| Event operator |
| **Created** | YYYY-MM-DD |
| **Last updated** | YYYY-MM-DD |

> Written in English. Describes WHAT and WHY, never HOW.
> No component names, table names, packages or function names in the requirements —
> those belong in `plan.md` and in *As-built notes*.
> Use the terms from `.specify/memory/glossary.md`. Do not invent new ones.

## 1. Purpose

Two or three sentences. What need does this serve, for whom, and what changes for them once it
exists? A reader who has never seen the code must understand the point of this feature.

## 2. Scope

**In scope**
- ...

**Out of scope**
- ... (and, briefly, why — or which spec covers it instead)

## 3. User scenarios

Written as a walk-through, in the actor's own terms. One scenario per meaningful path.

### 3.1 <Primary scenario>

**Given** ...
**When** ...
**Then** ...

### 3.2 <Alternative or recovery path>

...

## 4. Requirements

Numbered, atomic, and testable. Each one must be verifiable by running the system.
Use MUST / MUST NOT / SHOULD / MAY deliberately.

| ID | Requirement | Priority |
|---|---|---|
| R1 | The system MUST ... | Must |
| R2 | The system MUST NOT ... | Must |
| R3 | The system SHOULD ... | Should |

## 5. Business rules

The constants, thresholds and invariants this feature depends on. State the value **and the
reason it has that value**, so a future reader can tell an arbitrary number from a deliberate one.

| Rule | Value | Rationale |
|---|---|---|
| ... | ... | ... |

## 6. Edge cases and failure modes

What happens when things go wrong. Every row must say what the actor sees, not only what the
system does internally.

| Situation | Expected behaviour | Message shown to the actor |
|---|---|---|
| ... | ... | ... |

## 7. Security and integrity

How this feature holds up against someone trying to abuse it. Reference the constitution
principle at stake (III business rules in the database, IV identity, V secrets, VI point
economy). If the feature touches points, this section is mandatory and must name the structural
gate — a constraint, an index, or a conditional write — not just a check.

## 8. Acceptance criteria

The checklist a reviewer runs before approving the pull request. Each line is an observable
outcome, not a task.

- [ ] ...
- [ ] ...

## 9. Open questions

Every unresolved point, as `[NEEDS CLARIFICATION: the question]`.
**An unresolved marker blocks approval and blocks `plan.md`.** Delete this section when empty.

## 10. As-built notes

*Retro-specs only.* Anchors each requirement to the code that implements it today, so the spec
can be verified against reality. Delete this section for a spec describing work not yet built.

| Requirement | Implemented in |
|---|---|
| R1 | `path/to/file.js:NN` |

**Known deviations** — where the code does not match this spec, and whether the code or the spec
is considered wrong.

## 11. References

- Related specs: ...
- ADRs: ...
- Constitution principles: ...
