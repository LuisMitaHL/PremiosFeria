# Tareas

> Descompone un plan aprobado en tareas ejecutables (SDD, paso 3)
>
> Argumentos: lo que el usuario escriba despues del comando.

Break an approved plan into executable tasks. The spec is named in the arguments; if none were
given, ask which one.

## Before you start

Read `AGENTS.md`, the spec and the plan.

**Refuse to proceed if** the plan's status is not `Approved`. Say so and stop.

## Steps

**1. Derive the tasks from the plan**, not from your own idea of what the feature needs. If the
plan does not cover something a task would need, the plan is incomplete — go back and say so
rather than inventing scope.

**2. Order them: database, then backend, then frontend, then documentation.**
Tests are written alongside the thing they test, never batched at the end.

**3. Size them.** One task is one reviewable unit of work with one commit. If a task cannot be
described in a single sentence, split it. Mark tasks that have no dependency on each other
with `[P]`.

**4. Trace them.** Every task names the requirement it satisfies. A task that satisfies no
requirement should not exist — remove it, or amend the spec first.

**5. Write `tasks.md`** from `.specify/templates/tasks-template.md`, in English, into the spec's
directory. Include the commit plan: the Spanish conventional message each task will produce.

**6. Commit.** `docs: 📚 descomponer en tareas <la funcionalidad>`. **No AI attribution.**

## Then

Ask whether to begin executing the tasks. When executing, work one task at a time, commit each
one separately, and run `npm run lint` and `npm test` as you go — never `npm run build`.
Before opening the pull request, walk `.specify/checklists/definition-of-done.md` in full.
