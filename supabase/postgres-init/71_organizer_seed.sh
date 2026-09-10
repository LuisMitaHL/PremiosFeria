#!/bin/sh
# 71_organizer_seed.sh — creates the single organiser account (spec 017).
#
# Runs inside /docker-entrypoint-initdb.d with the container env. SQL cannot
# read environment variables, so this is a shell hook like 11_passwords.sh.
#
# Nobody inside the system can create the account that creates everyone else,
# so it is generated at deployment by deploy-keys.sh and passed in here. Failing
# the boot when it is missing is deliberate: the alternative is an event that
# starts and cannot be administered, discovered on the day.
set -eu
: "${ORGANIZER_USERNAME:?ORGANIZER_USERNAME is required. Run deploy-keys.sh to generate it: without an organiser nobody can create stands, and the event cannot be run.}"
: "${ORGANIZER_PASSWORD:?ORGANIZER_PASSWORD is required. Run deploy-keys.sh to generate it.}"

# The hash is computed inside the database, so the password is never written to
# a file or a log by this script. Cost 12: cost 6 is crackable offline in
# minutes, and this is the most powerful credential in the system.
psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -v username="$ORGANIZER_USERNAME" -v password="$ORGANIZER_PASSWORD" <<'SQL'
INSERT INTO organizers (username, password_hash)
VALUES (btrim(:'username'), crypt(:'password', gen_salt('bf', 12)))
ON CONFLICT (username) DO NOTHING;
SQL

echo "organizer account ready: $ORGANIZER_USERNAME"
