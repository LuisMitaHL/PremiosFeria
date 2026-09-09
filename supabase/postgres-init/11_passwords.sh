#!/bin/sh
# 11_passwords.sh — runs inside /docker-entrypoint-initdb.d with container env.
# SQL files cannot read env vars, so the authenticator password is set here.
set -eu
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"
psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c \
  "ALTER ROLE authenticator WITH PASSWORD '$POSTGRES_PASSWORD';"
