#!/bin/sh
# bootstrap.sh — one-shot seed job (restart: "no").
# Waits for Postgres + GoTrue (whose startup migrations create auth.*),
# then applies the idempotent seed.sql as superuser.
set -eu

echo "bootstrap: waiting for postgres at $PGHOST..."
for _ in $(seq 1 60); do
  if pg_isready -h "$PGHOST" -U "$PGUSER" >/dev/null 2>&1; then break; fi
  sleep 2
done
pg_isready -h "$PGHOST" -U "$PGUSER"

echo "bootstrap: waiting for GoTrue at $AUTH_URL..."
for _ in $(seq 1 120); do
  if wget -q -O /dev/null "$AUTH_URL" >/dev/null 2>&1; then break; fi
  sleep 2
done
wget -q -O /dev/null "$AUTH_URL"

echo "bootstrap: applying /srv/*.sql in order..."
for f in /srv/*.sql; do
  echo "bootstrap: -- $f"
  psql -v ON_ERROR_STOP=1 -f "$f"
done
echo "bootstrap: done."
