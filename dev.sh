#!/usr/bin/env bash
# ============================================================================
# dev.sh — spin up a local dev instance of PremiosFeria / Community Quest
#
# Stands up, via Docker:
#   - Postgres 16   (schema + RLS + RPC + seed applied on first init)
#   - PostgREST v12 (REST API; exposed under /rest/v1 via an nginx gateway)
# then runs the Vite dev server against it.
#
# The backend reproduces the app's COMMITTED schema/RLS/RPC (verbatim copies of
# "schema SQL community quest.txt", RLS.txt, RPC.txt), so you develop against
# the same behavior as production — including its (real, insecure) RLS posture.
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

for f in "schema SQL community quest.txt" RLS.txt RPC.txt; do
  [ -f "$REPO/$f" ] || { echo "✗ expected '$REPO/$f' (repo source) not found." >&2; exit 1; }
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

# Schema, RLS, RPC — byte-identical to the repo's committed .txt files.
cp "$REPO/schema SQL community quest.txt" "$SQL/20_schema.sql"
cat > "$SQL/30_grants.sql" <<'SQL'
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
SQL
cp "$REPO/RLS.txt" "$SQL/40_rls.sql"
cp "$REPO/RPC.txt" "$SQL/50_rpc.sql"

# Dev seed: communities get plaintext username/password (the app's loginAdmin
# reads them) so you can log in as any stand. No auth.users / auth_user_id —
# those no longer exist in the HEAD schema.
cat > "$SQL/60_seed.sql" <<'SQL'
DELETE FROM claimed_rewards;
DELETE FROM rewards;
DELETE FROM scans;
DELETE FROM communities;
DELETE FROM participants;

INSERT INTO communities (id, username, password, name, emoji, stand_number, visit_points, activity_points) VALUES
('d0000001-0000-0000-0000-000000000000','cypheranviil@feria.local','Cypher2024*','CypherAnvil','Shield','1',10,25),
('d0000002-0000-0000-0000-000000000000','meh@feria.local','Meh2024*','MEH','Cpu','2',10,25),
('d0000003-0000-0000-0000-000000000000','ieee@feria.local','Ieee2024*','IEEE','RadioReceiver','3',10,25),
('d0000004-0000-0000-0000-000000000000','aws.umsa@feria.local','Aws2024*','AWS','Cloud','4',10,25),
('d0000005-0000-0000-0000-000000000000','guild@feria.local','Guild2024*','Guild','Swords','5',10,25),
('d0000006-0000-0000-0000-000000000000','codemiaw@feria.local','Codecats2024*','Codecats','Cat','6',10,25),
('d0000007-0000-0000-0000-000000000000','pancho@feria.local','Cpc2024*','CPC','Code','7',10,25),
('d0000008-0000-0000-0000-000000000000','casdasd@feria.local','Ctrldev2024*','CtrlDev','Terminal','8',10,25),
('d0000009-0000-0000-0000-000000000000','microbot@feria.local','Microbot2024*','Microsoft Umsa','LayoutGrid','9',10,25),
('d000000a-0000-0000-0000-000000000000','trateur010@feria.local','Ciasi2024*','CIASI','Database','10',10,25);

INSERT INTO rewards (community_id, name, description, cost, stock, emoji) VALUES
('d0000002-0000-0000-0000-000000000000','CuboRubik Dotnet','Premio de MEH',150,1,'Box'),
('d0000004-0000-0000-0000-000000000000','Polera Community Day XL','Premio de la comunidad AWS Umsa',200,1,'Shirt'),
('d0000008-0000-0000-0000-000000000000','1 mes vps','Servicio cloud de CtrlDev',250,1,'Server'),
('d0000009-0000-0000-0000-000000000000','Pelotitas Antiestres','Premio de Microsoft',50,1,'Circle');

INSERT INTO participants (id, name, points) VALUES
('a0000001-0000-0000-0000-000000000000', 'Participante Demo', 0);
SQL

# nginx gateway: maps supabase-js's /rest/v1/* onto PostgREST's root.
# In production Supabase's Kong gateway strips /rest/v1; raw PostgREST serves at /.
cat > "$DEV/nginx.conf" <<'NGINX'
server {
    listen 3000;
    server_name _;

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
  gateway:
    image: nginx:alpine
    ports:
      - "${API_PORT:-3000}:3000"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - rest
volumes:
  dev_pgdata:
YAML

# ---------------------------------------------------------------------------
# Anon key = HS256 JWT (role=anon) signed with the same secret PostgREST knows.
# ---------------------------------------------------------------------------
ANON_KEY="$(node --input-type=module -e '
import crypto from "node:crypto";
const b64=(b)=>Buffer.from(b).toString("base64url");
const sign=(d)=>crypto.createHmac("sha256", process.env.JWT_SECRET).update(d).digest("base64url");
const h=b64(JSON.stringify({alg:"HS256",typ:"JWT"}));
const p=b64(JSON.stringify({role:"anon",iss:"supabase",iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+31536000}));
console.log(h+"."+p+"."+sign(h+"."+p));
')"

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
echo "    meh@feria.local       / Meh2024*"
echo "    aws.umsa@feria.local  / Aws2024*"
echo "    casdasd@feria.local   / Ctrldev2024*"
echo "    (+ 7 more in .dev/sql/60_seed.sql)"
echo "  Demo participant: a0000001-0000-0000-0000-000000000000"
echo "  Remote camera needs HTTPS — use manual codes on other devices."
echo "────────────────────────────────────────────────────────"
echo
echo "  Ctrl-C stops Vite only; backend keeps running (docker compose -f .dev/docker-compose.yml stop)."

cd "$REPO"
# shellcheck disable=SC2068
npm run dev -- --host
