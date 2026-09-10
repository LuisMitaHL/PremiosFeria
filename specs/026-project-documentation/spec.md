# Spec 026 — Project documentation

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `026-project-documentation` |
| **Actors** | — |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

The README is the first thing anyone reads and the last thing anyone updated. It calls the product
by a name nothing else uses, describes a developer mode in the scanner that was deleted, and jumps
from three lines of introduction straight into a six-section deployment runbook — with nothing in
between about what the system is, how it is put together, or why it is built the way it is.

Two different people arrive at this repository: somebody who is going to write code in it, and
somebody who is going to stand it up for an event. Today neither is served. The developer finds an
operations manual; the operator finds accurate instructions surrounded by things that are no longer
true.

## 2. Scope

**In scope**

- Rewriting the README in Spanish, for both audiences, in one file.
- What the system is and how it is put together.
- Running it locally.
- The tools and versions it depends on.
- Deploying and operating an event.
- Where the specifications, the rules and the decisions live.
- Removing what is no longer true.

**Out of scope**

- The specification system itself. `AGENTS.md`, the constitution and `docs/CONTRIBUIR.md` already
  exist and are not rewritten here; the README points at them.
- Changing any behaviour, any name, or any file other than documentation. Spec 016 owns the
  renaming, and this spec uses the name it settles on.
- Documenting screens that do not exist yet. This describes the system as it is at the moment it
  is written, and is updated by each spec that changes it.

## 3. User scenarios

### 3.1 Somebody joins the project

**Given** a developer cloning the repository for the first time
**When** they read the README
**Then** they understand what the system does, what it is built from, how to get it running on
their machine, and where to look for the rules before they change anything.

### 3.2 Somebody has to run an event

**Given** an operator preparing a fair
**When** they follow the README
**Then** they can generate the secrets, start the stack, verify it is working, create the
organiser's account, and know how to tear it all down afterwards.

### 3.3 Somebody asks why

**Given** a developer wondering why the leaderboard polls instead of using a socket, or why the
build targets a browser from 2020
**When** they follow the README's pointers
**Then** they reach the decision records rather than guessing or reopening the question.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The README MUST be written in Spanish. | Must |
| R2 | The README MUST serve both audiences — developing and operating — in clearly separated sections, in a single file. | Must |
| R3 | The README MUST open by saying what the system is, for whom, and what an attendee actually does with it. | Must |
| R4 | The README MUST describe the architecture: the four services, what each one is for, and where the business rules live. | Must |
| R5 | The README MUST list the tools and their versions, and MUST state the browser compatibility floor and why it exists. | Must |
| R6 | The README MUST give the steps to run the system locally, and MUST state that a schema change requires a fresh database. | Must |
| R7 | The README MUST document the verification commands — lint, tests, and the business-rule tests — and MUST state that a production build is not how work is verified. | Must |
| R8 | The README MUST keep the deployment and operating instructions, updated to match how the system actually works. | Must |
| R9 | The README MUST document how the organiser's account comes into existence, and how communities are created. | Must |
| R10 | The README MUST NOT describe anything that does not exist. | Must |
| R11 | The README MUST point to the specifications, the working rules, the constitution and the decision records, rather than restating them. | Must |
| R12 | The README MUST use the name spec 016 settles on. | Must |
| R13 | The README MUST NOT contain a credential, a real hostname, or an example that would work if pasted. | Must |
| R14 | Documentation touched by a change MUST be updated in the same pull request as that change. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Language | Spanish | The team works in Spanish, and this is the document written for people rather than for the specification system. The specs stay in English; the README is the boundary between the two. |
| One file, two sections | Always | Splitting into several documents means the operator's half goes stale unnoticed. One file that everyone opens is one file everyone sees is wrong. |
| Points, does not restate | Always | The rules live in `AGENTS.md`, the principles in the constitution and the reasoning in the decision records. Copying any of it into the README guarantees two versions that will disagree. |
| Nothing aspirational | Always | The current README documents a scanner feature that no longer exists, which is how a reader learns not to trust the rest of it. A README is only useful while it is true. |
| No working examples | Always | Every hostname is an example, every key a placeholder. A README that can be pasted is a README somebody will paste. |
| Updated with the change | Always | Part of the Definition of Done already. Stated here so the README's accuracy is somebody's job on every pull request rather than nobody's. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour |
|---|---|
| A spec changes how something is deployed | The README is updated in that spec's pull request, not later |
| A section would duplicate `AGENTS.md` | It links instead |
| An instruction cannot be verified by following it | It is removed rather than left as an approximation |
| The system is mid-migration and two things are true | Both are described, with which one applies when |
| A reader wants to know why | They are sent to the decision records, which is where reasons live |

## 7. Security and integrity

- **A README is a place credentials end up (R13).** The repository already carries an environment
  file with a hosted project's URL and key (spec 016 removes it), which is exactly what happens
  when real values are treated as convenient examples. Every value here is a placeholder, and no
  command in it works as written.
- **Documenting the organiser's bootstrap without weakening it (R9).** The organiser's account is
  generated at deployment (spec 017). The README says how to generate it and how to hand it over;
  it must not suggest a default, a fallback, or a way to recreate it that bypasses that step.
- **Inaccuracy is a security problem too.** An operator following a stale instruction can leave a
  port published, a secret file world-readable, or a database seeded with something they did not
  intend. R10 is not about tidiness.

## 8. Acceptance criteria

- [ ] The README is in Spanish.
- [ ] It has a section for developing and a section for operating, in one file.
- [ ] It opens with what the system is and what an attendee does with it.
- [ ] It describes the four services and where the business rules live.
- [ ] It lists the tools with their versions, and the browser floor with its reason.
- [ ] It gives working local instructions, including when a fresh database is required.
- [ ] It documents lint, tests and the business-rule tests, and says a production build is not a
      verification step.
- [ ] It documents deployment, verification, the organiser's account, creating communities, and
      teardown.
- [ ] Nothing in it describes a feature that does not exist.
- [ ] It points at the specs, the rules, the constitution and the decision records instead of
      restating them.
- [ ] It uses one name for the product throughout.
- [ ] No credential, real hostname or pasteable example appears in it.
- [ ] Every instruction was followed end to end by someone before this spec was accepted.

## 9. Open questions

None.

## 10. Current behaviour and the gap

`README.md` is the only document in the repository today, at roughly 160 lines.

| Requirement | Today |
|---|---|
| R1 | **Contradicted.** It is in English. |
| R2 | **Missing.** Three lines of introduction, then a deployment runbook. There is no developer half. |
| R3 | Partially met, in a single sentence. |
| R4 | Partially met. The stack is listed and there is a good line about rules living in Postgres RPC, but no picture of how the pieces fit. |
| R5 | Partially met. Libraries are named without versions, and the Chromium floor appears only as a comment in the build configuration, not in the README. |
| R6 | Met, and accurate: the local script, the fresh-database flag, and the warning that schema changes need it. |
| R7 | **Missing.** There were no lint or test commands when it was written. There are now. |
| R8 | Met, and the strongest part of the document: secrets, boot, the CDN contract with verification commands, seed files, credential rotation, teardown. |
| R9 | **Will be wrong.** It documents seeding stands from CSV, which specs 017 and 023 remove. |
| R10 | **Contradicted.** It documents a "Developer Mode" in the scanner that does not exist in the code. |
| R11 | **Missing.** None of `AGENTS.md`, the constitution, the specs or the decision records existed when it was written. |
| R12 | **Contradicted.** It calls the product FeriaPoints, which nothing else does. |
| R13 | Met. Hostnames and keys are placeholders. |

**Consequences the plan must address**

- This spec should be done last among the documentation work, because most of what it describes is
  still changing. Doing it early guarantees rewriting it.
- The deployment half is largely correct and should be translated and corrected rather than
  rewritten, so its hard-won detail is not lost.
- The seeding section is not an edit but a replacement: creating communities moves into the panel.
- Following every instruction end to end is part of accepting this spec, not an optional check.
  That is the only way R10 is ever true.

## 11. References

- `AGENTS.md` and `docs/CONTRIBUIR.md` — the working rules the README points at.
- `.specify/memory/constitution.md`, `architecture.md`, `glossary.md` and the decision records.
- Spec 016 — `naming-and-hygiene-cleanup`, which settles the name this uses.
- Spec 017 — `organizer-admin-panel`, whose bootstrap R9 documents.
- Spec 023 — `organizer-community-management`, which replaces the seeding section.
