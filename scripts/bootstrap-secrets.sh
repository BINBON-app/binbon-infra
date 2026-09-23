#!/usr/bin/env bash
# Bootstraps every externally-supplied credential this Terraform stack needs into
# AWS Secrets Manager. Run it before the first `terragrunt apply` of redpanda /
# clickhouse / secrets in an account.
#
# This is a TEMPLATE: it prompts for the account-specific values only you can
# provide (Redpanda Cloud API creds, ClickHouse Cloud API creds), and generates
# fresh random passwords for everything that doesn't need to match anything
# external. It deliberately does NOT contain any real credential - never fill
# this file in with real values and commit it; every value here is supplied
# interactively, at runtime, into Secrets Manager directly.
#
# Terraform reads all of these back live via `run_cmd()` in the .hcl files
# (terragrunt/components/redpanda.hcl, clickhouse.hcl, secrets.hcl) - once this
# script has run, no TF_VAR_*/REDPANDA_CLIENT_ID/etc. env var export is ever
# needed again for those components.
#
# SAFE TO RE-RUN
# --------------
# By default it only CREATES secrets that don't exist yet. An existing secret is
# left exactly as it is and reported. So re-running is how you add the secret for
# a new service: put it in SERVICES below and run the script again.
#
# That default is the point. This script used to overwrite every secret on each
# run, and on an account that is already serving that is an outage:
#
#   redpanda-<service>  Redpanda users are set with password_wo and a static
#                       password_wo_version, so a new value never reaches the
#                       cluster - Secrets Manager and Redpanda disagree and every
#                       Kafka service fails authentication on its next start.
#   clickhouse-admin    the same write-only mechanism; analytics can't connect.
#   jwt-secret          every issued token stops validating; every user is
#                       logged out.
#   internal-api-key    internal calls fail until the whole fleet restarts.
#
# ROTATING (--force)
# ------------------
# --force overwrites existing secrets. It prints those consequences, requires you
# to type the environment prefix to confirm, and refuses to run without a
# terminal to type it in. Rotation is not finished when this script is: see the
# follow-up it prints.
#
# Usage:
#   AWS_PROFILE=<profile> ENVIRONMENT=dev REGION=eu-central-1 ./scripts/bootstrap-secrets.sh
#   ... ./scripts/bootstrap-secrets.sh --force          # rotate existing secrets
set -euo pipefail

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
  esac
done

: "${AWS_PROFILE:?Set AWS_PROFILE to the profile for the target account}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${REGION:-eu-central-1}"
PREFIX="binbon-${ENVIRONMENT}"

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Bootstrapping secrets for ${PREFIX} in account ${ACCOUNT} (region ${REGION})"
if [ "$FORCE" -eq 1 ]; then
  echo "MODE: --force - existing secrets WILL be overwritten"
else
  echo "MODE: create-only - existing secrets are left untouched"
fi
echo

# ---------------------------------------------------------------------------
# --force confirmation, before anything is read or written
# ---------------------------------------------------------------------------
if [ "$FORCE" -eq 1 ]; then
  if [ ! -t 0 ]; then
    echo "ERROR: --force needs an interactive terminal to confirm, and stdin is not one." >&2
    echo "       Rotating live credentials is not something to do unattended." >&2
    exit 1
  fi
  cat >&2 <<EOF
You are about to OVERWRITE existing secrets in ${PREFIX} (account ${ACCOUNT}).
On an environment that is serving, this breaks things until you finish the
rotation by hand:

  redpanda-<service>  every Kafka service fails authentication, until you bump
                      password_wo_version for those users in env.hcl, apply
                      redpanda, and redeploy the services
  clickhouse-admin    analytics can't connect, until you bump the clickhouse
                      password_wo_version, apply clickhouse, and redeploy
  jwt-secret          every user is logged out
  internal-api-key    internal calls fail until every service has redeployed

EOF
  read -r -p "Type the environment prefix (${PREFIX}) to continue: " CONFIRM
  if [ "$CONFIRM" != "$PREFIX" ]; then
    echo "Confirmation did not match - nothing was changed." >&2
    exit 1
  fi
  echo
fi

CREATED=0; KEPT=0; ROTATED=0

# Secret state: "absent", "present", or "deleting" (scheduled for deletion).
secret_state() {
  local name="$1" deleted
  if ! deleted=$(aws secretsmanager describe-secret --secret-id "$name" --region "$REGION" \
                   --query 'DeletedDate' --output text 2>/dev/null); then
    echo absent
  elif [ -n "$deleted" ] && [ "$deleted" != "None" ]; then
    echo deleting
  else
    echo present
  fi
}

# Whether a secret still needs a value supplied - i.e. whether to prompt or
# generate at all. Keeps a re-run from asking for API credentials it will not use.
needs_value() {
  local state
  state=$(secret_state "$1")
  [ "$state" = "absent" ] || { [ "$state" = "present" ] && [ "$FORCE" -eq 1 ]; }
}

# Create a secret, or - only under --force - overwrite it. Never overwrites
# otherwise. Prints the ARN on stdout; progress goes to stderr.
put_secret() {
  local name="$1" value="$2" state
  state=$(secret_state "$name")
  case "$state" in
    absent)
      aws secretsmanager create-secret --name "$name" --secret-string "$value" \
        --region "$REGION" --query ARN --output text
      CREATED=$((CREATED + 1))
      echo "  created   ${name}" >&2
      ;;
    present)
      if [ "$FORCE" -eq 1 ]; then
        aws secretsmanager put-secret-value --secret-id "$name" --secret-string "$value" \
          --region "$REGION" --query ARN --output text
        ROTATED=$((ROTATED + 1))
        echo "  ROTATED   ${name}" >&2
      else
        aws secretsmanager describe-secret --secret-id "$name" --region "$REGION" \
          --query ARN --output text
        KEPT=$((KEPT + 1))
        echo "  exists    ${name}  (left untouched)" >&2
      fi
      ;;
    deleting)
      # create-secret would fail, and silently falling back to an update used to
      # hide exactly this. Surface it instead.
      echo "ERROR: ${name} is scheduled for deletion. Restore it with" >&2
      echo "       aws secretsmanager restore-secret --secret-id ${name}" >&2
      echo "       or wait for the deletion to complete, then re-run." >&2
      exit 1
      ;;
  esac
}

# Skip a secret entirely without prompting or generating, counting it as kept.
keep() {
  KEPT=$((KEPT + 1))
  echo "  exists    $1  (left untouched)" >&2
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
# 1. Redpanda Cloud API credentials - from https://cloud.redpanda.com,
#    Organization Settings -> API Keys. Used only by Terraform's `redpanda`
#    provider to manage the cluster/topics/users; never read by any service.
# ---------------------------------------------------------------------------
NAME="${PREFIX}-redpanda-cloud-api"
if needs_value "$NAME"; then
  prompt_if_unset REDPANDA_CLIENT_ID     "Redpanda Cloud client_id: "
  prompt_if_unset REDPANDA_CLIENT_SECRET "Redpanda Cloud client_secret (hidden): " hidden
  put_secret "$NAME" \
    "$(printf '{"client_id":"%s","client_secret":"%s"}' "$REDPANDA_CLIENT_ID" "$REDPANDA_CLIENT_SECRET")" >/dev/null
  unset REDPANDA_CLIENT_ID REDPANDA_CLIENT_SECRET
else
  keep "$NAME"
fi

# ---------------------------------------------------------------------------
# 2. ClickHouse Cloud API credentials - from https://console.clickhouse.cloud,
#    Organization -> API Keys. Used only by Terraform's `clickhouse` provider.
# ---------------------------------------------------------------------------
# Accepts the CLICKHOUSE_* names (same convention as the old local secrets env
# file) if they are already exported; otherwise prompts.
NAME="${PREFIX}-clickhouse-cloud-api"
if needs_value "$NAME"; then
  CH_ORG_ID="${CLICKHOUSE_ORG_ID:-}"
  CH_API_KEY="${CLICKHOUSE_CLOUD_API_KEY:-}"
  CH_API_SECRET="${CLICKHOUSE_CLOUD_API_SECRET:-}"
  prompt_if_unset CH_ORG_ID     "ClickHouse Cloud organization_id: "
  prompt_if_unset CH_API_KEY    "ClickHouse Cloud API key: "
  prompt_if_unset CH_API_SECRET "ClickHouse Cloud API secret (hidden): " hidden
  put_secret "$NAME" \
    "$(printf '{"org_id":"%s","api_key":"%s","api_secret":"%s"}' "$CH_ORG_ID" "$CH_API_KEY" "$CH_API_SECRET")" >/dev/null
  unset CH_ORG_ID CH_API_KEY CH_API_SECRET
else
  keep "$NAME"
fi

# ---------------------------------------------------------------------------
# 3. ClickHouse admin password - sets the actual service's `default` user
#    password AND is what services read as CLICKHOUSE_PASSWORD. Freshly
#    generated; nothing external it needs to match.
# ---------------------------------------------------------------------------
NAME="${PREFIX}-clickhouse-admin-password"
if needs_value "$NAME"; then
  CH_ADMIN_PASS=$(random_password)
  put_secret "$NAME" "$CH_ADMIN_PASS" >/dev/null
  unset CH_ADMIN_PASS
else
  keep "$NAME"
fi

# ---------------------------------------------------------------------------
# 4. Redpanda per-service SASL passwords - one freshly generated password per
#    Kafka-using service, matching `local.redpanda.service_users` in env.hcl.
#    Add/remove names here if that map ever changes; on an existing account,
#    adding a name and re-running creates just that one.
# ---------------------------------------------------------------------------
#    monitoring-readonly is not an application service - it is the read-only
#    SCRAM credential for external tooling (Kafka UI, Redpanda Console, kcat).
#    It still needs a secret here because redpanda.hcl fetches a password for
#    EVERY key in service_users, and that map includes it.
SERVICES="api-gateway auth-service user-service search-service feed-service notification-service analytics-service comment-service engagement-service media-service video-processing-service recommendation-service gift-service wallet-service moderation-service report-service audit-service story-service pk-service chat-service monitoring-readonly"

for svc in $SERVICES; do
  NAME="${PREFIX}-redpanda-${svc}"
  if needs_value "$NAME"; then
    PASS=$(random_password)
    put_secret "$NAME" "$PASS" >/dev/null
    unset PASS
  else
    keep "$NAME"
  fi
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
#    Rotating either one (--force) invalidates every access token already issued
#    in this environment, and all services must be redeployed together - a
#    service still holding the old value rejects tokens minted with the new one.
# ---------------------------------------------------------------------------
for pair in "jwt-secret" "internal-api-key"; do
  NAME="${PREFIX}-${pair}"
  if needs_value "$NAME"; then
    VALUE=$(random_password)
    put_secret "$NAME" "$VALUE" >/dev/null
    unset VALUE
  else
    keep "$NAME"
  fi
done

echo
echo "created: ${CREATED}   left untouched: ${KEPT}   rotated: ${ROTATED}"

if [ "$ROTATED" -gt 0 ]; then
  cat <<EOF

Rotation is NOT finished. Secrets Manager now holds new values that the rest of
the stack does not know about yet:

  1. For each rotated redpanda-<service> and for clickhouse-admin-password, bump
     password_wo_version in terragrunt/envs/${ENVIRONMENT}/${REGION}/env.hcl -
     a write-only password is only re-sent when its version changes.
  2. Apply redpanda and clickhouse (then secrets, which composes the URLs).
  3. Redeploy every service, together - ECS injects secrets at task start, and
     services on old and new JWT_SECRET / INTERNAL_API_KEY values reject each
     other until all have restarted.
EOF
elif [ "$CREATED" -gt 0 ]; then
  echo
  echo "Done. terragrunt plan/apply on redpanda, clickhouse, and secrets now needs no"
  echo "manually-exported credentials in this account."
else
  echo
  echo "Nothing to do - every secret already exists."
fi
