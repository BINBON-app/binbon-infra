#!/usr/bin/env bash
# Restart ECS tasks that started BEFORE the database password last rotated.
#
# WHY THIS EXISTS
# ---------------
# Aurora's master password is RDS-managed and rotates on a schedule. ECS injects
# secrets at TASK START, so a task that has been running since before a rotation
# still holds the old password in its environment. Its existing pooled
# connections keep working - Postgres does not drop live sessions when a
# password changes - but every NEW connection fails with
# "password authentication failed". That is a silent failure: the HTTP listener
# is fine, the ECS health check passes, and the service reports healthy while
# background work that opens fresh connections (the outbox relay, pool growth)
# fails continuously.
#
# This compares each service's running task against the secret's LastRotatedDate
# and forces a new deployment only for the ones that predate it.
#
# IT IS CONDITION-DRIVEN, NOT DATE-DRIVEN, on purpose. AWS rotates within a
# window rather than at a fixed interval - one observed gap was 7d17h, not 7d -
# so a schedule pinned to the expected day drifts out of alignment and
# eventually fires before the rotation it was meant to follow. Running this
# daily is a no-op on the days nothing happened, and self-heals after an
# off-cycle or manual rotation too.
#
# PREREQUISITE: the services must take the password from the RDS secret
# (DB_PASSWORD -> "<rds-secret>:password::"), not from a pre-composed
# DATABASE_URL. Restarting a service that still has a baked URL just restarts it
# into the same stale password. The script checks this and says so.
#
# Usage:
#   ./scripts/restart-stale-db-tasks.sh              # report only
#   ./scripts/restart-stale-db-tasks.sh --apply      # restart the stale ones
#   ./scripts/restart-stale-db-tasks.sh --env dev --apply
set -uo pipefail

ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-eu-central-1}"
APPLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  APPLY=1; shift ;;
    --env)    ENVIRONMENT="${2:?--env needs a value}"; shift 2 ;;
    --region) REGION="${2:?--region needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

CLUSTER="binbon-${ENVIRONMENT}"

# ------------------------------------------------------------------ rotation
MASTER=$(aws rds describe-db-clusters --region "$REGION" \
          --db-cluster-identifier "binbon-${ENVIRONMENT}-aurora" \
          --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text 2>/dev/null)
if [ -z "$MASTER" ] || [ "$MASTER" = "None" ]; then
  echo "ERROR: could not find the Aurora master secret for binbon-${ENVIRONMENT}-aurora" >&2
  exit 1
fi

ROTATED=$(aws secretsmanager describe-secret --secret-id "$MASTER" --region "$REGION" \
           --query 'LastRotatedDate' --output text 2>/dev/null)
if [ -z "$ROTATED" ] || [ "$ROTATED" = "None" ]; then
  echo "The master secret has never rotated - nothing to do."
  exit 0
fi
ROTATED_EPOCH=$(date -d "$ROTATED" +%s 2>/dev/null) || {
  echo "ERROR: could not parse LastRotatedDate '$ROTATED'" >&2; exit 1; }

echo "cluster       : $CLUSTER"
echo "secret        : ${MASTER##*:secret:}"
echo "last rotated  : $ROTATED"
[ "$APPLY" -eq 0 ] && echo "MODE          : report only (pass --apply to restart)"
echo

# ------------------------------------------------------------------- compare
printf '%-32s %-26s %-10s %s\n' SERVICE 'TASK STARTED' 'PW SOURCE' VERDICT
printf '%s\n' "---------------------------------------------------------------------------------------"

stale=(); fresh=0; baked=0; nodb=0

for arn in $(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" \
              --query 'serviceArns[]' --output text 2>/dev/null | tr '\t' '\n' | sort); do
  svc="${arn##*/}"
  [ -z "$svc" ] && continue

  TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" --region "$REGION" \
        --query 'services[0].taskDefinition' --output text 2>/dev/null)

  # How does this service get its password? Only "live" can be fixed by a restart.
  SOURCE=$(aws ecs describe-task-definition --task-definition "$TD" --region "$REGION" \
            --output json 2>/dev/null \
  | python3 -c '
import json,sys
try: c=json.load(sys.stdin)["taskDefinition"]["containerDefinitions"][0]
except Exception: print("?"); raise SystemExit
names=[s["name"] for s in (c.get("secrets") or [])]
print("live" if "DB_PASSWORD" in names else ("baked" if "DATABASE_URL" in names else "none"))
')

  if [ "$SOURCE" = "none" ]; then
    nodb=$((nodb+1)); continue
  fi

  TASK=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$svc" --region "$REGION" \
          --query 'taskArns[0]' --output text 2>/dev/null)
  if [ -z "$TASK" ] || [ "$TASK" = "None" ]; then
    printf '%-32s %-26s %-10s %s\n' "$svc" "-" "$SOURCE" "no running task"
    continue
  fi
  STARTED=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" --region "$REGION" \
             --query 'tasks[0].startedAt' --output text 2>/dev/null)
  STARTED_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)

  if [ "$STARTED_EPOCH" -ge "$ROTATED_EPOCH" ]; then
    verdict="ok"; fresh=$((fresh+1))
  elif [ "$SOURCE" = "baked" ]; then
    # A restart cannot help: the task would come back with the same stale URL.
    verdict="STALE - needs 'secrets' apply first"; baked=$((baked+1))
  else
    verdict="STALE - restart"; stale+=("$svc")
  fi

  printf '%-32s %-26s %-10s %s\n' "$svc" "${STARTED%.*}" "$SOURCE" "$verdict"
done

echo
echo "up to date: $fresh   restartable: ${#stale[@]}   blocked (baked URL): $baked   no database: $nodb"

if [ "$baked" -gt 0 ]; then
  echo
  echo "WARNING: $baked service(s) still take the password from a pre-composed"
  echo "DATABASE_URL. Restarting those changes nothing - they need the secrets"
  echo "component re-applied and then a redeploy. Land the DB_* task definitions"
  echo "to make them restartable."
fi

if [ "${#stale[@]}" -eq 0 ]; then
  echo
  echo "Nothing to restart."
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "Re-run with --apply to restart: ${stale[*]}"
  exit 0
fi

echo
echo "=== restarting ==="
failed=0
for svc in "${stale[@]}"; do
  if aws ecs update-service --cluster "$CLUSTER" --service "$svc" \
       --force-new-deployment --region "$REGION" >/dev/null 2>&1; then
    echo "  restarting $svc"
  else
    echo "  FAILED to restart $svc" >&2
    failed=$((failed+1))
  fi
done

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed restart(s) failed."
  exit 1
fi
echo "Restarts requested. ECS rolls them one at a time; re-run to confirm."
