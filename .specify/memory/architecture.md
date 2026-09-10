# Architecture Overview

This is the shared mental model every spec assumes. It describes the system **as it is today**,
not as it might become. Keep it accurate: a spec that contradicts this file is either wrong or
is proposing a change that needs an ADR.

## What the system is

A Progressive Web App for university fairs. Attendees walk between stands, scan a rotating QR
code at each one, accumulate points, and exchange them for physical prizes. The whole system is
designed to run for the hours a fair lasts and then be torn down.

Target scale: **~10 stands, ~300 attendees, single event**. Decisions that would only matter at
larger scale (the `O(n)` short-code search, the 5-second poll) are accepted at this size and are
documented as such in the relevant specs.

## Actors

| Actor | Authentication | Where their identity lives |
|---|---|---|
| Participant | Anonymous session issued by the auth service at registration | `participants.auth_user_id` = JWT `sub` |
| Stand admin | Username + bcrypt password, verified by the `stand_login` RPC | `communities.auth_user_id` = `communities.id` = JWT `sub` |
| Event operator | None — works outside the application | CSV files, `psql`, `docker compose` |

`localStorage` (`fp_current_participant_id`) is a display cache only. The source of truth for
who is acting is always the JWT, verified in Postgres.

## Runtime topology

```
                     public origin (TLS terminates at the customer's CDN)
                                        |
            +---------------------------+---------------------------+
            |                           |                           |
        /rest/v1/*                  /auth/v1/*                     /*
    PostgREST v12               auth service (Node)            static SPA
    GET 200s microcached 5s      never cached                   nginx
            |                           |
            +-----------+---------------+
                        |
                  Postgres 16
        schema + RLS + RPC + CSV seed, loaded once at first init
```

Four containers (`docker-compose.yml`): `web`, `db`, `rest`, `auth`. There is **no gateway in
this repository** — routing and TLS are the responsibility of an existing CDN, whose expected
configuration is documented by example in `nginx-cdn.conf.example`.

There is no realtime service. The leaderboard polls every 5 seconds and refetches on tab focus;
the CDN microcache collapses the resulting herd into roughly one query per window.

## Frontend

React 19 + Vite 8, plain JavaScript (no TypeScript), vanilla CSS in a single `src/index.css`
design system. Routing is `HashRouter`, so URLs look like `/#/dashboard`.

- `src/lib/api.js` — the only module that talks to the backend. All PostgREST queries and RPC
  calls go through here.
- `src/lib/AuthContext.jsx` — participant and stand-admin session state.
- `src/lib/qrSecurity.js` — encodes and decodes the already-signed payload; computes the
  countdown to the next rotation. **It does no signing and holds no secret.**
- `src/supabaseClient.js` — a `@supabase/supabase-js` client. The library is retained for its
  ergonomics; the backend behind it is self-hosted, not Supabase Cloud.

## Backend

Postgres is the application. `supabase/postgres-init/*.sql` runs once, in numeric order, against
an empty `./data/db`:

| File | Role |
|---|---|
| `10_roles.sql` | `anon`, `authenticated`, `service_role`, `authenticator` |
| `15_extensions.sql` | `pgcrypto` for `hmac`, `crypt`, `gen_random_uuid` |
| `20_schema.sql` | Six tables + a random `hmac_secret` |
| `25_auth_columns.sql`, `26_password_hash.sql` | Identity columns; drops the plaintext password column (audit finding F2) |
| `30_grants.sql` | Broad grants — the real filter is RLS |
| `35_auth_shim.sql` | `auth.uid()` and `auth.jwt()` reading `request.jwt.claims`; there is no GoTrue |
| `40_rls.sql` | Policies on all six tables |
| `50_rpc.sql`, `51_stand_login.sql` | Every game rule |
| `70_seed.sql` | Loads `seed/stands.csv` and `seed/rewards.csv`; aborts loudly if absent |

The auth service (`auth/server.mjs`, zero dependencies) implements the subset of the GoTrue API
that `supabase-js` calls: `POST /token` (password and refresh grants), `POST /signup` (anonymous),
`POST /logout`, `GET /user`, `GET /health`. It signs HS256 with the shared `JWT_SECRET`, issues
12-hour access tokens and 48-hour refresh tokens, and rate-limits to 20 attempts per 5 minutes
per IP and username. It delegates password verification to the `stand_login` RPC.

## Data model

```
communities (the STAND)                          rewards
  id, username UNIQUE, password_hash,      1---N   id, community_id, name, description,
  name, emoji (Lucide icon name),                  cost, stock, emoji
  stand_number, description,                         |
  visit_points 0..30, activity_points 0..100         | 1
  auth_user_id UNIQUE, created_at                    |
        | 1                                          | N
        | N                                    claimed_rewards
      scans                                      id, participant_id, reward_id, claimed_at
        id, participant_id, community_id,        UNIQUE (participant_id, reward_id)
        points, type ('visit'|'activity'),             | N
        created_at                                    |
        UNIQUE (participant_id, community_id)          | 1
               WHERE type = 'activity'          participants (the ATTENDEE)
        | N                                       id, name, points >= 0, fingerprint,
        +------------------- 1 -------------------  auth_user_id UNIQUE, registered_at

settings: key -> value. One row: 'hmac_secret'. RLS on, no policy: unreachable from any client.
```

`auth_user_id` columns are plain UUIDs with no foreign key: there is no GoTrue `auth.users`
table to reference.

## Environments

| Environment | How it runs |
|---|---|
| Local development | `./dev.sh` generates `.dev/` from the canonical SQL and starts Postgres, PostgREST, a mock auth service and Vite, bound to the LAN so phones can reach it. `./dev.sh --fresh` wipes the volume. Schema changes require `--fresh`. |
| Production | `deploy-keys.sh` writes `.env.prod` (mode 600), then `docker compose --env-file .env.prod up -d --build`. `VITE_SUPABASE_URL` is baked at build time, so changing the domain requires `--build`. |

## Known constraints and accepted trade-offs

- **Short-code lookup is `O(stands x 2 types x 2 windows)`** HMAC computations per attempt, with
  no rate limit of its own. Accepted at ~10 stands; revisit before a larger event.
- **Six-hex-character short codes** can in principle collide across stands within a window.
- **`participants` and `communities` are publicly readable**, so the leaderboard and the stand
  list can be public. Row level security is row level only, so `31_column_grants.sql` carries the
  column-level privileges: `communities.password_hash`, `communities.password` and
  `participants.fingerprint` are revoked from every client role. **A new column holding a secret
  must be added to that file, or it is public by default.**
- **The QR issuer identity is `premiosferia`** in `auth/server.mjs` and the production container
  is named `feriapoints`; both are legacy names slated for normalisation (spec 016).
