# 0001 — Leave Supabase Cloud for a minimal self-hosted stack

Status: Accepted (retroactive — shipped 2026-09-09)
Relates to: `docker-compose.yml`, `deploy-keys.sh`, `nginx-cdn.conf.example`

## Context

The system was built on Supabase Cloud: hosted Postgres, GoTrue, Realtime, and the managed API
gateway. The product is an **ephemeral event application** — it runs for the hours a fair lasts,
a handful of times a year, for roughly 300 attendees. A managed platform meant a permanent
account, a permanent bill and a permanent dependency for something switched on for an afternoon.
The operators already run their own CDN and their own hosts.

## Decision

Run the stack ourselves: Postgres 16, PostgREST v12, a small auth service and an nginx serving
the built SPA, as four containers with bind-mounted data. Routing and TLS stay with the CDN the
operators already run; this repository ships an example configuration rather than a gateway.

Keep `@supabase/supabase-js` on the client. The library's ergonomics are good and PostgREST is
the same wire protocol; replacing it would have been churn with no benefit.

## Consequences

- The whole event can be provisioned from nothing and destroyed afterwards, with no external
  account involved.
- Everything the platform used to provide must now be provided here: role bootstrapping, grants,
  an `auth.uid()` shim, JWT issuance, secret generation, seeding.
- `VITE_SUPABASE_URL` is baked into the bundle at build time, so changing the public origin
  requires rebuilding the image.
- The variable names still say supabase although no Supabase service is involved. Kept to avoid
  a rename with no functional gain.
