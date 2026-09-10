# SQL business-rule tests

Every rule that protects the point economy lives in Postgres (constitution III and ADR 0004), so
it is tested against a real database. There are no mocks here: a mock of `validate_and_scan`
would prove nothing about the function that actually runs during the fair.

## Running them

```bash
./dev.sh          # start the local stack once
npm run test:sql  # run the suite against it
```

Against any other reachable server, point `PSQL_CMD` at it:

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PSQL_CMD="psql" npm run test:sql
```

Either way the runner drops and rebuilds a throwaway database
(`community_quest_test`) from the **canonical production scripts** in
`supabase/postgres-init/`, runs the suite there, and drops it again. The dev
stack's own database is never touched, and the schema under test is always the
one that ships — not the dev variant, which diverges from it.

## How a test is written

Each file is self-contained and leaves nothing behind:

```sql
\set ON_ERROR_STOP on
BEGIN;
  -- fixtures: create the stands and participants this test needs
  -- act:      call the RPC
  -- assert:   RAISE EXCEPTION with a readable message when the result is wrong
ROLLBACK;
```

Rules of the house:

- **Roll back.** Never leave rows behind; the order of the files must not matter.
- **Build your own fixtures.** Never depend on seed data, which is operator-supplied and absent
  in CI.
- **Assert with `RAISE EXCEPTION`**, not `ASSERT` — assertions can be switched off with
  `plpgsql.check_asserts`, and a test that can be silently disabled is not a gate.
- **Say what failed.** The message is what a person reads at 8am on the day of the fair.
- **Set the actor explicitly** with `SET LOCAL request.jwt.claims`, the same way PostgREST does.
  Identity is never a parameter (constitution IV), so this is the only way to act as someone.

## Adding a test

Every business rule in section 5 of a spec needs one. Every path that awards or spends points
needs a concurrency test as well. Number the file after the rule it covers, not after the spec.
