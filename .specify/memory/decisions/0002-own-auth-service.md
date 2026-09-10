# 0002 — Replace GoTrue with a zero-dependency auth service

Status: Accepted (retroactive — shipped 2026-09-09)
Relates to: `auth/server.mjs`, `supabase/postgres-init/51_stand_login.sql`, `35_auth_shim.sql`

## Context

Two identity needs, both unusual:

1. **Participants** must register with a name and nothing else. No email, no password, no
   verification step — anything more would lose attendees at the door.
2. **Stand admins** log in with a plain username such as `meh`, handed to them on paper before
   the fair. There is no email to recover from and no support desk during the event.

GoTrue is email-centric. Running it meant carrying a large service, its migrations and its
configuration surface to use a fraction of it, and faking email addresses to log a stand in.

## Decision

Write the subset ourselves: `auth/server.mjs`, a Node service with **no dependencies**,
implementing the GoTrue endpoints that `supabase-js` actually calls — `POST /token` (password
and refresh grants), `POST /signup` (anonymous), `POST /logout`, `GET /user`, `GET /health`.

It signs HS256 with the `JWT_SECRET` shared with PostgREST, issues 12-hour access tokens and
48-hour refresh tokens, rate-limits to 20 attempts per 5 minutes per IP and username, compares
with `crypto.timingSafeEqual`, and answers a uniform `invalid_credentials` so usernames cannot be
enumerated. Password verification is delegated to the `stand_login` RPC, so bcrypt hashes never
leave Postgres.

Because there is no GoTrue, there is no `auth.users` table. `35_auth_shim.sql` supplies
`auth.uid()` and `auth.jwt()` by reading `request.jwt.claims`, and the `auth_user_id` columns are
plain UUIDs with no foreign key.

## Consequences

- Roughly 330 lines of auditable code replace a large service.
- Everything GoTrue would have given us for free is now ours to maintain: rotation, revocation,
  lockout, audit logging. Only what the event needs was built.
- There is no password recovery. Rotating a stand password is a documented SQL `UPDATE`.
- The JWT issuer is the legacy string `premiosferia` (normalised in spec 016).
