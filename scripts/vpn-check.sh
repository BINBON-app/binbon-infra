#!/usr/bin/env bash
# Diagnoses the OpenVPN Access Server instance. Read-only.
#
# The Marketplace AMI does NOT self-configure: it expects `ovpn-init` to be run
# once on first boot, and the module supplies no user_data. A freshly applied
# instance therefore runs, passes EC2 health checks, and still refuses every
# connection - the admin UI on :943 never comes up. That is the first thing
# this script checks for.
#
# Usage: ./scripts/vpn-check.sh [environment]
set -uo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${AWS_REGION:-eu-central-1}"

ID=$(aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=binbon-${ENVIRONMENT}-vpn" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null | awk '{print $1}')

if [ -z "$ID" ] || [ "$ID" = "None" ]; then
  echo "No instance tagged binbon-${ENVIRONMENT}-vpn found in ${REGION}." >&2
  exit 1
fi

echo "=== instance ==="
aws ec2 describe-instances --instance-ids "$ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress,LaunchTime]' \
  --output text 2>/dev/null

echo
echo "=== EC2 status checks ==="
aws ec2 describe-instance-status --instance-ids "$ID" --region "$REGION" \
  --query 'InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status]' \
  --output text 2>/dev/null

echo
echo "=== inbound rules (what the world can reach) ==="
# Select the VPN security group by name: the instance also carries the shared
# ECS tasks SG, and taking SecurityGroups[0] blindly reports the wrong rules.
SG=$(aws ec2 describe-instances --instance-ids "$ID" --region "$REGION" \
      --query "Reservations[0].Instances[0].SecurityGroups[?GroupName=='binbon-${ENVIRONMENT}-vpn'].GroupId | [0]" \
      --output text 2>/dev/null)
[ -z "$SG" ] || [ "$SG" = "None" ] && SG=$(aws ec2 describe-instances --instance-ids "$ID" \
      --region "$REGION" --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null)
echo "  security group: $SG"
aws ec2 describe-security-group-rules --region "$REGION" \
  --filters "Name=group-id,Values=$SG" \
  --query 'SecurityGroupRules[?!IsEgress].[IpProtocol,FromPort,ToPort,CidrIpv4,Description]' \
  --output text 2>/dev/null

echo
echo "=== is the subnet actually public? ==="
SUBNET=$(aws ec2 describe-instances --instance-ids "$ID" --region "$REGION" \
          --query 'Reservations[0].Instances[0].SubnetId' --output text 2>/dev/null)
RT=$(aws ec2 describe-route-tables --region "$REGION" \
      --filters "Name=association.subnet-id,Values=$SUBNET" \
      --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' \
      --output text 2>/dev/null)
echo "  subnet $SUBNET default route -> ${RT:-<none>}"
case "$RT" in
  igw-*) echo "  OK: routed via an internet gateway" ;;
  "")    echo "  PROBLEM: no default route - the instance is unreachable from the internet" ;;
  *)     echo "  PROBLEM: default route is not an IGW (${RT}) - inbound will not work" ;;
esac

echo
echo "=== SSM agent (needed to run ovpn-init remotely) ==="
PING=$(aws ssm describe-instance-information --region "$REGION" \
        --filters "Key=InstanceIds,Values=$ID" \
        --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)
echo "  ping status: ${PING:-<not registered>}"

echo
echo "=== has ovpn-init ever run? ==="
if [ "$PING" = "Online" ]; then
  CMD=$(aws ssm send-command --region "$REGION" --instance-ids "$ID" \
          --document-name AWS-RunShellScript \
          --comment "vpn-check: read-only state probe" \
          --parameters 'commands=[
            "systemctl is-active openvpnas 2>/dev/null || echo openvpnas:inactive",
            "test -f /usr/local/openvpn_as/etc/db/config.db && echo config-db:present || echo config-db:MISSING",
            "ss -lntp 2>/dev/null | grep -E \":(943|443|1194)\\b\" || echo no-listeners-on-943-443-1194"
          ]' \
          --query 'Command.CommandId' --output text 2>/dev/null)
  if [ -n "$CMD" ] && [ "$CMD" != "None" ]; then
    for _ in $(seq 1 15); do
      st=$(aws ssm get-command-invocation --region "$REGION" \
            --command-id "$CMD" --instance-id "$ID" \
            --query 'Status' --output text 2>/dev/null)
      case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac
      sleep 2
    done
    aws ssm get-command-invocation --region "$REGION" \
      --command-id "$CMD" --instance-id "$ID" \
      --query 'StandardOutputContent' --output text 2>/dev/null | sed 's/^/  /'
  else
    echo "  could not send SSM command"
  fi
else
  echo "  SSM not available - cannot inspect the host."
  echo "  Note: the OpenVPN Marketplace AMI does not always ship the SSM agent."
fi
