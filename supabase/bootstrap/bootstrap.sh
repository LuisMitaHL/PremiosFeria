#!/bin/sh
# bootstrap.sh — one-shot seed job (restart: "no").
# Waits for Postgres + auth service, then applies SQL files as superuser.
set -eu

echo "bootstrap: waiting for postgres at $PGHOST..."
for _ in $(seq 1 60); do
  if pg_isready -h "$PGHOST" -U "$PGUSER" >/dev/null 2>&1; then break; fi
  sleep 2
done
pg_isready -h "$PGHOST" -U "$PGUSER"

echo "bootstrap: waiting for auth service at $AUTH_URL..."
for _ in $(seq 1 120); do
  if wget -q -O /dev/null "$AUTH_URL" >/dev/null 2>&1; then break; fi
  sleep 2
done
wget -q -O /dev/null "$AUTH_URL"

echo "bootstrap: applying /srv/10_*.sql (always)..."
for f in /srv/10_*.sql; do
  [ -e "$f" ] || continue
  echo "bootstrap: -- $f"
  psql -v ON_ERROR_STOP=1 -f "$f"
done

if [ ! -r /seed/stands.csv ]; then
  echo "bootstrap: no /seed/stands.csv — skipping seed (drop stands.csv + optional rewards.csv in ./seed/ and re-run: docker compose run --rm bootstrap)."
else
  echo "bootstrap: applying /srv/20_*.sql (seed)..."
  if [ -r /seed/rewards.csv ]; then
    HAS_REWARDS=1
  else
    echo "bootstrap: no /seed/rewards.csv — stands only."
    HAS_REWARDS=0
  fi
  for f in /srv/20_*.sql; do
    [ -e "$f" ] || continue
    echo "bootstrap: -- $f"
    psql -v ON_ERROR_STOP=1 -v HAS_REWARDS="$HAS_REWARDS" -f "$f"
  done
fi
echo "bootstrap: done."
