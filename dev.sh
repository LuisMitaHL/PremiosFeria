#!/usr/bin/env bash
# ============================================================================
# dev.sh — spin up a local dev instance of PremiosFeria / Community Quest
#
# Stands up, via Docker:
#   - Postgres 16   (schema + RLS + RPC + seed applied on first init)
#   - PostgREST v12 (REST API; exposed under /rest/v1 via an nginx gateway)
# then runs the Vite dev server against it.
#
# The backend reproduces the app's canonical schema/RLS/RPC (copies of
# supabase/postgres-init/{20_schema,31_column_grants,40_rls,50_rpc}.sql), so you develop
# against the same behavior as production.
#
# Uses:
#   ./dev.sh            start / re-attach
#   ./dev.sh --fresh    wipe the local DB volume and re-provision from scratch
#
# Requires: docker (daemon running), node + npm, curl.
# Ports (override with env): DB_PORT=55433  API_PORT=3000  Vite stays 5173.
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV="$REPO/.dev"
SQL="$DEV/sql"
COMPOSE="$DEV/docker-compose.yml"

# Fixed dev-only secrets. Local instance only — never use in a deploy.
export JWT_SECRET="dev_only_super_secret_do_not_use_in_prod"
AUTH_PASSWORD="authenticator_dev"
DB_PORT="${DB_PORT:-55433}"
API_PORT="${API_PORT:-3000}"
# LAN IP so phones / other machines on the network reach Vite + API.
# Plain-HTTP LAN is not a secure context: remote cameras fail, use manual codes.
# (|| true: hostname/ip variants differ per OS; never fail under set -e.)
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
if [ -z "$LAN_IP" ] && command -v ip >/dev/null 2>&1; then
  LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)"
fi
LAN_IP="${LAN_IP:-localhost}"
APP_URL="http://${LAN_IP}:5173"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
for cmd in docker node npm curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✗ missing '$cmd' — install it and re-run." >&2
    exit 1
  fi
done
if ! docker info >/dev/null 2>&1; then
  echo "✗ Docker daemon is not running. Start it first (e.g. 'sudo systemctl start docker')." >&2
  exit 1
fi

for f in supabase/postgres-init/20_schema.sql supabase/postgres-init/31_column_grants.sql supabase/postgres-init/40_rls.sql supabase/postgres-init/50_rpc.sql; do
  [ -f "$REPO/$f" ] || { echo "✗ expected '$REPO/$f' (canonical source) not found." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Provision backend files under ./.dev/
# ---------------------------------------------------------------------------
mkdir -p "$SQL"

# Rev-1 reset
if [ "${1:-}" = "--fresh" ]; then
  echo "⟲ wiping local dev DB volume..."
  docker compose -f "$COMPOSE" down -v >/dev/null 2>&1 || true
fi

# Roles + grants (idempotent so a retained volume never errors on re-provision)
cat > "$SQL/10_roles.sql" <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'authenticator_dev';
  END IF;
END $$;
GRANT anon TO authenticator;
SQL

# Schema, RLS, RPC — copies of the canonical prod sources (same behavior).
# Deliberately NOT applied from prod: 25 (drops the password column dev
# needs in plaintext), 26/51 (bcrypt flow), 30 (dev grants below),
# 70 (prod CSV seed at init; dev seeds its own way further down).
cp "$REPO/supabase/postgres-init/20_schema.sql" "$SQL/20_schema.sql"
cat > "$SQL/30_grants.sql" <<'SQL'
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
SQL
# Column privileges are canonical: dev must hide the same secrets prod hides,
# or a leak is invisible until production.
cp "$REPO/supabase/postgres-init/31_column_grants.sql" "$SQL/31_column_grants.sql"
cp "$REPO/supabase/postgres-init/40_rls.sql" "$SQL/40_rls.sql"
cp "$REPO/supabase/postgres-init/50_rpc.sql" "$SQL/50_rpc.sql"

# Auth compat — must run BEFORE 40_rls.sql (its policies call auth.uid()).
# Plain Postgres knows no auth.uid()/auth.jwt(); local gets a compat layer.
cat > "$SQL/35_auth_compat.sql" <<'SQL'
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(auth.jwt() ->> 'sub', '')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO PUBLIC;

-- pgcrypto: the RPC uses hmac() for scan codes.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE participants ADD COLUMN IF NOT EXISTS auth_user_id UUID;
ALTER TABLE communities ADD COLUMN IF NOT EXISTS auth_user_id UUID;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'community_admin') THEN
    CREATE ROLE community_admin NOLOGIN;
  END IF;
END $$;
GRANT anon TO authenticated;
GRANT anon TO community_admin;
GRANT authenticated TO authenticator;
GRANT community_admin TO authenticator;
SQL

# After seed (60_*): dev mock auth issues sub = community id for admin logins,
# so link each community to its own uuid.
cat > "$SQL/70_auth_link.sql" <<'SQL'
UPDATE communities SET auth_user_id = id WHERE auth_user_id IS NULL;
SQL

# Dev seed: communities get plaintext username/password (the mock auth reads
# them) so you can log in as any stand. Usernames are bare (prod shape).
# Source: ./seed/*.csv when present (same logins as prod), else built-in demo.
cat > "$DEV/csv-seed.mjs" <<'MJS'
// csv-seed.mjs — ./seed/*.csv (prod format) -> dev 60_seed.sql (plaintext pw).
// Usage: node csv-seed.mjs stands.csv [rewards.csv] out.sql
// Prints "user / pw (name)" login lines to stdout for the dev banner.
import fs from "node:fs";
const [standsPath, rewardsPath, outPath] = process.argv.slice(2);
const q = (s) => `'${String(s ?? "").replace(/'/g, "''")}'`;
function parseCSV(path) {
  let text = fs.readFileSync(path, "utf8").replace(/^\uFEFF/, "");
  const rows = [];
  let row = [], field = "", inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else inQ = false;
      } else field += c;
    } else if (c === '"') inQ = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((v) => v !== "")) rows.push(row);
      row = [];
    } else field += c;
  }
  row.push(field);
  if (row.some((v) => v !== "")) rows.push(row);
  return rows;
}
function table(path, want) {
  const rows = parseCSV(path);
  const header = (rows.shift() || []).map((h) => h.trim());
  const idx = want.map((w) => header.indexOf(w));
  if (idx.some((i) => i < 0)) {
    console.error(`✗ ${path}: header must be ${want.join(",")}`);
    process.exit(1);
  }
  return rows.map((r) => Object.fromEntries(want.map((w, k) => [w, (r[idx[k]] ?? "").trim()])));
}
const out = [];
out.push("DELETE FROM claimed_rewards;");
out.push("DELETE FROM rewards;");
out.push("DELETE FROM scans;");
out.push("DELETE FROM communities;");
out.push("DELETE FROM participants;");
out.push("");
const logins = [];
for (const s of table(standsPath, ["user", "pw", "name"])) {
  if (!s.user || !s.pw || !s.name) { console.error(`✗ ${standsPath}: blank user/pw/name: ${JSON.stringify(s)}`); process.exit(1); }
  out.push(`INSERT INTO communities (username, password, name) VALUES (${q(s.user)}, ${q(s.pw)}, ${q(s.name)});`);
  logins.push(`    ${s.user}  (password: ./seed/stands.csv)`);
}
out.push("");
if (rewardsPath) {
  for (const r of table(rewardsPath, ["stand", "name", "description", "cost", "stock", "emoji"])) {
    if (!r.stand || !r.name) { console.error(`✗ ${rewardsPath}: blank stand/name: ${JSON.stringify(r)}`); process.exit(1); }
    const cost = Number(r.cost), stock = r.stock === "" ? 0 : Number(r.stock);
    if (!Number.isInteger(cost) || cost < 0 || !Number.isInteger(stock) || stock < 0) {
      console.error(`✗ ${rewardsPath}: bad cost/stock: ${JSON.stringify(r)}`); process.exit(1);
    }
    out.push(`INSERT INTO rewards (community_id, name, description, cost, stock, emoji) VALUES ((SELECT id FROM communities WHERE username=${q(r.stand)}), ${q(r.name)}, ${q(r.description || "")}, ${cost}, ${stock}, ${q(r.emoji || "Gift")});`);
  }
  out.push("");
}
out.push("INSERT INTO participants (id, name, points) VALUES");
out.push("('a0000001-0000-0000-0000-000000000000', 'Participante Demo', 0);");
fs.writeFileSync(outPath, out.join("\n") + "\n");
console.log(logins.join("\n"));
MJS

if [ -r "$REPO/seed/stands.csv" ]; then
  echo "▸ seeding dev DB from ./seed/*.csv (prod logins) ..."
  if [ -r "$REPO/seed/rewards.csv" ]; then REWARDS_CSV="$REPO/seed/rewards.csv"; else REWARDS_CSV=""; fi
  node "$DEV/csv-seed.mjs" "$REPO/seed/stands.csv" "$REWARDS_CSV" "$SQL/60_seed.sql" > "$DEV/seed-creds.txt"
else
  echo "▸ seeding dev DB with built-in demo stands ..."
  cat > "$SQL/60_seed.sql" <<'SQL'
DELETE FROM claimed_rewards;
DELETE FROM rewards;
DELETE FROM scans;
DELETE FROM communities;
DELETE FROM participants;

INSERT INTO communities (id, username, password, name, emoji, stand_number, visit_points, activity_points) VALUES
('d0000001-0000-0000-0000-000000000000','cypheranviil','Cypher2024*','CypherAnvil','Shield','1',10,25),
('d0000002-0000-0000-0000-000000000000','meh','Meh2024*','MEH','Cpu','2',10,25),
('d0000003-0000-0000-0000-000000000000','ieee','Ieee2024*','IEEE','RadioReceiver','3',10,25),
('d0000004-0000-0000-0000-000000000000','aws.umsa','Aws2024*','AWS','Cloud','4',10,25),
('d0000005-0000-0000-0000-000000000000','guild','Guild2024*','Guild','Swords','5',10,25),
('d0000006-0000-0000-0000-000000000000','codemiaw','Codecats2024*','Codecats','Cat','6',10,25),
('d0000007-0000-0000-0000-000000000000','pancho','Cpc2024*','CPC','Code','7',10,25),
('d0000008-0000-0000-0000-000000000000','casdasd','Ctrldev2024*','CtrlDev','Terminal','8',10,25),
('d0000009-0000-0000-0000-000000000000','microbot','Microbot2024*','Microsoft Umsa','LayoutGrid','9',10,25),
('d000000a-0000-0000-0000-000000000000','trateur010','Ciasi2024*','CIASI','Database','10',10,25);

INSERT INTO rewards (community_id, name, description, cost, stock, emoji) VALUES
('d0000002-0000-0000-0000-000000000000','CuboRubik Dotnet','Premio de MEH',150,1,'Box'),
('d0000004-0000-0000-0000-000000000000','Polera Community Day XL','Premio de la comunidad AWS Umsa',200,1,'Shirt'),
('d0000008-0000-0000-0000-000000000000','1 mes vps','Servicio cloud de CtrlDev',250,1,'Server'),
('d0000009-0000-0000-0000-000000000000','Pelotitas Antiestres','Premio de Microsoft',50,1,'Circle');

INSERT INTO participants (id, name, points) VALUES
('a0000001-0000-0000-0000-000000000000', 'Participante Demo', 0);
SQL
  cat > "$DEV/seed-creds.txt" <<'CREDS'
    cypheranviil  / Cypher2024*    (CypherAnvil)
    meh           / Meh2024*       (MEH)
    ieee          / Ieee2024*      (IEEE)
    aws.umsa      / Aws2024*       (AWS)
    guild         / Guild2024*     (Guild)
    codemiaw      / Codecats2024*  (Codecats)
    pancho        / Cpc2024*       (CPC)
    casdasd       / Ctrldev2024*   (CtrlDev)
    microbot      / Microbot2024*  (Microsoft Umsa)
    trateur010    / Ciasi2024*     (CIASI)
CREDS
fi

# nginx gateway: maps supabase-js's /rest/v1/* onto PostgREST's root.
# In production Supabase's Kong gateway strips /rest/v1; raw PostgREST serves at /.
cat > "$DEV/nginx.conf" <<'NGINX'
server {
    listen 3000;
    server_name _;

    location /auth/v1/ {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*" always;
            add_header Access-Control-Allow-Methods "$http_access_control_request_method" always;
            add_header Access-Control-Allow-Headers "$http_access_control_request_headers" always;
            add_header Access-Control-Max-Age "86400" always;
            return 204;
        }
        proxy_pass http://auth:3001/;
        proxy_pass_request_headers on;
        proxy_set_header Host $host;
        proxy_hide_header Access-Control-Allow-Origin;
        add_header Access-Control-Allow-Origin "*" always;
    }

    location /rest/v1/ {
        if ($request_method = OPTIONS) {
            add_header Access-Control-Allow-Origin "*" always;
            add_header Access-Control-Allow-Methods "$http_access_control_request_method" always;
            add_header Access-Control-Allow-Headers "$http_access_control_request_headers" always;
            add_header Access-Control-Max-Age "86400" always;
            return 204;
        }
        proxy_pass http://rest:3000/;
        proxy_pass_request_headers on;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Headers;
        proxy_hide_header Access-Control-Expose-Headers;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Expose-Headers "Content-Profile" always;
    }
}
NGINX

# Anon key = HS256 JWT (role=anon) signed with the same secret PostgREST knows.
# Needed before the compose write (the auth service passes it to PostgREST too).
ANON_KEY="$(node --input-type=module -e '
import crypto from "node:crypto";
const b64=(b)=>Buffer.from(b).toString("base64url");
const sign=(d)=>crypto.createHmac("sha256", process.env.JWT_SECRET).update(d).digest("base64url");
const h=b64(JSON.stringify({alg:"HS256",typ:"JWT"}));
const p=b64(JSON.stringify({role:"anon",iss:"supabase",iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+31536000}));
console.log(h+"."+p+"."+sign(h+"."+p));
')"

# Docker compose: Postgres + PostgREST. ${VAR:-default} is expansion for
# docker compose, so it is kept literal here.
cat > "$COMPOSE" <<YAML
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "${DB_PORT:-55433}:5432"
    volumes:
      - dev_pgdata:/var/lib/postgresql/data
      - ./sql:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 3s
      timeout: 3s
      retries: 40
  rest:
    image: postgrest/postgrest:v12.2.3
    environment:
      PGRST_DB_URI: postgres://authenticator:authenticator_dev@db:5432/postgres
      PGRST_DB_SCHEMAS: public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: dev_only_super_secret_do_not_use_in_prod
      PGRST_SERVER_PORT: "3000"
    depends_on:
      db:
        condition: service_healthy
  auth:
    image: node:24-alpine
    command: node /srv/auth-mock.mjs
    environment:
      PGRST_URL: http://rest:3000
      ANON_KEY: ${ANON_KEY}
      JWT_SECRET: dev_only_super_secret_do_not_use_in_prod
    volumes:
      - ./auth-mock.mjs:/srv/auth-mock.mjs:ro
    depends_on:
      - rest
  gateway:
    image: nginx:alpine
    ports:
      - "${API_PORT:-3000}:3000"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - rest
      - auth
volumes:
  dev_pgdata:
YAML

# ---------------------------------------------------------------------------
# Bring up docker stack, wait for PostgREST
# ---------------------------------------------------------------------------
echo "▸ starting Postgres + PostgREST + gateway (first run pulls images)..."
docker compose -f "$COMPOSE" up -d

echo "▸ waiting for API at http://localhost:${API_PORT} ..."
ready=""
for _ in $(seq 1 60); do
  if curl -fsS -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
      "http://localhost:${API_PORT}/rest/v1/participants?select=id&limit=1" >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
if [ -z "$ready" ]; then
  echo "✗ API did not become ready. Recent PostgREST logs:" >&2
  docker compose -f "$COMPOSE" logs rest >&2
  exit 1
fi
echo "✓ API ready"

# ---------------------------------------------------------------------------
# Frontend deps + env + dev server
# ---------------------------------------------------------------------------
[ -d "$REPO/node_modules" ] || { echo "▸ npm install..."; (cd "$REPO" && npm install); }

cat > "$REPO/.env.local" <<ENV
VITE_SUPABASE_URL=http://${LAN_IP}:${API_PORT}
VITE_SUPABASE_PUBLISHABLE_DEFAULT_KEY=${ANON_KEY}
ENV

echo
echo "────────────────────────────────────────────────────────"
echo "  Local:         http://localhost:5173"
echo "  Network:       ${APP_URL}"
echo "  API:           http://${LAN_IP}:${API_PORT}"
echo "  DB (optional): localhost:${DB_PORT}"
echo
echo "  Stand demo login (username / password):"
cat "$DEV/seed-creds.txt"
echo "  Demo participant: a0000001-0000-0000-0000-000000000000"
echo "  Remote camera needs HTTPS — use manual codes on other devices."
echo "────────────────────────────────────────────────────────"
echo
echo "  Ctrl-C stops Vite only; backend keeps running (docker compose -f .dev/docker-compose.yml stop)."

cd "$REPO"
# shellcheck disable=SC2068
npm run dev -- --host
