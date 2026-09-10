# Spec 002 — Camera QR scan

| | |
|---|---|
| **Status** | Implemented |
| **Branch** | `002-camera-qr-scan` |
| **Actors** | Participant |
| **Created** | 2026-09-10 |
| **Last updated** | 2026-09-10 |

## 1. Purpose

Scanning is the whole game. An attendee walks to a stand, points their phone at a screen, and
points appear. Everything else in the system exists to set that moment up or to spend what it
produces.

It has to work on a borrowed phone, in a hall with bad light, on a browser from 2020, in under a
couple of seconds, for three hundred people. And it has to be impossible to cheat: the codes are
projected on a screen anyone can photograph, and the prizes at the end are real.

This spec documents how that works today. It is behaviour that already ships and has already
survived a security audit; the intent is recorded so the reasoning is not lost when the rules
around it change.

## 2. Scope

**In scope**

- Opening the camera and reading a code from it.
- What the code carries and how it is verified.
- The rotation window that makes a photograph useless.
- What the attendee sees on success and on refusal.
- Falling back when the camera cannot be used.

**Out of scope**

- Typing a code by hand. Spec 003 — this spec only hands over to it.
- What a scan awards, and the cooldown and completion rules. Spec 020.
- Whether an activity is running. Spec 019.
- Producing and projecting the code. Spec 011.

## 3. User scenarios

### 3.1 A scan that works

**Given** an attendee at a stand with a code on screen
**When** they open the scanner and point the phone at it
**Then** within about a second they see how many points they were awarded, which stand awarded
them, and what it was for.

### 3.2 A photographed code

**Given** somebody who photographed a stand's code and left
**When** they scan the photograph a minute later
**Then** it is refused as expired. The code was replaced within fifteen seconds of being shown.

### 3.3 A code that was tampered with

**Given** somebody who has worked out the shape of the payload and written their own
**When** they present it
**Then** it is refused. The payload is signed, and they cannot produce the signature.

### 3.4 No camera

**Given** an attendee whose browser will not grant camera access, or is not on a secure connection
**When** they open the scanner
**Then** they are put straight into typing a code by hand, without an error they can do nothing
about.

### 3.5 Scanning again

**Given** an attendee who has just been awarded points
**When** they want to scan the next stand
**Then** one action returns them to a live camera.

## 4. Requirements

| ID | Requirement | Priority |
|---|---|---|
| R1 | The attendee MUST be able to scan a code with their device's camera, using the rear camera by default. | Must |
| R2 | Reading a code MUST NOT require the attendee to press anything: pointing the camera is the whole interaction. | Must |
| R3 | The camera MUST stop as soon as a code has been read, and MUST NOT read the same code repeatedly. | Must |
| R4 | Only one scan MUST be processed at a time. | Must |
| R5 | A code MUST be verifiable only by the system that issued it: the attendee's device MUST NOT be able to produce a valid one. | Must |
| R6 | A code MUST be accepted only within its rotation window, with one window of tolerance for network latency. | Must |
| R7 | Whether a scan is awarded MUST be decided entirely by the server. The device MUST NOT influence the outcome or the amount. | Must |
| R8 | On success the attendee MUST see how many points they were awarded, which stand, and whether it was a visit or an activity. | Must |
| R9 | On refusal the attendee MUST see why, in terms that tell them what to do next. | Must |
| R10 | The attendee MUST be able to start another scan in one action. | Must |
| R11 | If the camera cannot be started, for any reason, the attendee MUST be moved to entering a code by hand rather than shown a failure. | Must |
| R12 | The attendee MUST be able to choose to type a code instead, without the camera having to fail first. | Must |
| R13 | Leaving the scanner MUST release the camera. | Must |
| R14 | The scanner MUST NOT be reachable without a participant session. | Must |
| R15 | The scanner SHOULD work on the browser floor the project targets. | Should |

## 5. Business rules

| Rule | Value | Rationale |
|---|---|---|
| Rotation window | 15 seconds | Short enough that a photograph is worthless before it can be passed around a hall; long enough that someone fumbling with their phone in bad light still catches the code they are pointing at. |
| Backward tolerance | One window | A scan can be in flight when the code rotates. Without tolerance, attendees would lose points to their own latency and blame the stand. Extending it to two windows would double the life of a photograph for no benefit. |
| Forward tolerance | None | A code from a future window can only come from a clock that is wrong or a payload that was constructed. Neither should be awarded. |
| Signature | Over the stand, the window, the amount and the type | Everything that determines the award is signed together, so no field can be changed independently. |
| Where verification happens | The database | The client is public and the prizes are real. Anything the browser decides, an attendee can decide differently. |
| Camera | Rear-facing, continuous | It is the camera pointed at the screen. Continuous reading means the interaction is "point the phone", which is the only interaction that works while walking. |
| Camera failure | Falls through to manual | On a local network without HTTPS the camera is unavailable by browser policy, and some attendees simply refuse the permission. An error message would leave them with no way to play. |

## 6. Edge cases and failure modes

| Situation | Expected behaviour | Message shown |
|---|---|---|
| The code is from more than one window ago | Refused, nothing awarded | "Código QR caducado, escanee el código actual del stand." |
| The code is from a future window | Refused | as above |
| The signature does not match | Refused | "Código QR inválido o falsificado." |
| The code is not one of ours at all | Refused before anything is sent | "Código QR no reconocido" |
| The stand no longer exists | Refused | "Comunidad no encontrada" |
| The attendee has no profile | Refused, and told to register | "Regístrate para participar." |
| The camera permission is denied | Manual entry, immediately | none |
| The page is not on a secure connection | Manual entry, immediately | none |
| The device has no camera | Manual entry, immediately | none |
| The same code is read several times in one frame burst | One scan is processed | none |
| The network fails mid-scan | Nothing is awarded and it is safe to try again | a failure the attendee can retry |
| The attendee leaves the screen mid-scan | The camera is released; no scan is left half-processed | none |

## 7. Security and integrity

This is the surface an attacker actually reaches: the codes are projected in public and the
attacker owns the device doing the scanning.

- **The device is untrusted, entirely (R5, R7).** It reads a code, decodes it, and sends it. It
  does not decide whether it is valid, who is scanning, or what it is worth. Every one of those
  was at some point decided client-side, and each was an audit finding.
- **The secret never reaches the browser (constitution V).** Codes are signed in the database. The
  client only unwraps what a stand's screen displayed. This is audit finding F3 and it is the
  single most important property on this page.
- **Rotation is the anti-sharing mechanism, and it is the only one.** Nothing stops an attendee
  photographing a screen; the fifteen-second window is what stops the photograph being worth
  anything. Any change that lengthens it, caches a code, or accepts an older window weakens the
  entire scheme.
- **The signature binds the fields together (R5).** Stand, window, amount and type are signed as
  one string, so a payload cannot be assembled from parts of two valid codes.
- **The amount is re-derived, never accepted.** Even a correctly signed payload has its amount
  clamped to what the rules allow before anything is written (spec 020, R10).
- **The scanner is not an authorisation surface (R14).** The route check is a convenience; the
  award refuses an attendee with no profile regardless of how the request arrived.

## 8. Acceptance criteria

- [ ] Pointing the rear camera at a valid code awards points with no further interaction.
- [ ] The result names the points awarded, the stand and whether it was a visit or an activity.
- [ ] The camera stops once a code is read and does not award twice from one reading.
- [ ] A code more than one window old is refused as expired.
- [ ] A code from a future window is refused.
- [ ] A payload with an altered amount, stand, type or window is refused.
- [ ] Text that is not one of our codes is refused without reaching the server.
- [ ] Denying camera permission moves the attendee to manual entry rather than an error.
- [ ] Being on an insecure connection moves the attendee to manual entry.
- [ ] The attendee can choose manual entry without the camera failing first.
- [ ] One action returns to a live camera after a scan.
- [ ] Leaving the screen releases the camera.
- [ ] The scanner cannot be used without a participant session.

## 9. Open questions

None.

## 10. As-built notes

| Requirement | Implemented in |
|---|---|
| R1, R2, R3 | `src/pages/Scanner.jsx:25-64` — `html5-qrcode`, `facingMode: environment`, 10 frames per second, a 250-pixel target box; the reader is stopped inside the success callback. |
| R4 | `src/pages/Scanner.jsx:65` — a processing flag rejects re-entry. |
| R5, R6, R7 | `supabase/postgres-init/50_rpc.sql`, `validate_and_scan` — window arithmetic on `epoch / 15`, `(v_current_ts - v_qr_ts) > 1 OR (v_qr_ts > v_current_ts)`, and an HMAC-SHA256 comparison against the secret in `settings`. |
| R8, R9 | `src/pages/Scanner.jsx` result screen, from the fields the function returns. |
| R10 | The "Escanear otro" action, which resets the scanning state. |
| R11 | `src/pages/Scanner.jsx:50-53` — any camera start failure switches to manual entry. |
| R12 | A manual-entry control on the scanner screen. |
| R13 | The effect cleanup stops the reader. |
| R14 | `src/pages/Scanner.jsx:20-22`, plus `RequireAuth` in `src/App.jsx` and, decisively, the function's own `auth.uid()` lookup. |
| R15 | `vite.config.js` targets `chrome83`; `html5-qrcode` works within it. |

**Known deviations**

- The refusal messages carry emoji, which spec 016 removes.
- The payload's decoding uses a length heuristic to tell a manual code from a full payload
  (`data.trim().length <= 8`), which belongs to spec 003 and is documented there.

## 11. References

- Constitution: III (rules in the database), V (secrets never reach the client).
- ADR 0004 — business rules in Postgres, and audit finding F3.
- ADR 0005 — the Chromium 83 floor R15 refers to.
- Glossary: *Scan*, *Signed payload*, *Rotation window*.
- Spec 003 — `manual-code-fallback`, which R11 and R12 hand over to.
- Spec 011 — `qr-projection`, which produces what this reads.
- Spec 019 — `stand-activity-catalogue` and spec 020 — `fixed-points-model`, which change what the
  payload identifies and what it is worth, without changing this mechanism.
