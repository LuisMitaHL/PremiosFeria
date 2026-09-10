# Spec 010 — Stand login

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `010-stand-login` |
| **Actors** | Stand admin |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

A stand is run by whoever is standing behind it, on whatever device they brought, with credentials
handed to them on a slip of paper before the fair. They sign in once, in a noisy hall, and stay
signed in for the day. There is no email to send a reset to and no support desk to call.

That shapes everything about this: the login name is a word, not an address; the password is typed
once and then forgotten; the session lasts longer than the event. And because signing in as a
stand means being able to award points, the small surface it presents has to hold up against
somebody with a phone and an afternoon.

This documents behaviour that already ships, recorded so its reasoning survives the changes around
it. Spec 023 takes over how these credentials come into existence; the sign-in itself is unchanged.

## 2. Scope

**In scope**

- Signing in as a stand with a login name and a password.
- How the password is verified and where.
- The session that results, and how long it lasts.
- The protections against guessing and against learning which stands exist.

**Out of scope**

- Creating a stand and issuing its credentials, resetting a password, and withdrawing a stand.
  Spec 023 owns all of that.
- What a stand can do once signed in. Specs 019, 021 and 018.
- The organiser's sign-in, which is separate and must stay separate. Spec 017.
- The attendee's session, which has no password at all. Spec 001.

## 3. User scenarios

### 3.1 A stand signs in

**Given** a stand admin holding the slip they were given
**When** they enter their login name and password
**Then** they reach their console and stay signed in for the rest of the fair.

### 3.2 A password typed wrong

**Given** a stand admin mistyping in a hurry
**When** they submit
**Then** they are told the credentials are wrong, without being told which half.

### 3.3 Somebody guessing

**Given** someone trying passwords against a login name they saw
**When** they have tried a number of times in a few minutes
**Then** they are refused for a while regardless of what they type.

### 3.4 Somebody fishing for stand names

**Given** someone trying login names to see which exist
**When** they submit any of them
**Then** every response is identical. Nothing distinguishes a real stand from an invented one.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | A stand MUST sign in with a login name and a password. The login name MUST NOT be required to be an email address. | Must |
| R2 | The login name MUST be matched without regard to case or surrounding whitespace. | Must |
| R3 | The password MUST be matched exactly, including case. | Must |
| R4 | The password MUST be verified against a stored hash, never against a stored password. | Must |
| R5 | The hash MUST NOT leave the database, and MUST NOT be returned by anything. | Must |
| R6 | Verification MUST happen in the database, not in the service that receives the request. | Must |
| R7 | A wrong password and an unknown login name MUST produce identical responses, in content and in shape. | Must |
| R8 | A stand with no password set MUST NOT be able to sign in, whatever is submitted, including an empty password. | Must |
| R9 | Repeated failures MUST be refused for a period, counted against both the origin of the requests and the login name. | Must |
| R10 | The comparison of secrets MUST NOT reveal anything through how long it takes. | Must |
| R11 | A successful sign-in MUST produce a session that identifies the stand, and that identity MUST be what every later rule resolves. | Must |
| R12 | The session MUST last long enough to cover a fair without signing in again. | Must |
| R13 | A session MUST be renewable without the password being entered again. | Must |
| R14 | The response to a successful sign-in MUST NOT contain the password or its hash. | Must |
| R15 | Nothing in the sign-in path MUST reveal how many stands exist or what they are called. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Login name | A word, not an email | Handed over on paper and typed on a phone in a hall. An email address would be longer, easier to mistype, and a fiction — these accounts have no mailbox behind them. |
| Case and whitespace on the name | Ignored | It is read off a slip and typed by hand. `MEH`, `meh` and ` meh ` are the same stand, and refusing one of them is refusing a correct answer. |
| Case on the password | Significant | It is a secret, not a name. Folding case would throw away part of it. |
| Where verification happens | Inside the database | The hash never has to travel, and the service that fronts the request never has to be trusted with it. |
| Failure response | Identical for every reason | Distinguishing "no such stand" from "wrong password" tells an attacker which half to keep working on, and publishes the list of stands. |
| Attempt limit | Counted per origin **and** per login name | Per origin alone lets an attacker spread attempts across addresses. Per name alone lets one origin work through every stand. Both together close each other's gap. |
| Session length | Longer than an event | A stand signing in again halfway through the afternoon, on a phone with a slip they may have lost, is a failure mode worth avoiding more than the exposure of a long session on a device they are holding. |
| Password recovery | None | There is no address to send anything to. Recovery is a person at the organiser's desk issuing a new one (spec 023). |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| Wrong password | Refused | "Credenciales incorrectas." |
| Unknown login name | Refused, identically | as above |
| Login name in a different case | Accepted | none |
| Login name with surrounding spaces | Accepted | none |
| Password in a different case | Refused | as the first row |
| A stand with no password set | Refused, including for an empty password | as the first row |
| An empty login name or password | Refused before anything is checked | as the first row |
| Too many failures in a short period | Refused for a period, regardless of what is submitted | "Demasiados intentos. Espera unos minutos." |
| The database is unreachable | Refused as a failure, distinguishably from wrong credentials | a service failure, not "credenciales incorrectas" |
| A session expires mid-event | Signing in again restores everything; nothing about the stand is lost | none |
| An attendee's session is presented to a stand's screen | The screen may render, but nothing a stand can do will work | refusals from the rules themselves |

## 7. Security and integrity

Signing in as a stand is the ability to award points, so this is a real target.

- **The hash never leaves the database (R4, R5, R6).** The service that receives the request passes
  the submitted password to a database function and gets back an identity or nothing. It never
  reads a hash, so a compromise of that service does not yield one.
- **Every failure looks the same (R7, R15).** Content, shape and — as far as is practical — timing.
  A response that differs by reason is a directory of the fair's stands and a hint about which
  attack to continue.
- **Both limits, together (R9).** Counting only per origin invites spreading the attempts;
  counting only per name invites working through every stand from one place.
- **A null hash matches nothing (R8).** A stand created but not yet given a password must be
  closed, not open. This depends on comparison against an absent hash yielding no match rather
  than a match — an easy thing to get backwards.
- **The session is the identity, and only the identity (R11).** Everything a stand can afterwards
  do resolves the stand from the session, in the database. The token carries which stand it is;
  it does not carry what that stand is allowed to do, and no rule reads a role name from it.
- **A long session is a deliberate trade (R12).** It is held on a device the stand is holding, and
  the alternative — a stand locked out mid-fair with no way back — is the worse failure. It is
  paired with the organiser's ability to withdraw a stand (spec 023) as the way to end one early.

## 8. Acceptance criteria

- [ ] A stand signs in with a login name and password and reaches its console.
- [ ] The login name is accepted in any case and with surrounding whitespace.
- [ ] A password in the wrong case is refused.
- [ ] A wrong password and an unknown login name produce identical responses.
- [ ] A stand with no password set cannot sign in, including with an empty password.
- [ ] Repeated failures are refused for a period, counted per origin and per login name.
- [ ] No response ever contains a password or a hash.
- [ ] A successful sign-in produces a session that later rules resolve the stand from.
- [ ] The session outlasts a full event and can be renewed without the password.
- [ ] Nothing in the sign-in path reveals which stands exist.

## 9. Open questions

None.

## 10. As-built notes

| Requirement | Implemented in |
|---|---|
| R1, R11 | `src/pages/admin/AdminLogin.jsx` and `src/lib/api.js:172-201`. The client calls the password grant with the login name in the field the library calls `email`; the service does not require it to be one. |
| R2, R3, R4, R6 | `supabase/postgres-init/51_stand_login.sql` — `lower(btrim(...))` on the name, `crypt(p_password, c.password_hash)` on the password, inside a `SECURITY DEFINER` function. |
| R5, R14 | The same function returns only `id`, `username` and `name`. |
| R7, R15 | `auth/server.mjs:170-171` — a single `invalid_credentials` response for every failure. |
| R8 | Falls out of SQL: comparing against a `NULL` hash yields `NULL`, which matches no row. Documented in `26_password_hash.sql`. |
| R9 | `auth/server.mjs` — a sliding window of 20 attempts per 5 minutes, keyed on origin and lowercased login name together. |
| R10 | `auth/server.mjs` — `crypto.timingSafeEqual`. |
| R12, R13 | `docker-compose.yml` — a 12-hour access token and a 48-hour refresh token, HS256. |

**Known deviations**

- The stand's identity travels as `user_metadata.community_id`, with a fallback that looks the
  stand up by its identifier. That fallback works only because the seed sets a stand's identity
  equal to its own identifier; if that ever stops being true, sign-in resolves nothing.
- The client labels the field `email`, because that is what the library's password grant calls it.
  Nothing requires or validates an address, but the naming misleads a reader.
- The token issuer is a legacy name, which spec 016 addresses.
- Spec 023 adds a withdrawn state; once it lands, a withdrawn stand must be refused here too.

## 11. References

- Constitution: IV (identity is never a parameter), V (secrets never reach the client).
- ADR 0002 — why this is a small auth service rather than GoTrue.
- Glossary: *Stand*, *Stand admin*.
- Spec 023 — `organizer-community-management`, which creates these credentials, resets them, and
  adds the withdrawn state this path will have to honour.
- Spec 017 — `organizer-admin-panel`, whose sign-in is separate and must remain so.
- Spec 016 — `naming-and-hygiene-cleanup`, for the issuer name.
