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

: "${AWS_PROFILE:?Set AWS_PROFILE to the profile for the target account}"
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

# Use an already-exported value if there is one, otherwise prompt. Without this,
# `read` would clobber an exported variable with whatever was typed - including
# an empty string if the operator just pressed Enter assuming the export was
# picked up, silently storing a blank credential.
#   $1 = variable name, $2 = prompt text, $3 = "hidden" to mask input
prompt_if_unset() {
  local var="$1" prompt="$2" hidden="${3:-}"
  if [ -n "${!var:-}" ]; then
    echo "  using exported ${var}"
    return
  fi
  if [ "$hidden" = "hidden" ]; then
    read -r -s -p "$prompt" "$var"
    echo
  else
    read -r -p "$prompt" "$var"
  fi
  if [ -z "${!var:-}" ]; then
    echo "ERROR: ${var} is empty - refusing to store a blank credential." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 1. Redpanda Cloud API credentials — from https://cloud.redpanda.com,
#    Organization Settings -> API Keys. Used only by Terraform's `redpanda`
#    provider to manage the cluster/topics/users; never read by any service.
# ---------------------------------------------------------------------------
prompt_if_unset REDPANDA_CLIENT_ID     "Redpanda Cloud client_id: "
prompt_if_unset REDPANDA_CLIENT_SECRET "Redpanda Cloud client_secret (hidden): " hidden
ARN=$(create_or_update "${PREFIX}-redpanda-cloud-api" \
  "$(printf '{"client_id":"%s","client_secret":"%s"}' "$REDPANDA_CLIENT_ID" "$REDPANDA_CLIENT_SECRET")")
echo "  -> ${ARN}"
unset REDPANDA_CLIENT_ID REDPANDA_CLIENT_SECRET

# ---------------------------------------------------------------------------
# 2. ClickHouse Cloud API credentials — from https://console.clickhouse.cloud,
#    Organization -> API Keys. Used only by Terraform's `clickhouse` provider.
# ---------------------------------------------------------------------------
# Accepts the CLICKHOUSE_* names (same convention as the old local secrets env
# file) if they are already exported; otherwise prompts.
CH_ORG_ID="${CLICKHOUSE_ORG_ID:-}"
CH_API_KEY="${CLICKHOUSE_CLOUD_API_KEY:-}"
CH_API_SECRET="${CLICKHOUSE_CLOUD_API_SECRET:-}"
prompt_if_unset CH_ORG_ID    "ClickHouse Cloud organization_id: "
prompt_if_unset CH_API_KEY   "ClickHouse Cloud API key: "
prompt_if_unset CH_API_SECRET "ClickHouse Cloud API secret (hidden): " hidden
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
#    monitoring-readonly is not an application service - it is the read-only
#    SCRAM credential for external tooling (Kafka UI, Redpanda Console, kcat).
#    It still needs a secret here because redpanda.hcl fetches a password for
#    EVERY key in service_users, and that map includes it.
SERVICES="api-gateway auth-service user-service search-service feed-service notification-service analytics-service comment-service engagement-service media-service video-processing-service recommendation-service gift-service wallet-service moderation-service report-service audit-service story-service pk-service chat-service monitoring-readonly"

for svc in $SERVICES; do
  PASS=$(random_password)
  ARN=$(create_or_update "${PREFIX}-redpanda-${svc}" "$PASS")
  echo "${svc} -> ${ARN}"
  unset PASS
done

# ---------------------------------------------------------------------------
# 5. Platform-wide shared application secrets.
#
#    JWT_SECRET is the HS256 key every service uses to BOTH mint (auth-service)
#    and verify access tokens - it is symmetric, so all services must receive the
#    identical value. INTERNAL_API_KEY guards internal service-to-service calls
#    (payment / payout / live -> wallet, and the other privileged endpoints).
#
#    Without these, each service falls back to the insecure constants compiled
#    into the backend (DEV_JWT_SECRET / "dev-internal-key"), and refuses to boot
#    entirely once APP_ENV=production.
#
#    NOTE: rotating either value invalidates every access token already issued in
#    this environment, and all services must be redeployed together - a service
#    still holding the old value will reject tokens minted with the new one.
# ---------------------------------------------------------------------------
JWT_SECRET_VALUE=$(random_password)
ARN=$(create_or_update "${PREFIX}-jwt-secret" "$JWT_SECRET_VALUE")
echo "JWT signing secret -> ${ARN}"
unset JWT_SECRET_VALUE

INTERNAL_API_KEY_VALUE=$(random_password)
ARN=$(create_or_update "${PREFIX}-internal-api-key" "$INTERNAL_API_KEY_VALUE")
echo "Internal API key -> ${ARN}"
unset INTERNAL_API_KEY_VALUE

echo
echo "Done. terragrunt plan/apply on redpanda, clickhouse, and secrets now needs no"
echo "manually-exported credentials in this account."
