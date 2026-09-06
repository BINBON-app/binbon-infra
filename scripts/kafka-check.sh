#!/usr/bin/env bash
# Checks whether services are genuinely talking to Redpanda.
#
# ECS "healthy" does NOT imply a working broker connection: the events crate's
# warm() call has a 5s timeout and deliberately does not block startup, so a
# producer stays healthy while silently failing to reach the cluster. This
# greps each service's logs for the broker-connection evidence instead.
#
# Read-only. Usage: ./scripts/kafka-check.sh [environment] [minutes]
set -uo pipefail

ENVIRONMENT="${1:-dev}"
MINUTES="${2:-30}"
REGION="${AWS_REGION:-eu-central-1}"
SINCE=$(( ($(date +%s) - MINUTES*60) * 1000 ))

PATTERN='?"SASL" ?"authentication" ?"Authentication" ?"UNSUPPORTED" ?"unsupported" ?"warm-up" ?"timed out" ?"ERROR" ?"failed"'

echo "environment : $ENVIRONMENT"
echo "window      : last ${MINUTES}m"
echo

hits=0
for lg in $(aws logs describe-log-groups --region "$REGION" \
              --log-group-name-prefix "/ecs/binbon-${ENVIRONMENT}/" \
              --query 'logGroups[].logGroupName' --output text 2>/dev/null | tr '\t' '\n' | sort); do
  svc="${lg##*/}"
  out=$(aws logs filter-log-events --log-group-name "$lg" --region "$REGION" \
          --start-time "$SINCE" --filter-pattern "$PATTERN" \
          --query 'events[].message' --output text 2>/dev/null \
        | tr '\t' '\n' | grep -viE '^\s*$' | tail -6)
  if [ -n "$out" ]; then
    echo "--- $svc"
    printf '%s\n' "$out" | sed 's/^/    /'
    hits=$((hits+1))
  fi
done

if [ "$hits" -eq 0 ]; then
  echo "No broker-related log lines found in the last ${MINUTES}m across any service."
  echo "That is ambiguous: it can mean a clean silent connection, or that nothing"
  echo "ever attempted to produce/consume. Check consumer groups on the cluster."
fi
