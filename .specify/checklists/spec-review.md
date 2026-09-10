# Spec Review Checklist

Run this before moving a spec from `Draft` to `Approved`. A single unchecked box blocks
approval — and blocks writing `plan.md`.

## Completeness

- [ ] The purpose explains the need, not the solution.
- [ ] Scope names what is **out**, not only what is in.
- [ ] Every actor who touches the feature appears in a scenario.
- [ ] The unhappy paths are covered, not just the happy one.
- [ ] Every constant and threshold appears in the business-rules table with its rationale.
- [ ] There are no `[NEEDS CLARIFICATION]` markers left.

## Altitude

- [ ] No React component, table, column, package or function name appears in the requirements.
- [ ] The spec would still be correct if the implementation were rewritten from scratch.
- [ ] Nothing is described as "obvious" or "as it works today" without being written down.

## Testability

- [ ] Every requirement can be verified by running the system.
- [ ] No requirement uses an unmeasurable word — fast, simple, intuitive, robust — without a
      number or an observable behaviour attached.
- [ ] Every acceptance criterion is an outcome a reviewer can observe, not a task to perform.

## Security and integrity

- [ ] If the feature awards, spends or displays points, section 7 exists and is filled in.
- [ ] Any rule that must not be bypassable is enforced by a constraint, an index, or a
      conditional write — not only by a check the client could skip.
- [ ] Identity is derived from the session, never accepted as input.
- [ ] No secret is required to reach the client.
- [ ] The constitution principles at stake are named.

## Consistency

- [ ] Terms match `.specify/memory/glossary.md` exactly.
- [ ] The spec does not contradict `.specify/memory/architecture.md`, or it explicitly proposes
      an amendment to it.
- [ ] Related specs are cross-referenced, and none of them now contradicts this one.
- [ ] Any decision that constrains future work has an ADR.

## Retro-specs only

- [ ] Every requirement has an *As-built* anchor pointing at code that exists today.
- [ ] Anchors were verified against the current branch, not assumed.
- [ ] Deviations between spec and code are listed, each one labelled as a code bug or a spec bug.
