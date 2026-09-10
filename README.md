# FeriaPoints — University Fair Rewards System

A Progressive Web App (PWA) designed for university fairs, allowing attendees to scan QR codes at stands to earn points and redeem rewards.

## Features

- **PWA**: Installable on mobile devices with offline support.
- **Scanner**: Built-in QR scanner with manual fallback.
- **Admin Panel**: Manage stands, generate rotating QR codes, and view stats.
- **Security**: Time-based rotating QR codes (TOTP-style) with HMAC signatures to prevent sharing and replay attacks.
- **Data Persistence**: Minimal self-hosted backend (Postgres + PostgREST + username auth); leaderboard polls every 5s.

## Tech Stack

- **Frontend**: React, Vite
- **Styling**: Vanilla CSS (CSS Modules/Variables)
- **Routing**: React Router DOM
- **Libraries**: `html5-qrcode` (Scanner), `qrcode.react` (Generator)
- **Backend**: self-hosted minimal stack — Postgres 16 + PostgREST v12 + a zero-dependency Node auth service (username/password, HS256 sessions, 12h access + 48h refresh); your CDN routes + microcaches hot reads (see `nginx-cdn.conf.example`). Game rules live in Postgres RPC (`sign_scan_code`, `validate_and_scan`, `claim_reward`, `stand_login`); RLS scopes writes to `auth.uid()`. No realtime service: the leaderboard polls every 5s.

## Platform targets

- **Node.js 24** — all images pinned to `node:24-alpine` (`Dockerfile`, `auth/Dockerfile`, `dev.sh`). Build/runtime below Node 20.19 is unsupported (Vite 8 requirement).
- **Chrome/Chromium 83 minimum** — lowest device floor is Bromite (= Chromium 83). Enforced via `build.target: 'chrome83'` + `cssTarget: 'chrome83'` in `vite.config.js`; output must not use post-83 syntax.

## Development (local backend mock)

```bash
./dev.sh            # Postgres + PostgREST + auth + Vite on :5173
./dev.sh --fresh    # wipe local DB volume and re-provision
```

Backend files are generated under `.dev/` from the canonical prod sources (`supabase/postgres-init/{20_schema,40_rls,50_rpc}.sql`). API at `http://<lan-ip>:3000`, demo logins printed by the script. Seed: `./seed/*.csv` when present (same logins as prod), else built-in demo stands. After pulling schema changes, run `./dev.sh --fresh` once (old volumes keep the old schema).

## Production deployment

Compose file is prod-oriented: 4 services (web static, Postgres, PostgREST, username auth). No gateway here — your **existing CDN system** routes to the published ports (see `nginx-cdn.conf.example`). TLS terminates there too. No certs in this repo.

### 1. Secrets

```bash
SITE_URL=https://feria.example.com ./deploy-keys.sh   # generates .env.prod (mode 600)
```

Never commit `.env.prod`. `POSTGRES_PASSWORD` is hex-only (URL-safe, embedded in connection strings). Re-run with `--force` to rotate (then `down` + wipe `./data/db`, since the DB password is baked at init).

`deploy-keys.sh` also generates the organiser login (`ORGANIZER_USERNAME` / `ORGANIZER_PASSWORD`), written to the database **only on the first boot of an empty `./data/db`**. Regenerating `.env.prod` while the volume exists leaves the printed password unusable — the panel answers *"Credenciales incorrectas"*. To apply new credentials, wipe `./data/db` (section 6) or update the stored hash:

```sql
UPDATE organizers
SET password_hash = crypt('<organizer-password>', gen_salt('bf', 12))
WHERE username = '<organizer-username>';
```

### 2. Boot

```bash
docker compose --env-file .env.prod up -d --build
```

First boot: Postgres init loads schema + RLS + RPC + seed from `./seed/*.csv` (both files required — copy the tracked `.example` files, see section 4). Init scripts run in numeric order, so a seed that aborts also stops the organiser account from being created. A completion marker is written only after the whole chain succeeds, and the `db` healthcheck requires it: if init aborted, the database stays `unhealthy` and the API is never started against an empty database. Read the database logs before trusting the first boot. Check against published ports:

```bash
curl -s http://localhost:9999/health
curl -s -H "apikey: $ANON" http://localhost:3000/communities?select=name
docker compose --env-file .env.prod exec db psql -U postgres
```

### 3. CDN contract (`nginx-cdn.conf.example`)

Deploy the example on your CDN box: set the 3 upstreams to the docker host IP + published ports (`WEB/REST/AUTH_PORT`). Same public origin serves all paths (TLS also terminates there):

| Path | Target |
|---|---|
| `/rest/v1/*` | PostgREST (GET 200s microcached 5s) |
| `/auth/v1/*` | Auth service (never cached) |
| `/*` | App (SPA) |

Microcache lives in the example (5s TTL, herd lock, stale-while-revalidate, per-session keys). Verify through the CDN:

```bash
curl -sI -H "apikey: $ANON" https://feria.example.com/rest/v1/communities?select=name | grep -i x-microcache
# first: MISS, then: HIT
```

`VITE_SUPABASE_URL` must be the public `https://` origin — Vite bakes it at `docker build` time, so changing the domain requires `--build`.

### 4. Seed accounts from CSV

Both files must exist before the first boot. Copy the tracked examples and edit the
copies: `seed/*.csv` is git-ignored because it holds plaintext passwords, so only the
`.example` files are committed.

```bash
cp seed/stands.csv.example seed/stands.csv
cp seed/rewards.csv.example seed/rewards.csv
chmod 600 seed/stands.csv
# then edit both files
```

No accounts are hardcoded in SQL.

`seed/stands.csv` (required, header `user,pw,name`):

```csv
user,pw,name
meh,Meh2024*,MEH
ieee,Ieee2024*,IEEE
```

`seed/rewards.csv` (required, header-only allowed for "stands only"; header `stand,name,description,cost,stock,emoji` — `stand` matches a `user` above):

```csv
stand,name,description,cost,stock,emoji
meh,CuboRubik Dotnet,Premio de MEH,150,1,Box
```

Rules: UTF-8, quote fields containing commas. Blank `user`/`pw` rows are ignored; blank `name`/`cost` abort the seed visibly. The files are read once, at Postgres init on an empty `./data/db` — they provision a **new deployment only**. To create or change accounts on a running instance, use the organizer panel (or the SQL rotation in section 5); never wipe a live database to re-seed it (section 6).

### 5. Stand credentials

Seeded logins are whatever you put in `seed/stands.csv` — hand each `user,pw` pair to its stand over a secure channel. There is no email recovery; rotate via SQL:

```sql
UPDATE communities
SET password_hash = crypt('NewPass*', gen_salt('bf', 12))
WHERE username = 'meh';
```

(Seed CSV edits only apply on a fresh DB — rotate live passwords with the SQL above.)

### 6. Wipe / redeploy

```bash
docker compose --env-file .env.prod down
rm -rf ./data/db   # DESTRUCTIVE: init + seed re-run on next up
```

A wipe re-creates the organiser from the current `ORGANIZER_*` in `.env.prod` and re-runs the CSV seed.

DB data lives in `./data/db` (bind mount, git-ignored).

## Deployment

The application is containerized using Docker and served via Nginx.

### Prerequisites

- Docker and Docker Compose installed on your system.

### Running with Docker Compose

This starts the full prod stack (needs `.env.prod`, see Production deployment below):

1.  Clone the repository (if not already done).
2.  Run the following command in the project root:

    ```bash
    SITE_URL=https://feria.example.com ./deploy-keys.sh   # generates .env.prod
    docker compose --env-file .env.prod up -d --build
    ```

3.  Access the application at:
    [http://localhost:8080](http://localhost:8080) (or through your CDN at `VITE_SUPABASE_URL`)

### Manual Build

To build and run locally without Docker:

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Build for production
npm run build
# Preview production build
npm run preview
```

## Developer Tools

When running on `localhost`, the scanner page includes a **"Developer Mode"** helper. This allows you to simulate scanning a valid QR code without needing a physical camera, which is useful for testing the rewards flow.
