#!/usr/bin/env bash
# Prints the non-secret environment variables and the secret KEY NAMES (never
# secret values) of a service's running task definition. Read-only.
#
# Usage: ./scripts/show-task-env.sh <service> [environment]
set -uo pipefail

SVC="${1:?usage: show-task-env.sh <service> [environment]}"
ENVIRONMENT="${2:-dev}"
REGION="${AWS_REGION:-eu-central-1}"
CLUSTER="${ECS_CLUSTER:-binbon-${ENVIRONMENT}}"

TD=$(aws ecs describe-services --cluster "$CLUSTER" --services "${SVC}-${ENVIRONMENT}" \
       --region "$REGION" --query 'services[0].taskDefinition' --output text 2>/dev/null)
[ -z "$TD" ] || [ "$TD" = "None" ] && { echo "service ${SVC}-${ENVIRONMENT} not found" >&2; exit 1; }

echo "service  : ${SVC}-${ENVIRONMENT}"
echo "task def : ${TD##*/}"
echo

aws ecs describe-task-definition --task-definition "$TD" --region "$REGION" --output json 2>/dev/null \
| python3 -c '
import json,sys
c=json.load(sys.stdin)["taskDefinition"]["containerDefinitions"][0]
print("image:", c.get("image"))
print()
print("environment (plain values):")
for e in sorted(c.get("environment") or [], key=lambda x: x["name"]):
    print("  %-28s = %s" % (e["name"], e["value"]))
print()
print("secrets (key names only - values not read):")
for s in sorted(c.get("secrets") or [], key=lambda x: x["name"]):
    print("  %-28s <- %s" % (s["name"], s["valueFrom"].split(":secret:")[-1].rsplit("-",1)[0]))
'
