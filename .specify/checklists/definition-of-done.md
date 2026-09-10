# Definition of Done

Every change must satisfy all of it before it is pushed. With no reviewer, this checklist is
the review — run it yourself, honestly, every time.

## Specification

- [ ] The work maps to an approved spec, and the commit names it.
- [ ] The spec has an approved `plan.md`. (`tasks.md` only if the work spans sessions or people.)
- [ ] Nothing was built that no requirement asked for.
- [ ] The spec was updated if reality diverged from it during implementation.
- [ ] Every acceptance criterion in the spec is checked off.

## Quality gates

- [ ] `npm run lint` passes with no errors and no new warnings.
- [ ] `npm test` passes.
- [ ] `npm run test:sql` passes against a database started with `./dev.sh`.
- [ ] CI is green.

`npm run build` is a release step, not a gate. Do not use it to verify a change.

## Code

- [ ] No secret, credential or real seed data was added to a tracked file.
- [ ] No business rule was moved from Postgres into the client.
- [ ] No RPC accepts a caller identity as a parameter.
- [ ] New tables have RLS enabled and explicit policies.
- [ ] Any new column holding a secret is revoked in `31_column_grants.sql` and asserted in
      `tests/sql/08_column_privileges.sql`. RLS is row level only; it does not hide a column.
- [ ] No syntax or Web API newer than Chromium 83 was introduced.
- [ ] No emoji in source code identifiers, comments or logs.
- [ ] Dead code was removed, not commented out.

## Database

- [ ] If the schema changed, the commit message states whether a wipe is required and whether the
      change is safe to apply during a live event.
- [ ] Changes to `supabase/postgres-init/` were verified with `./dev.sh --fresh`.

## Repository hygiene

- [ ] Commits follow the Spanish conventional format with emoji (`AGENTS.md`).
- [ ] **No commit message, PR description, comment or file credits, mentions or links an AI
      model or assistant.** No `Co-Authored-By` naming a model, no "Generated with" footer, no
      session links.
- [ ] The branch is named after its spec (`NNN-slug`).
- [ ] Documentation touched by the change was updated in the same commit.
