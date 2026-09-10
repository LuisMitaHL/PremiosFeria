# Tasks NNN — <Feature name>

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Plan** | [`plan.md`](plan.md) — must be `Approved` before this file is written |
| **Branch** | `NNN-slug` |

> Each task is a single, independently reviewable unit of work with its own commit.
> Tasks marked `[P]` have no dependency on each other and can be done in parallel.
> Every task names the requirement it satisfies, so nothing is built that no spec asked for.

## Order of work

Database first, then backend, then frontend, then documentation. Tests are written alongside the
thing they test, never deferred to the end.

## Tasks

| # | Task | Satisfies | Files | Done |
|---|---|---|---|---|
| T1 | ... | R1 | `...` | [ ] |
| T2 [P] | ... | R2, R3 | `...` | [ ] |

## Commit plan

One commit per task, in Spanish, conventional format with emoji (see `AGENTS.md`):

```
T1 -> feat: ✨ <what changed, in Spanish>
T2 -> test: 🚨 <what is covered, in Spanish>
```

## Definition of Done

Before opening the pull request, run through
`.specify/checklists/definition-of-done.md` in full.
