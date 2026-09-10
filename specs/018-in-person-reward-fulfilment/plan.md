# Plan 018 — In-person reward fulfilment

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Depends on** | Spec 021 (rewards a stand owns) |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Rules in the database | Yes | The whole exchange is one RPC. The screens show a code and a result. |
| IV — Identity is never a parameter | Yes | The confirming stand comes from `auth.uid()`. The attendee comes from the code, which is the one place an identifier is accepted — and it is single-use, short-lived and unguessable precisely because of that. |
| V — Secrets never reach the client | Partly by design | A claim code IS returned to the attendee's screen: that is its purpose. It is not a credential — it authorises one exchange, at one stand, once. |
| VI — Defence in depth | Yes | Balance, stock, the duplicate check and the code are verified and changed in one indivisible step, on conditional writes. |
| IX — Quality gates | Yes | New SQL suite covering both races. |

## 2. Approach

`claim_reward` is **replaced**, not extended. Its caller changes from the attendee to the stand,
and the moment of payment moves from a tap to a confirmation. What is worth keeping is its atomic
core — the conditional `UPDATE ... WHERE stock > 0` and `UPDATE ... WHERE points >= cost` inside a
subtransaction — and that is carried over verbatim.

Two functions:

- `issue_claim_code()` — the attendee asks; returns a code. Invalidates any previous one.
- `confirm_handover(p_code, p_reward_id)` — the stand confirms; does everything or nothing.

A `claim_codes` table rather than a column on `participants`, because a code has a life of its own:
issued, seen, consumed, expired. One live code per attendee is a partial unique index, not an
`UPDATE` that hopes to win.

**Expiry is derived, like an activity's state.** A code is live while it has not been consumed and
its screen is still asking about it. `last_seen_at` is bumped by the attendee's polling, and a code
is dead once that is more than 60 seconds old. Nothing sweeps: "is this code live?" is answered
when it is presented. Same reasoning as spec 019, and the reason spec 018's section 9 flags the
60 seconds as derived rather than stated.

## 3. Database changes

| File | Change |
|---|---|
| `20_schema.sql` | `claim_codes (id, participant_id, code, issued_at, last_seen_at, consumed_at)`; partial unique index on `(participant_id) WHERE consumed_at IS NULL`; unique on `code` among live rows |
| `54_fulfilment.sql` (new) | `issue_claim_code`, `claim_code_state`, `touch_claim_code`, `confirm_handover` |
| `50_rpc.sql` | `claim_reward` removed |
| `claimed_rewards` | Gains `confirmed_by` (the stand) — spec 024 needs it |

Code alphabet: uppercase letters and digits excluding `O`, `0`, `I`, `1`, `L`, generated in the
database from `gen_random_bytes`. Six characters.

## 4. Frontend changes

| File | Change |
|---|---|
| `src/pages/Rewards.jsx` | The catalogue stops claiming. One control opens the code modal |
| `src/pages/ClaimCodeModal.jsx` | New. Shows the code, polls every 2 seconds, closes itself on confirmation and shows the new balance |
| `src/pages/admin/ClaimsSection.jsx` | New. The console's third section: enter a code, pick one of this stand's rewards, confirm |
| `src/lib/api.js` | `issueClaimCode`, `pollClaimCode`, `confirmHandover` |

## 5. Test strategy

`tests/sql/12_fulfilment.sql`: one use per code; expiry by silence; a second code kills the first;
insufficient balance, out of stock, already claimed and a foreign reward each refuse and change
nothing; the exchange is atomic; two confirmations on the last unit produce one handover; two on
the same code produce one. Nothing is committed before confirmation.

## 6. Risks

- **The code is the one identifier the system accepts.** Every safeguard sits on it. A weakness in
  its generation is a way to spend somebody else's points, so it is generated in the database from
  a cryptographic source, never from a timestamp or an identifier.
- The attendee's modal is the second polling loop; it must stop when the modal closes.
- Removing `claim_reward` breaks any caller left behind. The catalogue is the only one.

## 7. Out of scope

The organiser's view of claims (spec 024) and reward registration (spec 021).
