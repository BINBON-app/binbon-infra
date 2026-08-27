#!/bin/sh
# Runs apply_clickhouse_migrations_direct.yml from inside the VPC (a
# throwaway task with its own IAM permission to read the infra secret),
# fetching the ClickHouse connection details itself so they never need to
# pass through an operator's terminal/session in plain text.
#
# Usage: run_direct.sh <secret-id> <region> <clickhouse-https-url> <migrations-dir>
set -eu

SECRET_ID="$1"
REGION="$2"
CH_URL="$3"
MIGRATIONS_DIR="$4"

SECRET_JSON="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
CH_USER="$(printf '%s' "$SECRET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["CLICKHOUSE_USER"])')"
CH_PASS="$(printf '%s' "$SECRET_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["CLICKHOUSE_PASSWORD"])')"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/apply_clickhouse_migrations_direct.yml" \
  -e "clickhouse_https_url=$CH_URL" \
  -e "clickhouse_user=$CH_USER" \
  -e "clickhouse_password=$CH_PASS" \
  -e "migrations_dir=$MIGRATIONS_DIR"
