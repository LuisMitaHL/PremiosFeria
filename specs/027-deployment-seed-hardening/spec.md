# Spec 027 — Deployment seed hardening

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `027-deployment-seed-hardening` |
| **Actors** | Event operator |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

> Written in English. Describes WHAT and WHY, never HOW.
> No component names, table names, packages or function names in the requirements —
> those belong in `plan.md` and in *As-built notes*.
> Use the terms from `.specify/memory/glossary.md`. Do not invent new ones.

## 1. Purpose

An operator stands the system up for a fair. The first initialization reads the stand and
reward accounts from files the operator supplies. When those files are missing or malformed,
initialization stops — but the database has already been created, so the container restarts
and serves a system that looks healthy and has no accounts at all. The operator finds out at
the login screen, on the day of the event. This spec makes that failure visible at start-up
and gives the operator versioned templates to fill in, so a first boot either completes or
refuses to pretend that it did.

## 2. Scope

**In scope**

- Versioned example seed files that can be committed because they hold no real credentials.
- Instructions to copy and edit those examples before the first boot.
- Making an incomplete initialization visible: the database is not reported ready and the
  services that depend on it are not started.
- Interpreting an operator-supplied credential identically in every environment.

**Out of scope**

- The long-term decision between supplying accounts from files and creating them in the
  panel. Spec 012 retired file-based provisioning; the operator path that exists today still
  uses files, and this spec hardens that path rather than replacing it (see open question 9).
- The organiser's bootstrap, which spec 017 owns.
- Where credentials are stored, or how they are hashed.
- The CDN and the network topology around the stack.

## 3. User scenarios

### 3.1 An operator prepares a first boot

**Given** an operator with a fresh deployment
**When** they follow the deployment documentation
**Then** they copy the tracked templates, fill them in, and the first boot creates the
accounts those files describe.

### 3.2 The seed inputs are missing

**Given** a first boot with no seed files present
**When** initialization runs
**Then** it stops, the database never reports ready, the API is never started, and the
operator sees the failure instead of an empty login screen.

### 3.3 The container restarts after a failed initialization

**Given** a first boot that stopped before finishing
**When** the database container restarts on its own
**Then** it still does not report ready. It must not silently skip to a ready state.

### 3.4 A credential is written with surrounding spaces

**Given** a credential with leading or trailing spaces in the seed file
**When** the account is loaded and later used to sign in
**Then** the visible credential works, exactly as it does locally.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The repository MUST ship versioned example seed files for both required inputs. | Must |
| R2 | The operator documentation MUST instruct the operator to copy and edit those examples before the first boot. | Must |
| R3 | Both required seed inputs MUST exist for the first initialization to proceed. | Must |
| R4 | An initialization that stops early MUST leave the database not ready, and the services that depend on it MUST NOT start. | Must |
| R5 | A restart after a failed initialization MUST NOT report the database ready. | Must |
| R6 | The database MUST NOT report ready until initialization has completely finished, access restrictions included. | Must |
| R7 | A credential MUST be interpreted the same way in local development and in production. | Must |
| R8 | The versioned example files MUST NOT contain a real credential or a value that works as written. | Must |
| R9 | A failed initialization MUST leave an explanation in the database log. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Both inputs required | Always, even if one carries only a header | The initialization reads them unconditionally; a missing file is the most common operator mistake, and a silent empty fair is worse than a refused boot. |
| Ready means fully initialized | Only after the last structural step | A database that reports ready before its access restrictions are in place would serve credentials it is about to hide. |
| Whitespace around a credential is not significant | Always | The two paths that load credentials must hash the same input. A password that works locally and not in production is a bug the operator cannot see. |
| Examples are placeholders | Always | Anything committed is public. An example that works as written is a credential in the repository. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | What the operator sees |
|---|---|---|
| A required input file is missing | Initialization stops | The database container reports unhealthy; the log names the missing file |
| An input file is malformed (bad header, blank name, non-numeric cost) | Initialization stops | The database container reports unhealthy; the log carries the cause |
| An input file carries a header only | Initialization succeeds with no rows for it | The stack starts normally |
| The container restarts after a failed initialization | It stays not ready | The database remains unhealthy; the API never starts |
| A credential has surrounding spaces | It is loaded without the padding | Sign-in succeeds with the visible credential |

## 7. Security and integrity

- **Examples are public (constitution V).** The example files are committed, so they carry
  placeholders only. The real files stay untracked and are the operator's responsibility.
- **Ready only after access restrictions (R6).** The signal that the database is ready is
  also the signal that its secret-bearing columns are protected. Reporting ready earlier
  would expose them to every client for the interval between the two.
- **Credential parity (R7).** Interpreting a credential differently per environment is a
  silent failure that surfaces as "wrong password" at the worst moment. The two loading
  paths must agree on what the credential is.
- This feature neither awards nor spends points, so the structural gate of the point economy
  is not engaged.

## 8. Acceptance criteria

- [ ] Two tracked example seed files exist and contain only placeholder values.
- [ ] The deployment documentation tells the operator to copy and edit them.
- [ ] A first boot with a missing seed file leaves the database unhealthy and the API unstarted.
- [ ] A container restart after that failure keeps the database unhealthy.
- [ ] A successful first boot reports the database healthy and starts the API.
- [ ] A credential written with surrounding spaces signs in with the visible value.
- [ ] The log of a failed initialization names the cause.

## 9. Open questions

[NEEDS CLARIFICATION: is file-based seeding the intended production path, given that spec 012 retired it in favour of the organiser creating communities and stands registering their own rewards? If files are transitional, this spec hardens a path that is scheduled to disappear and should say so.]

## 10. As-built notes

*Retro-specs only.* Anchors each requirement to the code that implements it today, so the spec
can be verified against reality. Delete this section for a spec describing work not yet built.

| Requirement | Implemented in |
|---|---|
| R1 | `seed/stands.csv.example`, `seed/rewards.csv.example` |
| R2 | `seed/README.md`, `README.md` section 4 |
| R3 | `supabase/postgres-init/70_seed.sql` |
| R4 | `docker-compose.yml` (`db` healthcheck) |
| R5 | `supabase/postgres-init/99_init_complete.sh`, `docker-compose.yml` |
| R6 | `99_init_complete.sh` runs after `80_column_grants.sql`; healthcheck requires the marker |
| R7 | `supabase/postgres-init/70_seed.sql` (trims the password before hashing) |
| R8 | the `.example` files |
| R9 | the PostgreSQL init log |

**Known deviations** — where the code does not match this spec, and whether the code or the spec
is considered wrong.

- Spec 012 is retired and says file-based provisioning disappears, while the code and the
  deployment documentation still seed from files. This is the subject of open question 9; the
  code is considered correct for now.
- A change of secrets while a database volume already exists remains a documented manual
  procedure, not something this spec guards. It is out of scope here.

## 11. References

- Spec 010 — `stand-login`, whose credentials these files feed.
- Spec 012 — `csv-provisioning`, retired; the successor to the provisioning path.
- Spec 017 — `organizer-admin-panel`, the organiser's bootstrap.
- Spec 023 — `organizer-community-management`, which takes over creating communities.
- `.specify/memory/constitution.md` — principles on secrets and business rules.
