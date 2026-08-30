#!/usr/bin/env bash
# Bootstraps every externally-supplied credential this Terraform stack needs into
# AWS Secrets Manager, for a NEW AWS account/environment. Run this once before
# the first `terragrunt apply` of redpanda / clickhouse / secrets in that account.
#
# This is a TEMPLATE: it prompts for the account-specific values only you can
# provide (Redpanda Cloud API creds, ClickHouse Cloud API creds), and generates
# fresh random passwords for everything that doesn't need to match anything
# external. It deliberately does NOT contain any real credential — never fill
# this file in with real values and commit it; every value here is supplied
# interactively, at runtime, into Secrets Manager directly.
#
# Terraform reads all of these back live via `run_cmd()` in the .hcl files
# (terragrunt/components/redpanda.hcl, clickhouse.hcl, secrets.hcl) - once this
# script has run, no TF_VAR_*/REDPANDA_CLIENT_ID/etc. env var export is ever
# needed again for those components.
#
# Usage: AWS_PROFILE=<your-profile> ENVIRONMENT=dev REGION=eu-central-1 ./scripts/bootstrap-secrets.sh
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to the target account's profile}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${REGION:-eu-central-1}"
PREFIX="binbon-${ENVIRONMENT}"

echo "Bootstrapping secrets for ${PREFIX} in account: $(aws sts get-caller-identity --query Account --output text) (region ${REGION})"
echo

create_or_update() {
  local name="$1" value="$2"
  aws secretsmanager create-secret \
    --name "$name" --secret-string "$value" --region "$REGION" \
    --query ARN --output text 2>/dev/null \
  || aws secretsmanager update-secret \
    --secret-id "$name" --secret-string "$value" --region "$REGION" \
    --query ARN --output text
}

random_password() {
  openssl rand -base64 32 | tr -d '=+/\n' | head -c 40
}

# ---------------------------------------------------------------------------
# 1. Redpanda Cloud API credentials — from https://cloud.redpanda.com,
#    Organization Settings -> API Keys. Used only by Terraform's `redpanda`
#    provider to manage the cluster/topics/users; never read by any service.
# ---------------------------------------------------------------------------
read -r -p "Redpanda Cloud client_id: " REDPANDA_CLIENT_ID
read -r -s -p "Redpanda Cloud client_secret (hidden): " REDPANDA_CLIENT_SECRET
echo
ARN=$(create_or_update "${PREFIX}-redpanda-cloud-api" \
  "$(printf '{"client_id":"%s","client_secret":"%s"}' "$REDPANDA_CLIENT_ID" "$REDPANDA_CLIENT_SECRET")")
echo "  -> ${ARN}"
unset REDPANDA_CLIENT_ID REDPANDA_CLIENT_SECRET

# ---------------------------------------------------------------------------
# 2. ClickHouse Cloud API credentials — from https://console.clickhouse.cloud,
#    Organization -> API Keys. Used only by Terraform's `clickhouse` provider.
# ---------------------------------------------------------------------------
read -r -p "ClickHouse Cloud organization_id: " CH_ORG_ID
read -r -p "ClickHouse Cloud API key: " CH_API_KEY
read -r -s -p "ClickHouse Cloud API secret (hidden): " CH_API_SECRET
echo
ARN=$(create_or_update "${PREFIX}-clickhouse-cloud-api" \
  "$(printf '{"org_id":"%s","api_key":"%s","api_secret":"%s"}' "$CH_ORG_ID" "$CH_API_KEY" "$CH_API_SECRET")")
echo "  -> ${ARN}"
unset CH_ORG_ID CH_API_KEY CH_API_SECRET

# ---------------------------------------------------------------------------
# 3. ClickHouse admin password — sets the actual service's `default` user
#    password AND is what services read as CLICKHOUSE_PASSWORD. Freshly
#    generated; nothing external it needs to match.
# ---------------------------------------------------------------------------
CH_ADMIN_PASS=$(random_password)
ARN=$(create_or_update "${PREFIX}-clickhouse-admin-password" "$CH_ADMIN_PASS")
echo "ClickHouse admin password -> ${ARN}"
unset CH_ADMIN_PASS

# ---------------------------------------------------------------------------
# 4. Redpanda per-service SASL passwords — one freshly generated password per
#    Kafka-using service, matching `local.redpanda.service_users` in env.hcl.
#    Add/remove names here if that map ever changes.
# ---------------------------------------------------------------------------
SERVICES="api-gateway auth-service user-service search-service feed-service notification-service analytics-service comment-service engagement-service media-service video-processing-service recommendation-service gift-service wallet-service moderation-service report-service audit-service story-service pk-service"

for svc in $SERVICES; do
  PASS=$(random_password)
  ARN=$(create_or_update "${PREFIX}-redpanda-${svc}" "$PASS")
  echo "${svc} -> ${ARN}"
  unset PASS
done

echo
echo "Done. terragrunt plan/apply on redpanda, clickhouse, and secrets now needs no"
echo "manually-exported credentials in this account."
