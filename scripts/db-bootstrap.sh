#!/usr/bin/env bash
# Creates the per-service PostgreSQL databases inside the Aurora cluster.
#
# Aurora is provisioned with a single database (aurora_database_name); each
# service expects its own, named in its DATABASE_URL secret. In the original
# account those were created by hand, so a fresh account comes up with services
# crash-looping on: database "binbon_<x>" does not exist.
#
# Runs over the RDS Data API (the cluster has enable_http_endpoint = true), so
# no VPN or direct network access to the private subnet is required.
#
# Database names are read from each service's DATABASE_URL secret, but ONLY the
# database-name path component is ever extracted or printed - never the URL,
# host, user or password.
#
# Usage:
#   ./scripts/db-bootstrap.sh            # dry run: report what is missing
#   ./scripts/db-bootstrap.sh --apply    # create the missing databases
set -uo pipefail

ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-eu-central-1}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

CLUSTER_ARN=$(aws rds describe-db-clusters --region "$REGION" \
  --query "DBClusters[?DBClusterIdentifier=='binbon-${ENVIRONMENT}-aurora'].DBClusterArn" \
  --output text 2>/dev/null)
SECRET_ARN=$(aws rds describe-db-clusters --region "$REGION" \
  --query "DBClusters[?DBClusterIdentifier=='binbon-${ENVIRONMENT}-aurora'].MasterUserSecret.SecretArn" \
  --output text 2>/dev/null)

if [ -z "$CLUSTER_ARN" ] || [ "$CLUSTER_ARN" = "None" ]; then
  echo "ERROR: could not find Aurora cluster binbon-${ENVIRONMENT}-aurora in ${REGION}" >&2
  exit 1
fi
echo "cluster: ${CLUSTER_ARN##*:}"
echo "auth   : cluster master secret (RDS-managed)"
echo

sql() {
  aws rds-data execute-statement --region "$REGION" \
    --resource-arn "$CLUSTER_ARN" --secret-arn "$SECRET_ARN" \
    --database "${2:-postgres}" --sql "$1" --output json 2>&1
}

echo "=== databases that already exist ==="
existing=$(sql "SELECT datname FROM pg_database WHERE datistemplate = false" \
           | grep -oE '"stringValue": "[^"]+"' | cut -d'"' -f4 | sort)
if [ -z "$existing" ]; then
  echo "Could not list databases. Raw response:" >&2
  sql "SELECT datname FROM pg_database WHERE datistemplate = false" >&2
  exit 1
fi
printf '  %s\n' $existing
echo

# Work out the database each service actually wants, from its DATABASE_URL
# secret. Only the trailing path component is extracted.
echo "=== databases required by services ==="
# Each service's connection string lives as a DATABASE_URL_<service> key inside
# the shared "<env>-infra-secrets" entry. Parse it and keep ONLY the database
# name from each URL - the host, user and password are never emitted.
required=$(aws secretsmanager get-secret-value \
             --secret-id "binbon-${ENVIRONMENT}-infra-secrets" --region "$REGION" \
             --query SecretString --output text 2>/dev/null \
           | python3 -c '
import json,sys,re
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for k,v in sorted(d.items()):
    if not k.startswith("DATABASE_URL_"): continue
    m=re.search(r"/([A-Za-z0-9_]+)(?:\?|$)", v or "")
    if m: print("%-30s %s" % (k[len("DATABASE_URL_"):], m.group(1)))
')

if [ -z "$required" ]; then
  echo "  (none found - could not read binbon-${ENVIRONMENT}-infra-secrets)" >&2
  exit 1
fi
printf '  %s\n' "$required"
required=$(printf '%s\n' "$required" | awk '{print $2}')

missing=""
for db in $(printf '%s\n' $required | sort -u); do
  echo "$existing" | grep -qx "$db" || missing="$missing $db"
done

echo
if [ -z "$(printf '%s' "$missing")" ]; then
  echo "Nothing missing - every required database already exists."
  exit 0
fi

echo "=== missing ==="
printf '  %s\n' $missing
echo

if [ "$APPLY" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to create these."
  exit 0
fi

echo "=== creating ==="
fail=0
for db in $missing; do
  # Identifier is constrained to [A-Za-z0-9_] by the extraction above.
  out=$(sql "CREATE DATABASE \"${db}\"")
  if echo "$out" | grep -q '"numberOfRecordsUpdated"'; then
    echo "  created  $db"
  elif echo "$out" | grep -qi 'already exists'; then
    echo "  exists   $db"
  else
    echo "  FAILED   $db"
    echo "$out" | sed 's/^/           /' | head -3
    fail=$((fail+1))
  fi
done

echo
[ "$fail" -eq 0 ] && echo "All databases present." || { echo "$fail failed."; exit 1; }
