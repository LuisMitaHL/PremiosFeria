# Spec 017 — Organizer admin panel

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `017-organizer-admin-panel` |
| **Actors** | Event operator |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

The person running the fair has no account. Everything they need to do — creating stands, handing
out credentials, loading prizes, fixing a mistake, understanding what is happening — is done with
`psql`, CSV files and a redeploy. That works for setting up in advance and not at all once three
hundred people are in the building: the moment something needs correcting, the only person who
can correct it is whoever has a terminal and the database password.

This spec gives the organiser an identity and a place to stand. It is the shell the rest of the
panel lives in: a way to log in, a way to move between the four things they manage, and a single
screen that answers "how is the fair going" without anyone querying anything. The four areas
themselves — students, communities, rewards, the log — are specified separately.

## 2. Scope

**In scope**

- The organiser identity: what it is, how it is created, and how it logs in.
- Where the panel lives and who can reach it.
- The session, and how it ends.
- The panel's navigation to its four areas.
- The home screen and the figures on it.

**Out of scope**

- What the organiser can actually do in each area. Spec 022 for students, spec 023 for
  communities and their credentials, spec 024 for the log, spec 021 for reward costs and stock.
- Anything an organiser cannot do. The panel grants exactly the authority those specs describe;
  it is not a general override.
- Provisioning the deployment itself — secrets, containers, the CDN. Spec 026 documents it; this
  spec only adds the organiser's credentials to what is generated.

## 3. User scenarios

### 3.1 The organiser signs in

**Given** the organiser has the credentials produced when the system was deployed
**When** they open the panel's address and enter them
**Then** they are taken to the home screen. Nothing anywhere in the attendee's or the stand's app
would have led them there.

### 3.2 The organiser reads the room

**Given** the fair has been running for two hours
**When** the organiser looks at the home screen
**Then** they can see how many people have registered, how many points have been handed out and
spent, how many prizes have been given away and what stock is left across the fair, and which
activities are running right now.

### 3.3 The organiser checks the economy before opening

**Given** the stands have registered their prizes
**When** the organiser looks at the home screen before the doors open
**Then** they can compare the most expensive prize on offer against the most an attendee could
possibly earn, and go and talk to any stand whose prize nobody will ever be able to claim.

### 3.4 The organiser leaves the table

**Given** the panel is open on a laptop at the organisation desk
**When** whoever is sitting there gets up
**Then** they can sign out from wherever they are in the panel, without hunting for the control.

## 4. Requirements

### Identity

| ID | Requirement | Priority |
|---|---|---|
| R1 | There MUST be exactly one organiser account, shared by the organising team. | Must |
| R2 | The organiser MUST authenticate with a username and a password. | Must |
| R3 | The password MUST be stored only as a hash, and MUST NOT be recoverable from the system. | Must |
| R4 | The organiser account MUST be created when the system is deployed, by the same step that generates the deployment's other secrets. | Must |
| R5 | The organiser account MUST NOT be creatable, or its password changeable, from inside the application. | Must |
| R6 | The organiser's credentials MUST NOT appear in the repository, in anything served to a browser, or in any log. | Must |
| R7 | A failed sign-in MUST NOT reveal whether the username exists. | Must |
| R8 | Repeated failed sign-in attempts MUST be rate limited. | Must |

### Reaching the panel

| ID | Requirement | Priority |
|---|---|---|
| R9 | The panel MUST be part of the same application, at its own address. | Must |
| R10 | No screen shown to an attendee or to a stand MUST link to the panel. | Must |
| R11 | Every screen of the panel MUST be unreachable without an organiser session. | Must |
| R12 | R11 MUST hold where the data is served, not only by hiding a route: reaching the address directly, or calling the API directly, MUST fail the same way. | Must |
| R13 | An organiser session MUST last as long as a stand's. | Must |
| R14 | A control to sign out MUST be visible from every screen of the panel. | Must |

### The panel

| ID | Requirement | Priority |
|---|---|---|
| R15 | The panel MUST offer navigation to four areas: students, communities, rewards and the system log. | Must |
| R16 | The home screen MUST show, for the whole event: how many participants have registered, how many points have been awarded, and how many have been spent. | Must |
| R17 | The home screen MUST show how many rewards have been handed over and how much stock remains across every stand. | Must |
| R18 | The home screen MUST show which activities are running at that moment, and at which stand. | Must |
| R19 | The home screen MUST show the highest published reward cost alongside the most an attendee could earn by visiting every stand once and completing every published activity. | Must |
| R20 | Every figure on the home screen MUST cover the whole event, never a single stand. | Must |
| R21 | The home screen SHOULD keep itself current without the organiser reloading it. | Should |

### Authority

| ID | Requirement | Priority |
|---|---|---|
| R22 | The organiser MUST NOT be able to act as a participant or as a stand. | Must |
| R23 | The organiser's authority MUST be exactly what specs 021, 022, 023 and 024 grant, and no more. There MUST be no general override. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Organiser accounts | Exactly one, shared | Chosen deliberately, with the cost understood: the system log (spec 024) can record that the organiser did something, but never which person. The organising team is small and sits together, and one credential to hand out on the day beats several to manage. **If the log ever needs to name a person, this is the rule to change first.** |
| Account creation | At deployment, by the secret-generation step | Nobody inside the system can create the account that creates everyone else. Generating it alongside the other secrets makes it strong by construction, written once to a file only the operator can read, and never typed into a repository. |
| Password changes | Outside the application | The same position stand passwords are in today: rotated by an operator against the database. A change-password screen for a single shared account would add a path to the most powerful credential in the system for very little gain. |
| Session length | The same as a stand's | Covers a whole fair without signing in again, which matters on a laptop people walk away from and come back to. Paired with R14, so leaving is a deliberate act rather than a hunt. |
| Discoverability | Not linked from anywhere | The attendee's welcome screen already links to the stand panel; the organiser's must not be reachable by curiosity. This is not a security control — R11 and R12 are — it just keeps three hundred people away from a sign-in screen that is not for them. |
| Maximum achievable | One visit per stand, plus every published activity | The comparison that matters is not the theoretical maximum, which requires re-scanning every stand all afternoon, but what a diligent attendee actually earns. A prize above that number is claimed by nobody. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| Wrong password | Refused, with no hint about which half was wrong | "Credenciales incorrectas." |
| Unknown username | Identical refusal | as above |
| Many failed attempts | Refused for a while, saying so | "Demasiados intentos. Espera unos minutos." |
| The panel address is opened without a session | The sign-in screen, and no glimpse of the panel | none |
| A participant's or stand's session opens a panel address | Refused exactly as if signed out; the data is never served | none |
| The session expires while the panel is open | The next action returns to sign-in, without appearing to have worked | "Tu sesión expiró. Vuelve a iniciar sesión." |
| No stands or participants yet | Zeroes, not an error and not an empty page | none |
| No activity running | Said plainly | "Ninguna actividad en curso." |
| No rewards published yet | The economy comparison is unavailable rather than a misleading zero | "Todavía no hay premios publicados." |
| The most expensive prize is beyond reach | Shown as such, clearly enough to act on | "El premio más caro está fuera de alcance." |
| The organiser account was never generated at deployment | The system refuses to finish starting, loudly, rather than starting with no organiser | (operator-facing, at deploy time) |

## 7. Security and integrity

The organiser credential is the most powerful in the system, and it is shared.

- **Created outside, unchangeable inside (R4, R5).** There is no path from a compromised session
  to a permanently changed password, and no screen that could be tricked into creating a second
  organiser.
- **Access is enforced where the data is (R12, constitution IV).** Hiding a route is not access
  control. A participant's or stand's session presenting itself at a panel endpoint must be
  refused by the same mechanism that scopes every other actor: from the session, in the database.
  This is the mistake the existing stand panel already makes — its guard is a redirect inside a
  component — and it is only safe there because the real control is elsewhere.
- **The panel ships in the public bundle (R9).** Anyone can read its code, so nothing in it may be
  a secret and nothing in it may be the enforcement. It draws screens; the database decides.
- **Authority is enumerated, not implied (R23).** The organiser can do what four specs say and
  nothing else. In particular they cannot award points, cannot confirm a handover in a stand's
  name, and cannot act as an attendee. An organiser who could quietly grant points would make
  every position on the leaderboard deniable.
- **Sign-in must not enumerate (R7, R8).** With a single account the username is a guessable word,
  so the password is the only secret and rate limiting is what protects it. The auth service
  already does both for stands, and the same treatment applies.
- **One shared account is an accepted weakness.** The log cannot attribute an action to a person,
  and a leaked credential cannot be narrowed to one holder. Recorded here as a decision, not an
  oversight.

## 8. Acceptance criteria

- [ ] The organiser can sign in with the credentials produced at deployment.
- [ ] Those credentials appear nowhere in the repository or in anything served to a browser.
- [ ] A wrong password and an unknown username produce the same refusal.
- [ ] Repeated failures are rate limited.
- [ ] No screen in the attendee's or the stand's app links to the panel.
- [ ] Opening a panel address without a session shows sign-in and no panel data.
- [ ] A stand's session calling a panel endpoint directly is refused and receives no data.
- [ ] A participant's session calling a panel endpoint directly is refused and receives no data.
- [ ] Sign-out is reachable from every screen of the panel.
- [ ] The home screen shows participants, points awarded and points spent for the whole event.
- [ ] The home screen shows rewards handed over and stock remaining across every stand.
- [ ] The home screen lists the activities running right now and their stands.
- [ ] The home screen compares the most expensive published reward against the maximum a diligent
      attendee could earn.
- [ ] With no stands, participants, activities or rewards, the home screen shows zeroes and plain
      statements rather than errors.
- [ ] The organiser cannot award points, cannot confirm a handover, and cannot act as an attendee.

## 9. Open questions

None.

## 10. Current behaviour and the gap

Nothing in this spec exists. There is no organiser in the system at all.

| Concern | Today |
|---|---|
| Identity | Two actors: participants on anonymous sessions, and stands on a username and a bcrypt password verified by the `stand_login` function. There is no third. |
| The operator | Works entirely outside the application: CSV files read once at first database start, `psql` for corrections, `docker compose` for everything else. |
| Credentials at deploy | `deploy-keys.sh` already generates the JWT secret, the API keys and the database password into a secrets file with restricted permissions. The organiser's credentials join what it produces. |
| Access control on panels | The stand panel's routes have no wrapper: each component redirects from inside itself. Cosmetic by the code's own admission; the real control is the database. The organiser panel must not copy that pattern for its data. |
| Event-wide figures | Nothing computes them. The stand console shows one stand's totals plus the number of registered participants. |

**Consequences the plan must address**

- A third identity in a service built for two. The auth service verifies stand passwords through a
  database function; the organiser needs the equivalent, kept separate so a stand can never
  authenticate as an organiser or the reverse.
- `deploy-keys.sh` gains the organiser's credentials, and the first database start has to accept
  them the way it currently accepts seeded stands.
- The home screen's figures are aggregates across every table. They are read often, by one person,
  and must not be assembled by pulling every row into the browser.
- The maximum-achievable figure depends on spec 020's constants and on what stands have published,
  so it is computed, never stored.

## 10b. As built

A separate table, `organizers`, with RLS on and no policy — and no client grant either, so a stand
asking for it gets "permission denied" rather than an empty result. `organizer_login` mirrors
`stand_login` against its own table: two functions, each looking at one table, is what stops a
stand ever authenticating as an organiser or the reverse. Both were asserted in both directions.

`event_overview()` computes every figure in one read. The reachable maximum is derived from spec
020's constants and what stands have published, never stored.

The account is created at deployment: `deploy-keys.sh` generates the username and a strong
password into the secrets file, and `71_organizer_seed.sh` loads it at first boot. **The boot fails
loudly if the variables are unset** — an event that starts and cannot be administered is a worse
failure than one that does not start, because it is discovered on the day.

**Verified in the browser**: the organiser signs in at an address nothing links to, and the home
screen shows the six figures, what is running, and the economy check — which immediately earned its
place by flagging that the most expensive published prize (250) was above what anyone could earn
(100). A stand's session calling the same endpoint gets "No autorizado" and cannot read the table
at all.

**Not built.** The four areas are placeholders: students (022), communities and reward powers
(023), and the log (024).

## 11. References

- Constitution: IV (identity is never a parameter), V (secrets never reach the client), IX
  (quality gates).
- ADR 0002 — the auth service, which this extends rather than replaces.
- Glossary: *Event operator*, *Stand*, *Participant*.
- Spec 022 — `organizer-student-management`, which also delivers R10b of spec 001.
- Spec 023 — `organizer-community-management`, which creates stands and their credentials, and
  delivers R11 and R14 of spec 021.
- Spec 024 — `system-audit-log`.
- Spec 020 — `fixed-points-model`, whose constants the economy comparison uses.
- Spec 026 — `project-documentation`, which documents the deployment this account is created in.
