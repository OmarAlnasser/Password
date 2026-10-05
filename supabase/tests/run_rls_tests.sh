#!/usr/bin/env bash
# Runs the RLS attack suite against a throw-away PostgreSQL database.
# Usage: PGHOST=/tmp/pgvault PGPORT=54329 supabase/tests/run_rls_tests.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="vaultsnap_rls_$$"
psql -U postgres -qc "create database $db"
trap 'psql -U postgres -qc "drop database if exists $db" >/dev/null' EXIT
psql -U postgres -d "$db" -q -v ON_ERROR_STOP=1 -f "$here/supabase_shim.sql" >/dev/null
psql -U postgres -d "$db" -q -v ON_ERROR_STOP=1 -f "$here/../migrations/20261005000000_vaultsnap.sql" >/dev/null
out="$(psql -U postgres -d "$db" -f "$here/rls_attack_tests.sql")"
echo "$out"
echo "$out" | grep -qE "^ +0 \| +[0-9]+$" || { echo "RLS TESTS FAILED"; exit 1; }
