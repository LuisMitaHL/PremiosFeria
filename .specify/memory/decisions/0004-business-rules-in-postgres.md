# 0004 — Keep every game rule in Postgres RPC

Status: Accepted (retroactive — shipped 2026-08-25, in response to a security audit)
Relates to: `supabase/postgres-init/50_rpc.sql`, `40_rls.sql`, `20_schema.sql`

## Context

The client is a public PWA. Anyone at the fair can open devtools, read the bundle, and call the
API directly with the anon key. Points buy real prizes, so there is a real incentive to cheat.

An external audit found the original design trusted the browser too much. Its findings are
referenced in code comments to this day: **F2** stand passwords stored in plaintext, **F3** the
HMAC secret shipped to the client so anyone could mint valid QR codes, **F4** participant
identity passed as a parameter so anyone could award points to anyone, **F8** a race in the
visit cooldown that let concurrent scans both pass.

## Decision

Move every rule that matters into `SECURITY DEFINER` PL/pgSQL functions with
`SET search_path = public`, and treat the client as a rendering layer:

- `sign_scan_code` signs QR payloads server-side; the secret stays in `settings`, a table with
  RLS on and no policy, so no client role can read it.
- `validate_and_scan` resolves the participant from `auth.uid()`, locks the row with
  `FOR UPDATE` before evaluating the cooldown, verifies the HMAC, checks the rotation window,
  and re-clamps points with `GREATEST(0, LEAST(...))` against the stand's own ceilings.
- `claim_reward` gates on conditional `UPDATE ... WHERE stock > 0` and
  `UPDATE ... WHERE points >= cost` inside a subtransaction.
- `stand_login` compares bcrypt hashes inside the database.

Structural invariants back the procedural ones: a partial unique index for one activity per
stand, `CHECK` constraints for the point ceilings and for non-negative balances, and a unique
constraint on `(participant_id, reward_id)`.

## Consequences

- A tampered client cannot mint points, replay a code, skip a cooldown, or oversell stock.
- The rules are written in PL/pgSQL, which fewer contributors read comfortably, and they are
  only reachable through Postgres — which is why the Definition of Done requires SQL tests
  against a real database rather than mocks.
- Changing a rule means changing SQL, and the init scripts run **only once on an empty volume**,
  so schema changes require `./dev.sh --fresh` locally and a wipe in production.
- Friendly pre-checks are duplicated in front of the real gates. This is deliberate: the
  pre-check writes the message, the constraint enforces the rule.
