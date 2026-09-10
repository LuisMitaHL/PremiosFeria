---
mode: agent
description: Audita un spec contra el checklist de revision
---

Argumentos: <NNN o slug del spec a revisar>

Audit a specification against this project's review checklist. The spec is named in the
arguments; if none were given, ask which one, or offer to review every spec whose status is
`Draft` or `In review`.

## Before you start

Read `.specify/checklists/spec-review.md`, `.specify/memory/constitution.md` and
`.specify/memory/glossary.md`.

## How to review

Go through the checklist item by item. For each one, state **pass** or **fail** — and for every
failure, quote the offending line and say what it should be instead. A vague verdict is useless;
the author must be able to act on it without asking you a follow-up question.

Be adversarial about these four, which are where specs in this project actually fail:

1. **Altitude.** Requirements that name a component, a table, a column, a package or a function
   have leaked implementation into the spec. Move them to `plan.md`.
2. **Testability.** Any requirement you could not verify by running the system is not a
   requirement yet. Words like fast, simple, intuitive or robust with no number attached are a
   fail.
3. **Point economy.** If the feature awards, spends or displays points and section 7 is missing,
   thin, or names only an `IF` rather than a constraint, an index or a conditional write, that is
   a fail.
4. **Retro-spec anchors.** Open the files the *As-built notes* cite and check the anchors point
   at code that really does what the requirement claims. Do not take them on trust.

Also flag: leftover `[NEEDS CLARIFICATION]` markers, terms that are not in the glossary,
contradictions with `.specify/memory/architecture.md`, and contradictions with another spec.

## Output

Report in Spanish, in this shape:

- **Veredicto**: listo para aprobar, o cuántos puntos bloquean la aprobación.
- **Bloqueantes**: each failure, with the quoted line and the concrete fix.
- **Sugerencias**: improvements that do not block.

Do not edit the spec unless the user asks you to. Reviewing and rewriting in one pass hides
what was wrong.
