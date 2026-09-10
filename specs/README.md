# Specifications

One directory per feature: `NNN-slug/`, containing `spec.md` (what and why) and, when work is to
be done, `plan.md` (how) and `tasks.md` (steps). **Numbers are assigned once and never reused or
renumbered**, including numbers that were reserved and then abandoned.

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
| `Superseded` | Replaced; the successor spec is named in the row |

---

## Behaviour that already ships

Retro-specs, documenting the system as built. They carry *As-built notes* and no `plan.md` or
`tasks.md` unless a change is proposed against them.

| # | Spec | Actor | Status |
|---|---|---|---|
| 002 | `camera-qr-scan` | Participant | Not started |
| 003 | `manual-code-fallback` | Participant | Not started |
| 004 | `visit-cooldown-rules` | Participant | Not started |
| 007 | `live-leaderboard` | Participant | Not started |
| 010 | `stand-login` | Stand admin | Not started |
| 015 | `pwa-shell` | Participant | Not started |

## Changes to behaviour that ships

Part retro-spec, part change. Each opens with what exists today and why it is being replaced.

| # | Spec | Actor | Status |
|---|---|---|---|
| 001 | [`participant-registration`](001-participant-registration/spec.md) | Participant | Draft |
| 011 | `qr-projection` | Stand admin | Not started |
| 013 | [`participant-dashboard`](013-participant-dashboard/spec.md) | Participant | Draft |
| 016 | `naming-and-hygiene-cleanup` | — | Not started |

## New capabilities

| # | Spec | Actor | Status |
|---|---|---|---|
| 017 | [`organizer-admin-panel`](017-organizer-admin-panel/spec.md) | Event operator | Draft |
| 018 | [`in-person-reward-fulfilment`](018-in-person-reward-fulfilment/spec.md) | Participant, Stand admin | Draft |
| 019 | [`stand-activity-catalogue`](019-stand-activity-catalogue/spec.md) | Stand admin | Draft |
| 020 | [`fixed-points-model`](020-fixed-points-model/spec.md) | Participant, Stand admin | Draft |
| 021 | [`stand-reward-management`](021-stand-reward-management/spec.md) | Stand admin | Draft |
| 022 | [`organizer-student-management`](022-organizer-student-management/spec.md) | Event operator | Draft |
| 023 | [`organizer-community-management`](023-organizer-community-management/spec.md) | Event operator | Draft |
| 024 | [`system-audit-log`](024-system-audit-log/spec.md) | Event operator | Draft |
| 025 | [`participant-activity-progress`](025-participant-activity-progress/spec.md) | Participant | Draft |
| 026 | `project-documentation` | — | Not started |

## Numbers retired before they were written

These were reserved when the inventory assumed the original points and rewards model. That model
is being replaced, so writing a retro-spec for them would have documented behaviour that is about
to be deleted. The numbers stay retired rather than being reused.

| # | Was going to be | Replaced by | Why |
|---|---|---|---|
| 005 | `activity-once-per-stand` | 019, 020 | One activity per stand becomes up to three, each a real entity with its own identity |
| 006 | `points-ceiling-enforcement` | 020 | Per-stand configurable ceilings become fixed event-wide values |
| 008 | `rewards-catalog` | 021, 018 | The catalogue stops being seed-only and becomes something a stand manages |
| 009 | `reward-claiming` | 018 | Claiming in the app is replaced by in-person fulfilment confirmed by the stand |
| 014 | `stand-admin-console` | 019, 021 | Its point configuration disappears; what remains is activity and reward management |
| 012 | `csv-provisioning` | 017, 023, 021 | Seeding stands and rewards from CSV disappears: the organiser creates stands, and stands register their own rewards |

---

## Working order

Numeric order no longer matches dependency order: the new requirements introduce a foundation
that several other specs stand on. Working numerically would mean specifying rewards against a
points model that is about to change underneath them.

The order is therefore by dependency. Note that **023 became critical path** once the organiser
took over creating stands: without it there are no stands, so there is no fair.

```
017 organizer-admin-panel       <- the organiser identity and the panel shell
 |
 +-- 023 organizer-community-management   <- CRITICAL PATH: stands and their
 |                                           credentials now exist only here
 +-- 022 organizer-student-management     (delivers R10b of spec 001)
 +-- 024 system-audit-log

020 fixed-points-model          <- the points model everything else assumes
 |
 +-- 019 stand-activity-catalogue   (activities, and one QR per activity)
 |     |
 |     +-- 011 qr-projection        (the stand picks which activity it is showing)
 |     +-- 025 participant-activity-progress
 |
 +-- 021 stand-reward-management    (a stand registers its own rewards and their cost)
       |
       +-- 018 in-person-reward-fulfilment   (single-use code, the stand confirms,
                                              points and stock spent together)

Independent of the above: 002, 003, 004, 007, 013, 015, 016, 026
```

Spec 001 is already drafted and is not blocked by any of them.

## A note on scope

Several of these change the database schema. The initialisation scripts in
`supabase/postgres-init/` run **once, on an empty volume**, so none of it can be applied to a
fair already in progress. Group the schema changes into as few deployments as possible and say so
in each `plan.md`.
