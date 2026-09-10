# Spec 001 — Participant registration

| | |
|---|---|
| **Status** | Draft |
| **Branch** | `001-participant-registration` |
| **Actors** | Participant, Event operator |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

An attendee arrives at the fair, opens the app on their own phone, and needs to be earning points
within seconds. Registration is the first thing they meet and the only thing standing between
them and the game, so it asks for as little as possible: a nickname, and nothing else.

That nickname is also their only way back. If they close the browser, run out of battery, or open
the app again later in the day, typing the same nickname on the same device returns them to the
profile they already have, with their points intact. This is what makes a name-only registration
survive an afternoon.

## 2. Scope

**In scope**

- Creating a participant profile from a nickname alone.
- Returning to an existing profile from the same device.
- Refusing a nickname that already belongs to someone else.
- The limits that keep a nickname displayable on a projected leaderboard.
- Telling the attendee, at the moment they choose a nickname, what an offensive one costs them.

**Out of scope**

- Recovering a profile from a **different** device. That is the escape valve for a device whose
  identity changed, and it belongs to the event operator — see spec 017.
- Renaming or removing a participant during the event. Also spec 017.
- Automatic detection of offensive nicknames. Deliberately excluded: see R12 and section 5.
- Logging out or switching profile on purpose. No requirement exists for it today.

## 3. User scenarios

### 3.1 A new attendee registers

**Given** an attendee opens the app for the first time on their phone
**When** they enter a nickname nobody is using and confirm
**Then** a profile is created with zero points, they are taken straight to their dashboard, and
they can scan immediately.

### 3.2 An attendee returns on the same device

**Given** an attendee registered earlier today and has since closed the app or cleared the page
**When** they open the app and enter the same nickname on the same device
**Then** they are returned to their existing profile, with the points, scans and claims they had
already accumulated. Nothing is reset and no second profile is created.

### 3.3 An attendee picks a nickname somebody else is already using

**Given** another attendee has already registered as `zorro`
**When** a different attendee enters `zorro`
**Then** they are told the nickname is taken and asked to choose another. No profile is created,
and the existing `zorro` is not disturbed in any way.

### 3.4 An attendee's device is no longer recognised

**Given** an attendee registered as `zorro` earlier, and their device identity has since changed
(a browser update, a private window, a different phone)
**When** they enter `zorro` again
**Then** the system cannot tell them apart from scenario 3.3 and refuses the nickname. They are
told the nickname is taken and asked to choose another.

Until spec 017 ships there is **no way out of this state**: the attendee starts again under a
different nickname and loses the points they had. This is a known, accepted cost of shipping 001
first — the message deliberately does not promise help that does not exist yet. When 017 lands,
R10b adds the sentence pointing at the organiser's stand.

### 3.5 An attendee is warned about offensive nicknames

**Given** an attendee is choosing a nickname
**When** they are on the registration screen
**Then** they can see, before submitting, that a nickname judged offensive means they will not be
able to claim prizes.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | Registration MUST require exactly one field from the attendee: a nickname. | Must |
| R2 | A nickname MUST be at least 2 characters after leading and trailing whitespace is removed. | Must |
| R3 | A nickname MUST be at most 24 characters after trimming. | Must |
| R4 | The length limits MUST be enforced where the data is stored, not only in the form, so a caller bypassing the interface cannot exceed them. | Must |
| R5 | A nickname MUST identify exactly one participant for the whole event. | Must |
| R6 | Nickname matching MUST be case-insensitive and MUST ignore surrounding whitespace, so `Zorro`, `zorro` and ` zorro ` are the same nickname. | Must |
| R7 | When the nickname is not in use, the system MUST create a new profile with zero points and begin a session for it. | Must |
| R8 | When the nickname is in use **and the request comes from the device that profile was registered on**, the system MUST return the attendee to that existing profile with all of its accumulated state, and MUST NOT create a second profile. | Must |
| R9 | When the nickname is in use **and the request does not come from that device**, the system MUST refuse it, MUST NOT create a profile, and MUST NOT alter the existing one. | Must |
| R10 | The refusal in R9 MUST tell the attendee that the nickname is already taken and ask them to choose another. | Must |
| R10b | Once spec 017 ships, the refusal MUST additionally tell the attendee that a profile can be restored at the organiser's stand. **Deferred: not implemented with this spec.** | Must (deferred) |
| R11 | The registration screen MUST state, before submission, that an offensive nickname forfeits the ability to claim prizes. | Must |
| R12 | The system MUST NOT automatically reject a nickname for its content. | Must |
| R13 | A participant MUST begin with a balance of zero. | Must |
| R14 | The device identity used for R8 MUST NOT be usable on its own to act as a participant: it identifies a device, it does not authenticate one. | Must |
| R15 | Registration SHOULD complete in a single screen with a single action, with no confirmation step. | Should |
| R16 | The field SHOULD present itself as a chosen nickname rather than as a legal name, since a real name that is already taken will be refused. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Minimum nickname length | 2 characters | Rules out an empty or single-character entry while staying out of the way. Unchanged from the behaviour that already ships. |
| Maximum nickname length | 24 characters | The leaderboard and the podium are projected on a screen during the event. 24 characters is what fits a row without wrapping. Without a limit, one attendee can deform the screen everyone is watching. |
| Nickname uniqueness | Event-wide, case-insensitive | The nickname is the recovery key. If two people could hold the same one, returning to "your" profile would be ambiguous, and the cost of that ambiguity is somebody else's points. |
| Device match for recovery | Must match the device recorded at registration | Without it, anyone could type a nickname and take over that profile. The device is the second factor that makes a name-only login safe enough for a one-day event. |
| Recovery across devices | Not automatic; operator only | An attendee who genuinely lost their device cannot be told apart from someone impersonating them. A person at the organiser's stand can tell the difference; software cannot. |
| Offensive nicknames | Warned, not filtered | A blocklist would need maintaining and would misfire on Bolivian slang and surnames, refusing real attendees at the door. Judgement stays with the organiser, who acts once on the rare case, instead of the system guessing on every registration. |
| Starting balance | 0 points | Everyone starts level. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown to the attendee |
|---|---|---|
| Empty nickname | Refused, no profile created | "Ingresa tu nombre" |
| One character | Refused | "El nombre debe tener al menos 2 caracteres" |
| More than 24 characters | Refused, or prevented at the input | "El nombre no puede tener más de 24 caracteres" |
| Whitespace only | Refused as empty | "Ingresa tu nombre" |
| Same nickname, same device | Existing profile restored, silently and immediately | none — they land on their dashboard |
| Same nickname, different device | Refused, existing profile untouched | "Ese nombre ya está en uso, elige otro." (R10b extends this once 017 ships) |
| Same nickname differing only in case or spacing | Treated as the same nickname | as above, per device match |
| Two attendees submit the same free nickname at the same instant | Exactly one profile is created; the loser is refused as in R9 | as above |
| The device identity cannot be determined | The attendee can still register; recovery on that device is simply unavailable | none |
| The network drops mid-registration | No partial profile is left behind; retrying is safe and does not create a duplicate | "No se pudo completar el registro. Intenta de nuevo." |
| An attendee already has a session on this device | They go straight to their dashboard without seeing the registration screen | none |

## 7. Security and integrity

This feature creates the identity every point in the system is later attached to, so its failure
modes are the point economy's failure modes.

- **Identity is issued, not asserted (constitution IV).** Registration produces a session, and
  every later action resolves the acting participant from that session. The nickname and the
  device identity are used *once*, to decide which profile the session belongs to. Neither may
  ever be accepted afterwards as a claim of who is calling (R14).
- **The device identity is not a credential (R14).** It is a weak, forgeable signal. It is
  acceptable here because it only ever *narrows* access: it can restore a profile to the device
  that created it, and it can never grant access from anywhere else. Anything stronger, and the
  cross-device case would have to be solved in software rather than by a person at a stand.
- **Uniqueness must be structural (constitution VI).** A check performed before the write is not
  the gate: two attendees choosing the same free nickname in the same instant must not both
  succeed. The guarantee has to be a constraint in the database, with the pre-check reduced to
  writing a friendly message.
- **Recovery must not become an account takeover.** The only path that returns an existing profile
  is nickname *and* device together. Refusing on a device mismatch (R9) is the security boundary,
  and it is deliberately preferred over the friendlier alternative of creating a duplicate.
- **Public exposure.** Participant rows are world-readable so the leaderboard can be public. Any
  device identity stored on a participant is therefore readable by anyone holding the anon key. It
  must not be a value that says anything about the person or that is reusable elsewhere.
- **Enumeration.** The refusal in R9 confirms a nickname exists. Accepted: the leaderboard already
  publishes every nickname, so there is nothing to conceal.

## 8. Acceptance criteria

- [ ] A new attendee can register with a nickname alone and reach the dashboard in one action.
- [ ] A new profile starts at zero points.
- [ ] Closing the app and re-entering the same nickname on the same device restores the same
      profile, with its points, scans and claims unchanged.
- [ ] Restoring a profile does not create a second one; the participant count does not rise.
- [ ] Entering a nickname held by someone on another device is refused, and the attendee is asked
      to choose another nickname.
- [ ] The refusal does **not** mention the organiser's stand, which cannot help until 017 ships.
- [ ] A refused registration leaves the existing profile's points, scans and claims untouched.
- [ ] `Zorro`, `zorro` and ` zorro ` are treated as one nickname.
- [ ] A 25-character nickname is refused; a 24-character one is accepted.
- [ ] A 25-character nickname is still refused when submitted directly to the API, bypassing the
      form.
- [ ] Two simultaneous registrations of the same free nickname produce exactly one profile.
- [ ] The warning about offensive nicknames is visible before submitting.
- [ ] No nickname is ever refused for its content.

## 9. Open questions

None. The three conflicts raised during the interview — repeated names against nickname-based
recovery, an automatic filter against an advisory warning, and the absence of a length limit —
were resolved in favour of uniqueness, a warning only, and a 24-character cap.

## 10. Current behaviour and the gap

This began as a retro-spec and became a change: only part of what is written above ships today.

| Requirement | Today |
|---|---|
| R1, R2, R13, R15 | Already met. `src/pages/Register.jsx:22-29` validates a single trimmed name of at least 2 characters and navigates straight to the dashboard; `points` defaults to 0. |
| R3, R4 | **Missing.** No maximum anywhere, in the form or in the schema. |
| R5, R6 | **Missing.** Nicknames are free-form and may repeat; nothing compares them. |
| R7 | Partially met. A profile is always created — `src/lib/api.js:12-33` signs out, opens an anonymous session and inserts the row — but *unconditionally*, with no check for an existing nickname. |
| R8, R9, R10 | **Missing.** There is no recovery path at all. A device that loses `localStorage` loses the profile permanently, and re-registering produces a second profile with the same name and zero points. |
| R10b | **Deferred to spec 017.** |
| R11, R12 | R12 is met by omission — no filter exists. R11 is **missing**: the screen currently reassures the attendee that "tu información se guarda de forma segura en la nube", which is close to the opposite of the warning R11 asks for. |
| R14 | Met in spirit. A device fingerprint is collected at `src/lib/AuthContext.jsx:74` and stored on the participant, but **nothing reads it** — it affects no decision today. This spec is what gives it a purpose. |
| R16 | **Missing.** The field is labelled "Nombre completo *" and shows "Ej: María García", inviting exactly the real names R5 will now refuse. |

**Consequences the plan must address**

- Uniqueness and the length cap are schema changes. The initialisation scripts run once, on an
  empty volume, so neither can be applied to a fair already in progress.
- Recovery cannot be a client-side lookup. Deciding whether a nickname belongs to this device, and
  re-attaching a session to an existing profile, is a rule and therefore belongs in the database
  (constitution III), reached through a function rather than through table access.
- Existing rows may already hold duplicate or over-length nicknames.

## 10c. As built

`register_or_recover` in `supabase/postgres-init/57_registration.sql` decides all three outcomes in
one step: a free nickname creates a profile, the same nickname on the same device returns it, and
somebody else's is refused. One function because it has to be atomic — split across a lookup and an
insert, two people choosing the same free nickname would both see it free.

Uniqueness is a functional unique index on `lower(btrim(name))`, so `Zorro`, `zorro` and ` zorro `
collide without a second column to keep in step. The client's `INSERT` policy on `participants` is
gone: there is no path left that skips the uniqueness or the device check.

**Verified in the browser**, all three: registered as `zorro`, cleared the session and returned by
typing `ZORRO` — the profile came back with its 85 points — then changed the stored device identity
and was refused with "Ese nombre ya está en uso, elige otro."

**R10b is still deferred.** The refusal deliberately does not mention the organiser's stand, because
until spec 022 nobody there can help.

## 11. References

- Constitution: III (rules in the database), IV (identity is never a parameter), VI (structural
  guarantees); `AGENTS.md` section 8.
- Glossary: *Participant*, *Points*.
- Spec 017 — `event-organizer-role`, which owns cross-device recovery, renaming and removal.
  **001 ships without referring to it** (R10b is deferred), so until 017 lands an attendee whose
  device identity changed has no recovery path at all.
- Spec 007 — `live-leaderboard`, which is why the 24-character cap has the value it has.
