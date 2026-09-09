# FeriaPoints — University Fair Rewards System

A Progressive Web App (PWA) designed for university fairs, allowing attendees to scan QR codes at stands to earn points and redeem rewards.

## Features

- **PWA**: Installable on mobile devices with offline support.
- **Scanner**: Built-in QR scanner with manual fallback.
- **Admin Panel**: Manage stands, generate rotating QR codes, and view stats.
- **Security**: Time-based rotating QR codes (TOTP-style) with HMAC signatures to prevent sharing and replay attacks.
- **Data Persistence**: Supabase backend (Postgres + PostgREST + Auth + Realtime); leaderboard/scans update live.

## Tech Stack

- **Frontend**: React, Vite
- **Styling**: Vanilla CSS (CSS Modules/Variables)
- **Routing**: React Router DOM
- **Libraries**: `html5-qrcode` (Scanner), `qrcode.react` (Generator)
- **Backend**: self-hosted Supabase-minimal — Postgres 16 + PostgREST v12 + GoTrue (auth) + Realtime, behind an nginx gateway. Game rules live in Postgres RPC (`sign_scan_code`, `validate_and_scan`, `claim_reward`); RLS scopes writes to `auth.uid()`.

## Development (local backend mock)

```bash
./dev.sh            # Postgres + PostgREST + auth-mock + Vite on :5173
./dev.sh --fresh    # wipe local DB volume and re-provision
```

Backend files are generated under `.dev/` from the committed sources (`schema SQL community quest.txt`, `RLS.txt`, `RPC.txt`). API at `http://<lan-ip>:3000`, demo logins printed by the script.

## Production deployment

Compose file is prod-oriented: app + minimal Supabase behind a plain-HTTP gateway. An **external TLS proxy** terminates HTTPS and forwards to the gateway. No certs in this repo.

### 1. Secrets

```bash
SITE_URL=https://feria.example.com ./deploy-keys.sh   # generates .env.prod (mode 600)
```

Never commit `.env.prod`. `POSTGRES_PASSWORD` is hex-only (URL-safe, embedded in connection strings). Re-run with `--force` to rotate (then `down` + wipe `./data/db`, since the DB password is baked at init).

### 2. Boot

```bash
docker compose --env-file .env.prod up -d --build
```

First boot: Postgres init (`supabase/postgres-init/`: roles, schema, RLS, RPC, realtime publication) → GoTrue migrates `auth.*` → one-shot `bootstrap` seeds 10 stands + 4 rewards + GoTrue users. Check:

```bash
curl -s http://localhost:8080/auth/v1/health
curl -s -H "apikey: $ANON" http://localhost:8080/rest/v1/communities?select=name
docker compose --env-file .env.prod exec db psql -U postgres
```

### 3. TLS front contract

Forward to gateway `${GATEWAY_PORT:-8080}` as plain HTTP, preserving `Host` and setting `X-Forwarded-Proto: https`. Same host serves all paths:

| Path | Target |
|---|---|
| `/rest/v1/*` | PostgREST |
| `/auth/v1/*` | GoTrue |
| `/realtime/v1/*` | Realtime (websocket) |
| `/*` | App (SPA) |

`SITE_URL` / `VITE_SUPABASE_URL` must be the public `https://` origin — Vite bakes them at `docker build` time, so changing the domain requires `--build`.

### 4. Seed accounts from CSV

Drop two files in `./seed/` (git-ignored, operator-only). No accounts are hardcoded in SQL.

`seed/stands.csv` (required, header `user,pw,name`):

```csv
user,pw,name
meh@feria.local,Meh2024*,MEH
ieee@feria.local,Ieee2024*,IEEE
```

`seed/rewards.csv` (optional, header `stand,name,description,cost,stock,emoji` — `stand` matches a `user` above):

```csv
stand,name,description,cost,stock,emoji
meh@feria.local,CuboRubik Dotnet,Premio de MEH,150,1,Box
```

Rules: UTF-8, quote fields containing commas. Blank `user`/`pw` rows are ignored; blank `name`/`cost` abort the seed visibly. Re-running only adds missing rows (keyed on email / stand+name) — never duplicates, never wipes. If `stands.csv` is absent at boot, seeding is skipped; add files later and re-run:

```bash
docker compose --env-file .env.prod run --rm bootstrap
```

### 5. Stand credentials

Seeded logins are whatever you put in `seed/stands.csv` — hand each `user,pw` pair to its stand over a secure channel. Rotate after handover via password reset, or update `auth.users` directly with `crypt(newpw, gen_salt('bf'))`.

### 6. Wipe / redeploy

```bash
docker compose --env-file .env.prod down
rm -rf ./data/db   # DESTRUCTIVE: init + seed re-run on next up
```

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
    cp .env.prod.example .env.prod   # fill secrets first
    docker compose --env-file .env.prod up -d --build
    ```

3.  Access the application at:
    [http://localhost:8080](http://localhost:8080) (or behind your TLS proxy at `SITE_URL`)

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
