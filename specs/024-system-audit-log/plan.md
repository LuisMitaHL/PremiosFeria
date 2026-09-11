# Plan 024 — System audit log

| | |
|---|---|
| **Spec** | [`spec.md`](spec.md) |
| **Status** | Approved |
| **Depends on** | Specs 018, 019, 020, 021, 022, 023 — every action this records |
| **Last updated** | 2026-09-10 |

## 1. Constitution check

| Principle | Complies | Note |
|---|---|---|
| III — Rules in the database | Yes | Recording happens inside the functions that already hold the rules. Nothing is logged from the client, which could lie or simply not call. |
| IV — Identity is never a parameter | Yes | Every RPC has already resolved its caller from `auth.uid()` before it acts; it passes what it resolved. `audit()` is server-to-server, never client-to-server. |
| V — Secrets never reach the client | Yes, and enforced | Passwords, claim codes and recovery codes all pass through logged actions. A `BEFORE INSERT` trigger refuses an entry carrying one, so R9 is a lock rather than a habit. |
| VI — Defence in depth | Yes | Append-only is three locks: revoked privileges, RLS with no policy, and a trigger that also binds the owner. |
| IX — Quality gates | Yes | New SQL suite, including that each action writes its entry and that no path edits one. |

## 2. Approach

Two files, split by who uses them. `45_audit.sql` holds the table and the writer and is numbered
before `50` because every function from `50` onward writes to it. `59_audit_read.sql` holds the
reader, which needs `calling_organizer()` from `55`.

**Recording is an `INSERT` in the caller's transaction, not a queue, a trigger on each table, or a
separate connection.** Table triggers were considered and rejected: they see rows change, not
actions refused, and R3 makes refusals the larger half of this log. They also cannot record *why*.

**The actor is passed, not re-derived.** Every RPC resolves its caller before it acts, so
`audit()` takes `actor_kind` and `actor_id` as arguments. Re-deriving them inside `audit()` would
mean three extra lookups on the busiest write path in the system — every scan, including refused
ones — to recompute something the caller already knows. `audit_actor()` exists for the few places
that must record a refusal precisely *because* they could not resolve a caller.

**Ordering is an identity column, not a timestamp.** Two actions in the same instant must read
back in an unambiguous order, and `now()` is the same value for everything in one transaction.

**Paging is by key, not by `OFFSET`.** The organiser reads newest-first while the fair keeps
writing at that end; an `OFFSET` over a table growing at the head repeats and skips rows. The
cursor is the last delivered `id`.

## 3. The vocabulary

An action name is `scope.verb`, lower case, enforced by a `CHECK`. The scope is what the screen
filters by, so it is the noun the organiser would use: `scan`, `reward`, `activity`, `community`,
`participant`, `claim`, `auth`.

| Action | Written by | Subject | `before` holds |
|---|---|---|---|
| `participant.register` | `register_or_recover` | the participant | — |
| `participant.recover` | `redeem_recovery_code` | the participant | — |
| `participant.rename` | `organizer_rename_participant` | the participant | `{name}` |
| `participant.set_flags` | `organizer_set_participant_flags` | the participant | `{claims_barred, is_removed}` |
| `participant.adjust_points` | `organizer_adjust_points` | the participant | `{points}` |
| `participant.issue_recovery` | `issue_recovery_code` | the participant | — |
| `scan.award` | `validate_and_scan` | the stand | — |
| `claim.issue_code` | `issue_claim_code` | the participant | — |
| `claim.handover` | `confirm_handover` | the reward | `{points, stock}` |
| `activity.create` / `.update` / `.start` / `.finish` | `52_activities.sql` | the activity | the changed fields |
| `reward.create` / `.restock` | `53_rewards.sql` | the reward | `{stock}` on restock |
| `reward.reprice` / `.set_stock` / `.withdraw` | `56_organizer_communities.sql` | the reward | `{cost}`, `{stock}`, `{is_withdrawn}` |
| `community.create` / `.update` / `.reset_password` / `.set_withdrawn` | `56_organizer_communities.sql` | the community | the changed fields |
| `auth.sign_in_failed` | `stand_login`, `organizer_login` | — | — |

**The actor id is always a domain id** — a participant, community or organiser id, never the
token's subject. Mixing the two spaces would mean filtering the log by a stand silently omits
that stand's refused attempts, which are exactly the entries someone would go looking for.
`audit_actor_id()` resolves it for the paths that could not resolve a caller themselves.

**`before` holds only the fields that changed**, not the whole row. Copying the row is how a hash
or a fingerprint ends up in the log, and it is the reason the trigger exists.

**`auth.sign_in_failed` records that an attempt failed and nothing about the attempt** — not the
username tried, not the password, not a prefix of either. A log of failed sign-ins that names what
was tried is a list of guessed credentials, sitting on the one screen the organiser reads all day.

## 4. Where refusals are recorded

Every `RETURN jsonb_build_object('error', ...)` and every `'valid', false` / `'success', false`
path gets an entry carrying that same message as the reason. Two deliberate exceptions:

- **`poll_my_claim_code` and the `participant_detail` read path write nothing.** They change
  nothing, and R5 says the log must not become a general diagnostic stream. A poll every two
  seconds per attendee would bury the log in entries about nothing happening.
- **`close_expired_activities` writes nothing.** It closes activities whose duration has
  elapsed, and nobody performed it — it is derived cleanup that any read can trigger.
  Logging it would attribute a change to whichever attendee happened to open a screen.

- **An unauthorised call writes an entry**, because "a stand tried to read the log" is exactly the
  kind of thing the organiser should be able to see. It records the caller resolved from the
  session, never anything the caller supplied.

## 5. Risks

| Risk | Handling |
|---|---|
| A client forges entries | `audit()` and the two refusal helpers are `SECURITY DEFINER` functions in `public`, which is exactly what PostgREST publishes as `/rpc/...`, and Postgres grants `EXECUTE` to `PUBLIC` by default. Their privileges are revoked explicitly. A log a third party can write to is worth no more than one they can edit. |
| The log slows down scanning | One `INSERT` with no index on a text column that gets searched; the indexes are on the columns the organiser filters by. The write path gains one row, not a lookup. |
| An `EXCEPTION` block swallows a failed write | R21 requires the opposite. Audit calls go **outside** the `BEGIN ... EXCEPTION` blocks that exist for conditional writes, or in their handlers — never inside a block whose handler would turn a failed entry into a silent success. |
| A future action forgets to log | The suite asserts per action, so a new action with no entry fails a test rather than passing quietly. This is the weakest guarantee here, and it is stated as such. |
| Volume on the screen | Server-clamped page size; the client never chooses how much to fetch. |

## 6. Verification

- SQL suite `tests/sql/16_audit_log.sql`: every action in section 3 writes its entry; refusals
  carry their reason; no entry holds a secret; `UPDATE`, `DELETE` and `TRUNCATE` are all refused;
  a stand and a participant reading the log get nothing; filters work together; paging returns
  each entry exactly once.
- Mutation testing: every assertion is proven to fail when the rule it covers is broken.
- Browser: the organiser's log screen, filtered by scope, actor and time range, against a fair
  with real activity in it.
