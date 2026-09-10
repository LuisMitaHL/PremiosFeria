# Specifications

One directory per feature: `NNN-slug/`, containing `spec.md` (what and why) and, when work is to
be done, `plan.md` (how) and `tasks.md` (steps). Numbers are assigned once and never reused or
renumbered.

Specs are written in **English**; the UI, commit messages and team documentation are in Spanish.
See `.specify/memory/glossary.md` for the binding translation of every domain term.

Read `.specify/memory/constitution.md` before writing or reviewing any spec.

## Status values

| Status | Meaning |
|---|---|
| `Not started` | Number reserved, no interview held yet |
| `Draft` | Written, not yet reviewed against `.specify/checklists/spec-review.md` |
| `In review` | Under review; unresolved `[NEEDS CLARIFICATION]` markers may remain |
| `Approved` | Passed review. Only now may `plan.md` be written |
| `Implemented` | Behaviour is live and anchored in *As-built notes* |
| `Superseded` | Replaced; the successor spec is named in the header |

## Retro-specs — behaviour that already ships

These document the system as built. They carry *As-built notes* and no `plan.md` or `tasks.md`
unless a change is proposed against them.

| # | Spec | Actor | Status |
|---|---|---|---|
| 001 | `participant-registration` | Participant | Not started |
| 002 | `camera-qr-scan` | Participant | Not started |
| 003 | `manual-code-fallback` | Participant | Not started |
| 004 | `visit-cooldown-rules` | Participant | Not started |
| 005 | `activity-once-per-stand` | Participant | Not started |
| 006 | `points-ceiling-enforcement` | Participant, Stand admin | Not started |
| 007 | `live-leaderboard` | Participant | Not started |
| 008 | `rewards-catalog` | Participant | Not started |
| 009 | `reward-claiming` | Participant | Not started |
| 010 | `stand-login` | Stand admin | Not started |
| 011 | `qr-projection` | Stand admin | Not started |
| 012 | `csv-provisioning` | Event operator | Not started |
| 013 | `participant-dashboard` | Participant | Not started |
| 014 | `stand-admin-console` | Stand admin | Not started |
| 015 | `pwa-shell` | Participant | Not started |

## New work

These run the full cycle: interview, spec, plan, tasks, implementation.

| # | Spec | Actor | Status |
|---|---|---|---|
| 016 | `naming-and-hygiene-cleanup` | — | Not started |
| 017 | `event-organizer-role` | Event operator | Not started |
| 018 | `reward-fulfilment-verification` | Participant, Stand admin | Not started |

## Working order

Numeric. Each spec begins with an interview — the questions come first, the document second —
and lands as its own `docs` commit.
