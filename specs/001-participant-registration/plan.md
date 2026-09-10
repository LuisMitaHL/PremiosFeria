# Plan 001 — Participant registration

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Rules in the database | Yes | Uniqueness, the limits and the recovery decision are all SQL. The form's checks become courtesy messages. |
| IV — Identity is never a parameter | Yes, with one deliberate exception | Registration is where identity is *established*, so it necessarily accepts a nickname and a device. Both are used once, to decide which profile the session belongs to, and never afterwards. |
| VI — Structural guarantees | Yes | Uniqueness is a unique index on the folded nickname, not a check-then-insert: two attendees choosing the same free nickname in the same instant must not both succeed. |
| IX — Quality gates | Yes | New SQL suite. |

## 2. Approach

Registration becomes a single RPC, `register_or_recover(nickname, fingerprint)`, which decides
between three outcomes:

| Nickname | Device | Outcome |
|---|---|---|
| free | — | new profile, zero points |
| taken | matches | that profile is returned and re-attached to this session |
| taken | differs | refused |

Doing it in one function is what makes it atomic. Split across a lookup and an insert, two people
registering the same nickname at once both see it free.

**Uniqueness is a functional unique index** on `lower(btrim(name))`, so `Zorro`, `zorro` and
` zorro ` collide without a second column to keep in step.

The client still signs in anonymously first — the session has to exist before the row can be
attached to it — and the RPC then binds `auth_user_id`. Recovery re-binds it, which is the one
place an existing row's identity changes, so it lives in this function and nowhere else.

## 3. Database changes

| File | Change |
|---|---|
| `20_schema.sql` | `participants.name` gains `CHECK (char_length(btrim(name)) BETWEEN 2 AND 24)`; unique index on `lower(btrim(name))` |
| `57_registration.sql` (new) | `register_or_recover(p_name, p_fingerprint)` |
| `40_rls.sql` | The `participants_insert` policy is dropped: registration goes through the RPC, so there is no client insert path left |

## 4. Frontend

| File | Change |
|---|---|
| `src/lib/api.js` | `registerParticipant` calls the RPC and returns its verdict rather than inserting |
| `src/pages/Register.jsx` | The refusal message; a 24-character limit; the warning that an offensive nickname forfeits prizes (R11); the label stops asking for a full name (R16) |

R10b — pointing at the organiser's stand — is **deferred to spec 022**, which is what makes that
sentence true.

## 5. Test strategy

`tests/sql/14_registration.sql`: the three outcomes; case and whitespace folding; the length limits
including through a direct insert; two simultaneous registrations of one free nickname producing
one profile; recovery preserving points, scans and claims and creating no second profile; recovery
detaching the previous device; a refusal leaving the existing profile untouched.

## 6. Risks

- **Recovery re-binds a session to an existing profile.** That is an account takeover performed on
  purpose, and the device match is the only thing standing in front of it. The fingerprint is weak
  by nature; it is acceptable only because it *narrows* — it can return a profile to the device
  that made it and can never grant access from anywhere else.
- Existing rows may hold duplicate or over-length nicknames. Schema changes require a fresh
  deployment regardless.

## 7. Out of scope

Cross-device recovery, renaming, and everything else at the organiser's desk: spec 022.
