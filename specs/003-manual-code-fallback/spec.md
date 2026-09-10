# Spec 003 — Manual code fallback

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `003-manual-code-fallback` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

A meaningful number of attendees cannot use their camera. Some deny the permission. Some are on
old browsers. And on a local network without a certificate, the browser refuses camera access
outright — which is exactly the situation during setup and testing, and a real risk if the event
runs without a certificate on the day.

Without a way in, those people cannot play at all. So every code a stand projects also appears as
six characters underneath it, and an attendee can type them. It is the same code, verified the
same way, worth the same points: the only thing that changes is how it got from the screen to the
server.

## 2. Scope

**In scope**

- Typing a code instead of scanning one.
- What the short code is, and how the server works out which code was meant.
- Its limits, and the risks that come with them.
- When an attendee ends up here rather than at the camera.

**Out of scope**

- Reading a code with the camera. Spec 002.
- Displaying the short code on the projected screen. Spec 011.
- What a scan awards. Spec 020.
- The attendee's own claim code, which is a different thing with a different purpose. Spec 018.

## 3. User scenarios

### 3.1 An attendee without a camera

**Given** an attendee whose browser will not open the camera
**When** they open the scanner
**Then** they are already on the manual entry, and can type the six characters shown under the
code on the stand's screen.

### 3.2 An attendee who prefers to type

**Given** an attendee in a crowd who cannot get a clear line to the screen
**When** they choose manual entry
**Then** they can type the code without the camera having to fail first.

### 3.3 A code typed too late

**Given** an attendee typing slowly
**When** they submit a code from two windows ago
**Then** it is refused as expired, exactly as a photographed code would be, and they can read the
current one and try again.

### 3.4 A code typed in lower case

**Given** an attendee typing what they see
**When** they enter the characters in any case
**Then** it is accepted. The case they type is not part of the code.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | An attendee MUST be able to enter a code by typing it instead of scanning it. | Must |
| R2 | The short code MUST be short enough to read across a room and type on a phone. | Must |
| R3 | The short code MUST be derived from the same signature the camera path verifies, so both paths accept and refuse identically. | Must |
| R4 | A typed code MUST be accepted regardless of the case it is entered in, and regardless of surrounding whitespace. | Must |
| R5 | A typed code MUST be subject to the same rotation window and the same one-window tolerance as a scanned one. | Must |
| R6 | A typed code MUST award exactly what the equivalent scan would award. | Must |
| R7 | The system MUST determine which stand and which kind of code a typed code refers to, without the attendee stating either. | Must |
| R8 | A typed code that matches nothing MUST be refused with a message that distinguishes "wrong or expired" from any other failure. | Must |
| R9 | Manual entry MUST be reachable deliberately, not only after the camera fails. | Must |
| R10 | The attendee MUST be moved here automatically when the camera cannot be started. | Must |
| R11 | Nothing about this path MUST be easier to abuse than the camera path. | Must |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Short code length | 6 characters | The first six of the signature. Long enough that a wrong guess is very unlikely to land on a valid code within its fifteen-second life; short enough to read off a projector and type without a mistake. |
| Short code source | The head of the same signature | Not a second secret and not a second scheme. Whatever makes the full code valid makes these six characters valid, which is why the two paths cannot drift apart. |
| Case and whitespace | Ignored | It is typed by a person reading a screen. Rejecting `a1b2c3` because the screen showed `A1B2C3` would be refusing a correct answer. |
| Which stand it belongs to | Worked out by the server | Asking the attendee to pick a stand first would double the typing and let them pick the wrong one. The server has every stand's signature for the current window and can simply look. |
| Window | The same as a scanned code | Anything longer would make the typed path the weak one, and an attacker would use it. |
| Existence of this path | Required | Without it, an attendee on a device that will not open a camera cannot participate at all. That is a worse outcome than the risks below. |

### Accepted risks

Consequences of the design, recorded rather than solved. They are acceptable at the reference
scale of ten stands and three hundred attendees, and should be revisited before a larger event.

| Risk | Detail |
|---|---|
| Cost per attempt | Working out which code was meant recomputes a signature for every stand, for both kinds of code, across two windows. At ten stands that is forty computations per attempt, and it grows linearly with the number of stands. |
| No limit on attempts | Nothing throttles this path specifically; the rate limiting that protects sign-in does not cover it. With six characters and a fifteen-second window, guessing is impractical — but impractical rather than prevented. |
| Collision | Two stands could in principle produce the same six leading characters in the same window, crediting an attendee to the wrong stand. Vanishingly unlikely at ten stands; not impossible. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| The code matches nothing in either window | Refused | "Código manual inválido o caducado." |
| The code is from two windows ago | Refused as above; it no longer matches | as above |
| The code is typed in lower case | Accepted | none |
| The code is typed with surrounding spaces | Accepted | none |
| Fewer or more than six characters | Refused as not matching | as above |
| The attendee has no profile | Refused, and told to register | "Regístrate para participar." |
| The code is correct but the cooldown has not elapsed | Refused for that reason, not as an invalid code | the cooldown message (spec 020) |
| The code is correct but the activity is not running | Refused for that reason | the activity message (spec 019) |
| Something longer than a short code is pasted in | Treated as a full payload, not as a short code | as spec 002 |

## 7. Security and integrity

This path is deliberately equivalent to the camera path, and its risks come from the one place
they differ: the server has to work out what was meant.

- **Same signature, same window, same rules (R3, R5, R6).** There is no second verification path
  and no second secret. A change to how codes are signed changes both paths at once, which is what
  keeps them from drifting.
- **The search must not become a way in (R11).** It compares a typed string against signatures the
  server computes for itself. It never uses the typed value to look anything up, so there is
  nothing to inject, and a near-miss reveals nothing.
- **The cost is on the server, per attempt, and unthrottled.** Recorded above as an accepted risk.
  If the number of stands grows, or the event becomes a target, this is the first thing to protect.
- **Six characters is a probability argument, not a proof.** It rests on the fifteen-second window:
  a guess is worth something only for the window it was made in. Lengthening that window would
  weaken this far more than it would help anyone scan.
- **The two codes in the system must not be confused.** This one belongs to a stand's screen and
  identifies a code. The claim code in spec 018 belongs to an attendee and identifies a person.
  Neither path may accept the other's code.

## 8. Acceptance criteria

- [ ] An attendee can type a six-character code and be awarded exactly what scanning it would have
      awarded.
- [ ] The same code typed in lower case, upper case, or with surrounding spaces is accepted.
- [ ] A code from the previous window is accepted; one from two windows ago is refused.
- [ ] A code matching no stand is refused as invalid or expired.
- [ ] The attendee never has to say which stand or which kind of code they are entering.
- [ ] Manual entry is reachable deliberately, not only after the camera fails.
- [ ] A camera that cannot start puts the attendee here automatically.
- [ ] A correct code that fails a rule — cooldown, activity not running, already completed — is
      refused for that reason and not as an invalid code.
- [ ] A claim code from spec 018 is not accepted here.

## 9. Open questions

None. Three risks are accepted and recorded in section 5 rather than left open.

## 10. As-built notes

| Requirement | Implemented in |
|---|---|
| R1, R9, R10 | `src/pages/Scanner.jsx:66-96` — the manual form, reachable by choice and entered automatically when the camera fails. |
| R2, R3 | `supabase/postgres-init/50_rpc.sql`, `sign_scan_code` — `upper(substring(v_tok from 1 for 6))`, the head of the same HMAC the full payload carries. |
| R4 | `src/pages/Scanner.jsx:73` uppercases and trims; `validate_and_scan` uppercases again on receipt. |
| R5, R6, R7 | `supabase/postgres-init/50_rpc.sql:103-145` — a loop over every community, over both kinds, over the current and previous window, recomputing the signature and comparing its first six characters. |
| R8 | The same function: "Código manual inválido o caducado." |
| R11 | Both paths converge on the same cooldown, completion and clamping logic further down the same function. |

**Known deviations**

- The refusal messages carry emoji, which spec 016 removes.
- Whether an input is a short code or a full payload is decided by length
  (`data.trim().length <= 8`, `src/pages/Scanner.jsx:72`). It works because the two formats differ
  by an order of magnitude, but it is a heuristic rather than a distinction.
- The search is `O(stands × 2 × 2)` per attempt with no rate limit of its own. Recorded as an
  accepted risk, not a defect.

## 11. References

- Constitution: III (rules in the database), V (secrets never reach the client), VI (defence in
  depth).
- ADR 0004 — business rules in Postgres.
- Glossary: *Short code*, *Rotation window*, *Signed payload*.
- Spec 002 — `camera-qr-scan`, the path this backs up.
- Spec 011 — `qr-projection`, which displays the short code.
- Spec 018 — `in-person-reward-fulfilment`, whose claim code must never be confused with this one.
- Specs 019 and 020 — the rules a correct code is still subject to.
