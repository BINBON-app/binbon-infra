#!/usr/bin/env bash
# Read-only post-deploy health check for the Binbon ECS stack.
#
# Reports, per service: desired/running counts, deployment rollout state, the
# image tag actually running, ALB target health, and the stop reason for any
# recently-failed task (which is where image-pull and startup crashes show up).
#
# Makes no changes. Usage:  ./scripts/health-check.sh [environment]
set -uo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-eu-central-1}"
CLUSTER="${ECS_CLUSTER:-binbon-${ENVIRONMENT}}"

echo "cluster : $CLUSTER"
echo "region  : $REGION"
echo "account : $(aws sts get-caller-identity --query Account --output text --region "$REGION" 2>/dev/null)"
echo

mapfile -t ARNS < <(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" \
                      --query 'serviceArns[]' --output text 2>/dev/null | tr '\t' '\n' | sort)

if [ "${#ARNS[@]}" -eq 0 ]; then
  echo "No services found in cluster '$CLUSTER'." >&2
  exit 1
fi
echo "services: ${#ARNS[@]}"
echo

healthy=0; unhealthy=0
declare -a BAD

# describe-services accepts 10 at a time.
for ((i = 0; i < ${#ARNS[@]}; i += 10)); do
  batch=("${ARNS[@]:i:10}")
  aws ecs describe-services --cluster "$CLUSTER" --services "${batch[@]}" \
      --region "$REGION" --output json 2>/dev/null \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for s in d.get("services",[]):
    dep=(s.get("deployments") or [{}])[0]
    state=dep.get("rolloutState","-")
    name=s["serviceName"]; run=s["runningCount"]; des=s["desiredCount"]; pend=s["pendingCount"]
    ok = (run==des and des>0 and state in ("COMPLETED","-"))
    print("\t".join([name,str(des),str(run),str(pend),state,
                     dep.get("taskDefinition","").split("/")[-1],
                     "OK" if ok else "BAD",
                     (dep.get("rolloutStateReason") or "").replace("\t"," ")]))
'
done > /tmp/binbon-health.$$ 2>/dev/null

printf '%-30s %4s %4s %4s  %-12s %-28s %s\n' SERVICE DES RUN PEND ROLLOUT TASKDEF STATUS
printf '%s\n' "-------------------------------------------------------------------------------------------------------"
while IFS=$'\t' read -r name des run pend state taskdef status reason; do
  printf '%-30s %4s %4s %4s  %-12s %-28s %s\n' "$name" "$des" "$run" "$pend" "$state" "$taskdef" "$status"
  if [ "$status" = "BAD" ]; then
    unhealthy=$((unhealthy+1)); BAD+=("$name")
    [ -n "${reason:-}" ] && echo "      reason: $reason"
  else
    healthy=$((healthy+1))
  fi
done < /tmp/binbon-health.$$
rm -f /tmp/binbon-health.$$

echo
echo "healthy: $healthy   unhealthy: $unhealthy"

# For anything unhealthy, the stopped-task reason is the actual diagnosis.
if [ "$unhealthy" -gt 0 ]; then
  echo
  echo "=== stopped-task reasons (most recent per failing service) ==="
  for svc in "${BAD[@]}"; do
    # No --max-items: it appends a pagination token to text output and corrupts the ARN.
    task=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$svc" \
             --desired-status STOPPED --region "$REGION" \
             --query 'taskArns[0]' --output text 2>/dev/null)
    if [ -n "$task" ] && [ "$task" != "None" ]; then
      echo "--- $svc"
      aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task" --region "$REGION" \
        --query 'tasks[0].[stoppedReason,containers[0].reason,containers[0].exitCode]' \
        --output text 2>/dev/null
    else
      echo "--- $svc: no stopped task recorded (likely never started / still pending)"
    fi
  done

  # Stopped tasks are retained only ~1h, so the service event log is the more
  # reliable diagnosis: it keeps the last 100 events including pull failures.
  echo
  echo "=== recent service events (failing services) ==="
  for svc in "${BAD[@]}"; do
    echo "--- $svc"
    aws ecs describe-services --cluster "$CLUSTER" --services "$svc" --region "$REGION" \
      --query 'services[0].events[:4].message' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/    /'
  done

  echo
  echo "=== container logs (failing services, last lines) ==="
  for svc in "${BAD[@]}"; do
    base="${svc%-$ENVIRONMENT}"
    for lg in "/ecs/binbon-${ENVIRONMENT}/${base}" "/ecs/${svc}" "/ecs/binbon-${ENVIRONMENT}-${base}"; do
      stream=$(aws logs describe-log-streams --log-group-name "$lg" --region "$REGION" \
                 --order-by LastEventTime --descending --max-items 1 \
                 --query 'logStreams[0].logStreamName' --output text 2>/dev/null)
      if [ -n "$stream" ] && [ "$stream" != "None" ]; then
        echo "--- $svc  ($lg)"
        aws logs get-log-events --log-group-name "$lg" --log-stream-name "$stream" \
          --region "$REGION" --limit 12 --query 'events[].message' --output text 2>/dev/null \
          | tr '\t' '\n' | tail -12 | sed 's/^/    /'
        break
      fi
    done
  done
fi

echo
echo "=== ALB target health ==="
aws elbv2 describe-target-groups --region "$REGION" \
    --query 'TargetGroups[?starts_with(TargetGroupName,`binbon`)].[TargetGroupName,TargetGroupArn]' \
    --output text 2>/dev/null \
| while read -r tgname tgarn; do
    [ -z "$tgname" ] && continue
    states=$(aws elbv2 describe-target-health --target-group-arn "$tgarn" --region "$REGION" \
               --query 'TargetHealthDescriptions[].TargetHealth.State' --output text 2>/dev/null)
    printf '%-40s %s\n' "$tgname" "${states:-no targets registered}"
  done
