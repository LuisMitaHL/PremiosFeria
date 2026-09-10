---
description: Entrevista al usuario y redacta el spec de una funcionalidad (SDD, paso 1)
argument-hint: <descripcion de la funcionalidad a especificar>
---

Argumentos: $ARGUMENTS

Write the specification for a new feature, following this project's Spec-Driven Development
process. The feature to specify is described in the arguments; if none were given, ask what to
specify before doing anything else.

## Before you start

Read, in this order:

1. `AGENTS.md` — the working rules.
2. `.specify/memory/constitution.md` — the non-negotiable principles.
3. `.specify/memory/glossary.md` — the binding domain vocabulary.
4. `.specify/memory/architecture.md` — how the system actually works.
5. `specs/README.md` — the index, to find the next free number.

## Steps

**1. Reserve the number and the branch.**
Take the next unused `NNN` from `specs/README.md`. Choose a short English slug that names the
capability, not the implementation. Create the directory `specs/NNN-slug/` and, if you are about
to do implementation work, the branch `NNN-slug` off `develop`.

**2. Interview the user. Do not skip this.**
The point of a spec is to capture intent that the code cannot express. Ask before you write, in
Spanish, and prefer a small number of sharp questions over a long questionnaire. Cover:

- **Purpose** — what need does this serve, and what changes for the actor once it exists?
- **Actors** — participant, stand admin, event operator? Which of them touch this?
- **Rules** — every threshold, limit, cooldown and constant, *and the reason for its value*.
- **Edge cases** — what happens when it fails, when it is abused, when two people race.
- **Scope** — what is explicitly out, and which spec covers it instead.
- **Acceptance** — how will the user know this is done and correct?

If the feature is a retro-spec, first read the code that implements it and come to the interview
with a concrete reading of what it does today, so the questions are about *intent* rather than
about behaviour you could have read yourself. Present what you found, then ask what was
deliberate and what was accidental.

**Never guess a business rule.** Anything still unresolved goes into the spec as
`[NEEDS CLARIFICATION: the question]`.

**3. Write `spec.md`.**
Copy `.specify/templates/spec-template.md` and fill every section. In English. Rules:

- Describe behaviour, never implementation. No component, table, column, package or function
  names in the requirements.
- Every requirement numbered, atomic and verifiable by running the system.
- No unmeasurable adjectives without a number attached.
- Use glossary terms exactly.
- If the feature awards, spends or displays points, section 7 is mandatory and must name the
  structural gate — a constraint, an index, or a conditional write.
- For a retro-spec, fill *As-built notes* with real file and line anchors that you verified,
  and set `Status: Implemented`. Otherwise delete that section and set `Status: Draft`.

**4. Update the index.**
Set the spec's row in `specs/README.md` to its new status.

**5. Review it.**
Run `.specify/checklists/spec-review.md` against what you wrote and fix what fails before
handing it over.

**6. Commit.**
One `docs` commit, message in Spanish with the emoji, for example:
`docs: 📚 especificar el canje de premios`.
**No AI attribution of any kind in the commit message.**

## Then stop

Do not write `plan.md` and do not write code. The spec has to be approved by the user first.
Report what you wrote, and list any `[NEEDS CLARIFICATION]` markers still open.
