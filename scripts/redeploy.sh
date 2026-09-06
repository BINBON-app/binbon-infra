#!/usr/bin/env bash
# Forces a new deployment for ECS services that are not running their desired
# count. A service whose deployment circuit breaker has tripped stays FAILED
# until something asks it to try again - fixing the underlying cause (a missing
# database, a missing secret) does not by itself restart it.
#
# Also reports the image tag each service is configured to run, which is how a
# service still pointing at the ":<name>-replace" placeholder becomes obvious.
#
# Usage:
#   ./scripts/redeploy.sh            # report what would be redeployed
#   ./scripts/redeploy.sh --apply    # force new deployments
set -uo pipefail

ENVIRONMENT="${1:-dev}"
[ "$ENVIRONMENT" = "--apply" ] && ENVIRONMENT=dev
REGION="${AWS_REGION:-eu-central-1}"
CLUSTER="${ECS_CLUSTER:-binbon-${ENVIRONMENT}}"
APPLY=0
for a in "$@"; do [ "$a" = "--apply" ] && APPLY=1; done

mapfile -t ARNS < <(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" \
                      --query 'serviceArns[]' --output text 2>/dev/null | tr '\t' '\n' | sort)
[ "${#ARNS[@]}" -eq 0 ] && { echo "no services in $CLUSTER" >&2; exit 1; }

printf '%-32s %-10s %s\n' SERVICE STATE IMAGE
printf '%s\n' "----------------------------------------------------------------------------------"

targets=()
for ((i = 0; i < ${#ARNS[@]}; i += 10)); do
  batch=("${ARNS[@]:i:10}")
  while IFS=$'\t' read -r name run des td; do
    [ -z "$name" ] && continue
    img=$(aws ecs describe-task-definition --task-definition "$td" --region "$REGION" \
            --query 'taskDefinition.containerDefinitions[0].image' --output text 2>/dev/null)
    tag="${img##*:}"
    if [ "$run" != "$des" ]; then
      state="NEEDS"
      targets+=("$name")
    else
      state="ok"
    fi
    printf '%-32s %-10s %s\n' "$name" "$state" "$tag"
  done < <(aws ecs describe-services --cluster "$CLUSTER" --services "${batch[@]}" \
             --region "$REGION" \
             --query 'services[].[serviceName,runningCount,desiredCount,taskDefinition]' \
             --output text 2>/dev/null)
done

echo
echo "needing redeploy: ${#targets[@]}"
[ "${#targets[@]}" -eq 0 ] && exit 0

if [ "$APPLY" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to force new deployments."
  exit 0
fi

echo
for svc in "${targets[@]}"; do
  if aws ecs update-service --cluster "$CLUSTER" --service "$svc" \
       --force-new-deployment --region "$REGION" >/dev/null 2>&1; then
    echo "  redeploying $svc"
  else
    echo "  FAILED to redeploy $svc"
  fi
done
echo
echo "Deployments started. Re-run scripts/health-check.sh in a few minutes."
