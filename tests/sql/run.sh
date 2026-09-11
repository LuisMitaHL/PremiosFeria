#!/usr/bin/env bash
# Business-rule tests for Community Quest.
#
# Every game rule lives in Postgres (constitution III, ADR 0004), so these run
# against a real database. There are no mocks: a mock of validate_and_scan would
# prove nothing about the function that actually runs during the fair.
#
# The suite builds a throwaway database from the CANONICAL production scripts on
# every run, so what is tested is exactly what is deployed — never the dev
# variant, which diverges. The dev stack's own database is left untouched.
#
#   ./dev.sh && npm run test:sql                    # against the local stack
#   PSQL_CMD="psql" npm run test:sql                # against any reachable server
#                                                   # (set PGHOST/PGPORT/PGUSER/PGPASSWORD)
set -euo pipefail

cd "$(dirname "$0")/../.."

PSQL_CMD="${PSQL_CMD:-docker compose -f .dev/docker-compose.yml exec -T db psql -U postgres}"
TEST_DB="${TEST_DB:-community_quest_test}"

# 11_passwords.sh is a container entrypoint hook, and 70_seed.sql reads optional
# operator CSVs from /seed, which the test database does not mount. Everything
# else is the real definition and must be loaded verbatim.
SCHEMA_FILES=(
  supabase/postgres-init/10_roles.sql
  supabase/postgres-init/15_extensions.sql
  supabase/postgres-init/20_schema.sql
  supabase/postgres-init/25_auth_columns.sql
  supabase/postgres-init/26_password_hash.sql
  supabase/postgres-init/30_grants.sql
  supabase/postgres-init/35_auth_shim.sql
  supabase/postgres-init/40_rls.sql
  supabase/postgres-init/45_audit.sql
  supabase/postgres-init/50_rpc.sql
  supabase/postgres-init/51_stand_login.sql
  supabase/postgres-init/52_activities.sql
  supabase/postgres-init/53_rewards.sql
  supabase/postgres-init/54_fulfilment.sql
  supabase/postgres-init/55_organizer.sql
  supabase/postgres-init/56_organizer_communities.sql
  supabase/postgres-init/57_registration.sql
  supabase/postgres-init/58_organizer_students.sql
  supabase/postgres-init/59_audit_read.sql
  supabase/postgres-init/60_dashboard.sql
  supabase/postgres-init/61_statistics.sql
  supabase/postgres-init/80_column_grants.sql
)

psql_admin() { $PSQL_CMD -d postgres -v ON_ERROR_STOP=1 --quiet --no-psqlrc "$@"; }
psql_test()  { $PSQL_CMD -d "$TEST_DB" -v ON_ERROR_STOP=1 --quiet --no-psqlrc "$@"; }

if ! psql_admin -c 'SELECT 1' >/dev/null 2>&1; then
  echo "Cannot reach Postgres." >&2
  echo "Start the local stack with ./dev.sh, or set PSQL_CMD to reach another server." >&2
  exit 1
fi

echo "Building ${TEST_DB} from the canonical schema..."
psql_admin -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)" >/dev/null 2>&1
psql_admin -c "CREATE DATABASE ${TEST_DB}" >/dev/null
for f in "${SCHEMA_FILES[@]}"; do
  # NOTICEs about idempotent guards are expected noise; a real failure still
  # trips ON_ERROR_STOP, and only then is the output worth showing.
  if ! load_output="$(psql_test < "$f" 2>&1)"; then
    printf 'Failed to load %s
' "$f" >&2
    printf '%s
' "$load_output" | sed 's/^/    /' >&2
    exit 1
  fi
done
echo

failed=0
passed=0

for test_file in tests/sql/[0-9]*.sql; do
  [ -e "$test_file" ] || continue
  name="$(basename "$test_file")"
  printf '%-44s' "$name"
  if output="$(psql_test < "$test_file" 2>&1)"; then
    printf 'PASS\n'
    passed=$((passed + 1))
  else
    printf 'FAIL\n'
    printf '%s\n\n' "$output" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
done

psql_admin -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)" >/dev/null 2>&1

echo
echo "${passed} passed, ${failed} failed"
[ "$failed" -eq 0 ]
