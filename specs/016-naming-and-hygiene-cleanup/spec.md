# Spec 016 — Naming and hygiene cleanup

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `016-naming-and-hygiene-cleanup` |
| **Actors** | Participant, Stand admin |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

The product answers to six different names depending on where you look, tells attendees their data
is safely in the cloud on a screen that is about to warn them of the opposite, speaks to them in
emoji, and ships a file of abandoned credentials in its own repository.

None of this is a bug in the sense of something failing. It is what a system looks like after two
rebrands, a platform migration and a security audit, when nobody went back to tidy up. Left alone
it costs a little every time somebody new reads the code, and one or two things on the list — the
figure that is hardcoded to zero, the file in version control — cost more than that.

This spec is the tidy-up: one name, no emoji in the interface, a consistent visual surface, and
the loose ends closed.

## 2. Scope

**In scope**

- One name for the product, everywhere.
- Removing emoji from everything an attendee or a stand reads.
- Making the visual surface consistent: styles that belong to the design system, empty states that
  exist, new screens that match old ones.
- Removing the environment file from version control.
- The application icons that are referenced but absent.
- The fonts that are requested in a format that is not there.
- Code that no longer does anything.

**Out of scope**

- The README and the deployment documentation. Spec 026.
- Any change in behaviour. Every rule in the system means afterwards exactly what it meant before.
- Redesigning the interface. Considered and rejected as a separate concern: this spec makes what
  exists consistent, it does not reimagine it.
- Renaming the repository. It stays `PremiosFeria`; renaming it would break every remote the team
  has for no gain.

## 3. User scenarios

### 3.1 An attendee installs the app

**Given** an attendee adding the app to their home screen
**When** it installs
**Then** it has a name and an icon, and both are the ones the app uses everywhere else.

### 3.2 An attendee is refused

**Given** an attendee scanning a stand they visited ten minutes ago
**When** they are told to wait
**Then** the message reads as a sentence, without a padlock or a stopwatch standing in for words.

### 3.3 A developer clones the repository

**Given** somebody joining the project
**When** they look at what is checked in
**Then** they find an example environment file with no real values in it, and nothing that looks
like a credential.

### 3.4 A stand opens a screen that was added later

**Given** the sections and screens the newer specs introduce
**When** a stand moves between them
**Then** they look like the rest of the application, because they are built from the same design
system rather than from styles written into each component.

## 4. Requirements

### One name

| ID | Requirement | Priority |
|---|---|---|
| R1 | The product MUST be called **Community Quest** everywhere it is named. | Must |
| R2 | The name MUST be corrected in: the package manifest, the page title, the installable app manifest, the design system's own header, the production container name, and the token issuer. | Must |
| R3 | The repository MUST NOT be renamed. | Must |
| R4 | Changing the token issuer MUST NOT be done without first confirming nothing verifies it, and MUST be applied only in a fresh deployment, since it invalidates tokens in flight. | Must |

### No emoji

| ID | Requirement | Priority |
|---|---|---|
| R5 | No message shown to an attendee or a stand MUST contain an emoji, including messages produced by the database. | Must |
| R6 | Where an emoji carried meaning, it MUST be replaced by an icon from the set the application already uses, or by words. | Must |
| R7 | No emoji MUST appear in source code, in identifiers, in comments or in logs. | Must |
| R8 | Meaning MUST NOT be lost: a message that distinguished success from refusal by its emoji MUST still distinguish them. | Must |

### A consistent surface

| ID | Requirement | Priority |
|---|---|---|
| R9 | Styles written directly into components SHOULD be moved into the design system where an equivalent exists or belongs. | Should |
| R10 | Every screen that can be empty MUST have an empty state that explains rather than showing nothing. | Must |
| R11 | Screens introduced by other specs MUST use the same design system, spacing and components as the existing ones. | Must |

### Loose ends

| ID | Requirement | Priority |
|---|---|---|
| R12 | The environment file MUST be removed from version control and MUST be ignored from then on. | Must |
| R13 | An example environment file MUST be committed in its place, with no real values. | Must |
| R14 | The values currently in that file belong to an abandoned hosted project; that project SHOULD be shut down rather than merely unreferenced. | Should |
| R15 | Every icon the installable app manifest references MUST exist in the format it claims. | Must |
| R16 | Every font the stylesheet requests MUST exist in a format that is served. | Must |
| R17 | Code that is unreachable or unused MUST be deleted, not commented out. | Must |
| R18 | No figure shown to a user MUST be hardcoded. Anything that cannot be computed MUST be removed rather than faked. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| The canonical name | Community Quest | It is what the installable app already calls itself, which is the name attendees actually see. The others are earlier rebrands nobody finished. |
| The repository name | Unchanged | Renaming breaks every remote the team has, in exchange for a consistency nobody outside the team observes. |
| Emoji | None, anywhere a person reads | They render differently on every phone, part of the audience is on browsers from 2020, and a message whose meaning depends on a glyph is a message that fails on some devices. |
| Emoji in code | None, ever | Already a rule of the project (`AGENTS.md`); this spec brings the existing code in line with it. |
| Hardcoded figures | Never shown | A wrong number is worse than an absent one: it is indistinguishable from a real value. |
| The environment file | Removed and ignored | The values are a publishable key and a URL for a hosted project no longer in use — not a serious exposure, but exactly the shape of the mistake that later is one. |
| Behaviour | Unchanged | This is the one spec where "no behaviour change" is the point, and it should be verifiable by running the tests before and after. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour |
|---|---|
| Something verifies the token issuer | The issuer is left alone and the deviation recorded, rather than breaking authentication for the sake of a name |
| A message loses meaning without its emoji | The words carry it instead; the message is rewritten rather than truncated |
| The environment file is removed while somebody has it checked out | It stays on their disk, ignored; the example file says what it should contain |
| An icon is referenced in a format that does not exist | The icon is produced in that format, rather than the reference quietly pointed at something absent |
| A style moved into the design system changes an unrelated screen | It stays where it is. Consistency is not worth a regression in a screen nobody asked to touch |
| Deleted code turns out to be referenced | It was not unused; it stays, and the spec was wrong about that item |

## 7. Security and integrity

Two items are the reason this is not purely cosmetic.

- **The committed environment file (R12 to R14).** It holds the URL and publishable key of an
  abandoned hosted project. A publishable key is meant to be public, so nothing is exposed today —
  but it establishes that credentials live in this repository, and the next one may not be
  publishable. Removing the file is half the job; shutting the project down is the other half.
- **The hardcoded figure (R18).** A screen showing a number it did not compute asserts something
  false to a user with no way for them to tell. It is also the precedent the rest of the system
  reasons against.
- **Nothing here may weaken a rule.** Removing emoji touches the messages the database returns on
  refusal. Those strings are the visible half of rules that protect the point economy; rewriting
  them must not change which branch produces them, and the tests asserting those refusals must
  pass unchanged in substance.

## 8. Acceptance criteria

- [ ] The product is called Community Quest in the package manifest, the page title, the app
      manifest, the design system header and the container name.
- [ ] The token issuer is either corrected, or left alone with the reason recorded.
- [ ] The repository is not renamed.
- [ ] No message shown to an attendee or a stand contains an emoji, including those from the
      database.
- [ ] Every refusal still distinguishes itself from a success without relying on a glyph.
- [ ] No emoji appears in source code, identifiers, comments or logs.
- [ ] Every screen that can be empty explains its empty state.
- [ ] The environment file is no longer tracked, is ignored, and an example with no real values is
      committed in its place.
- [ ] Every icon the app manifest references exists in the format it claims.
- [ ] Every font the stylesheet requests exists in a served format.
- [ ] No unreachable or unused code remains, and none is commented out.
- [ ] No figure shown to a user is hardcoded.
- [ ] The lint gate runs with no unused-code exemptions remaining.
- [ ] Every test that passed before this spec passes after it, unchanged in substance.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Everything below is present today.

**Six names for one product**

| Where | Name |
|---|---|
| `README.md` | FeriaPoints |
| `package.json` | `comunity-quest` (with the typo) |
| `vite.config.js`, `index.html` | Community Quest |
| `src/index.css` | Comunity Quest Design System (with the typo) |
| `docker-compose.yml` | container `feriapoints` |
| `auth/server.mjs` | token issuer `premiosferia` |
| the repository | PremiosFeria |

**Emoji in user-facing messages** — concentrated in `supabase/postgres-init/50_rpc.sql`, which
returns one on every refusal: a person for "register first", a stopwatch for an expired code, a
shield for a forged one, a padlock for the cooldown, a tick for an activity already completed. The
messages in `claim_reward` carry them too.

**Loose ends**

| Item | Where |
|---|---|
| A permanently zero figure labelled "Premios" | `src/pages/Dashboard.jsx:57-58` — the one explicit TODO in the application |
| The environment file, tracked, with a hosted project's URL and publishable key | `.env` |
| App manifest icons referencing `.png`; only `.svg` exists | `vite.config.js`, `index.html`, `public/` |
| A font requested as `.woff2`; only `.ttf` exists | `src/index.css` against `public/fonts/` |
| A function nobody calls | `getAllScans`, `src/lib/api.js:119-127` |
| A value computed and never rendered | `const rest`, `src/pages/Leaderboard.jsx:35` |
| Imports that are not used | `src/App.jsx`, `src/pages/Welcome.jsx`, `src/pages/Register.jsx`, `src/pages/Scanner.jsx` |
| Styles written into components rather than the design system | throughout `src/pages/` |

**Consequences the plan must address**

- The lint configuration currently downgrades unused code to a warning, in a block whose comment
  names this spec. Completing R17 is what allows that block to be deleted and the gate tightened,
  which is the observable proof the cleanup happened.
- Rewriting the database's refusal messages changes `supabase/postgres-init/50_rpc.sql`, which
  runs once on an empty volume — so it lands in a deployment, never during an event.
- R11 only makes sense once the screens it refers to exist. This spec is best done late, or split
  so the loose ends land early and the consistency work lands after the new screens.
- The token issuer must be checked before it is touched. Nothing appears to verify it, but that has
  to be established rather than assumed.

## 11. References

- `AGENTS.md` — the no-emoji-in-code rule this brings the existing code in line with.
- Constitution: V (secrets never reach the client), IX (quality gates).
- Glossary: the note on the legacy `emoji` column, which this spec does **not** rename.
- Spec 013 — `participant-dashboard`, which removes the hardcoded figure as part of its own work.
- Spec 026 — `project-documentation`, which owns the README.
- Specs 017 to 025 — the screens R11 must match.
