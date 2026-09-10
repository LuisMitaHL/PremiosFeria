#!/bin/sh
# 99_init_complete.sh — first-boot completion marker (fail-loud guard).
#
# Runs after every structural script, 80_column_grants.sql included, so the
# marker means "the database is fully initialised". docker-compose.yml's db
# healthcheck requires it: if a seed aborts on a missing or malformed CSV, the
# container restart would otherwise skip init and serve a schema-only database
# that looks healthy and rejects every login. With this marker the db stays
# unhealthy and the API is never started against an empty fair.
set -eu
: "${PGDATA:?PGDATA is required}"
touch "$PGDATA/.init_complete"
echo "init complete"
