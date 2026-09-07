#!/usr/bin/env bash
# Apply the HTTPS configuration the ALB needs on top of what Terraform builds.
#
# Run this AFTER `terragrunt run --all apply` and AFTER scripts/request-certs.sh,
# whose output supplies the certificate ARNs this script takes as input.
#
# WHAT TERRAFORM LEAVES BEHIND
# ----------------------------
# The alb module keys everything off certificate_arn, which is null in env.hcl
# because the certificates are requested outside Terraform (DNS validation needs
# records at an external registrar). With it null the module creates:
#   :80   HTTP, default action = fixed-response 503
#   :443  not created at all
# This script converts that into the working configuration:
#   :80   HTTP,  default action = redirect -> HTTPS:443 (301)
#   :443  HTTPS, default certificate + a second certificate over SNI,
#         TLS policy as given, default action = forward -> api-gateway,
#         plus a /api/* rule forwarding to api-gateway
#
# DRIFT: these changes are invisible to Terraform. Re-running
# `terragrunt apply` on the alb component reverts :80 to the 503 fixed-response
# and leaves :443 orphaned. Re-run this script after any such apply.
#
# Usage:
#   ./scripts/configure-alb.sh --default-cert <arn> --sni-cert <arn>
#   ./scripts/configure-alb.sh --default-cert <arn> --dry-run
set -uo pipefail

REGION="${AWS_REGION:-eu-central-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
SSL_POLICY="${SSL_POLICY:-ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09}"
DEFAULT_CERT=""
SNI_CERT=""
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --default-cert) DEFAULT_CERT="${2:?}"; shift 2 ;;
    --sni-cert)     SNI_CERT="${2:?}";     shift 2 ;;
    --ssl-policy)   SSL_POLICY="${2:?}";   shift 2 ;;
    --env)          ENVIRONMENT="${2:?}";  shift 2 ;;
    --region)       REGION="${2:?}";       shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$DEFAULT_CERT" ] || {
  echo "usage: configure-alb.sh --default-cert <arn> [--sni-cert <arn>]" >&2
  echo "  get the ARNs from ./scripts/request-certs.sh" >&2
  exit 2
}

LB_NAME="binbon-${ENVIRONMENT}-alb"
TG_NAME="binbon-${ENVIRONMENT}-api-gateway"

run() { # echo the action, execute unless --dry-run
  if [ "$DRY" -eq 1 ]; then echo "    [dry-run] $*"; return 0; fi
  "$@" >/dev/null 2>&1
}

echo "load balancer : $LB_NAME"
echo "region        : $REGION"
echo "tls policy    : $SSL_POLICY"
echo "default cert  : ${DEFAULT_CERT##*/}"
[ -n "$SNI_CERT" ] && echo "sni cert      : ${SNI_CERT##*/}"
[ "$DRY" -eq 1 ] && echo "MODE          : dry run, nothing will change"
echo

# ------------------------------------------------------------------ discovery
LB=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?LoadBalancerName=='${LB_NAME}'].LoadBalancerArn | [0]" \
      --output text 2>/dev/null)
[ -n "$LB" ] && [ "$LB" != "None" ] || { echo "ERROR: load balancer $LB_NAME not found - run terragrunt apply first" >&2; exit 1; }

TG=$(aws elbv2 describe-target-groups --region "$REGION" --names "$TG_NAME" \
      --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
[ -n "$TG" ] && [ "$TG" != "None" ] || { echo "ERROR: target group $TG_NAME not found - run terragrunt apply first" >&2; exit 1; }
echo "  target group : ${TG##*/}"

for arn in "$DEFAULT_CERT" ${SNI_CERT:+$SNI_CERT}; do
  st=$(aws acm describe-certificate --certificate-arn "$arn" --region "$REGION" \
        --query 'Certificate.Status' --output text 2>/dev/null)
  [ "$st" = "ISSUED" ] || { echo "ERROR: certificate ${arn##*/} is $st, not ISSUED" >&2; exit 1; }
done
echo "  certificates : ISSUED"
echo

# ------------------------------------------------------------- HTTPS listener
echo "=== :443 HTTPS listener ==="
L443=$(aws elbv2 describe-listeners --load-balancer-arn "$LB" --region "$REGION" \
        --query "Listeners[?Port==\`443\`].ListenerArn | [0]" --output text 2>/dev/null)

if [ -n "$L443" ] && [ "$L443" != "None" ]; then
  echo "  exists - updating certificate, policy and default action"
  run aws elbv2 modify-listener --listener-arn "$L443" --region "$REGION" \
        --certificates "CertificateArn=$DEFAULT_CERT" \
        --ssl-policy "$SSL_POLICY" \
        --default-actions "Type=forward,TargetGroupArn=$TG" \
    && echo "    updated" || echo "    FAILED to update" >&2
else
  echo "  creating"
  if [ "$DRY" -eq 1 ]; then
    echo "    [dry-run] create-listener :443 HTTPS -> $TG_NAME"
    L443="<new-listener>"
  else
    L443=$(aws elbv2 create-listener --load-balancer-arn "$LB" --region "$REGION" \
             --protocol HTTPS --port 443 \
             --certificates "CertificateArn=$DEFAULT_CERT" \
             --ssl-policy "$SSL_POLICY" \
             --default-actions "Type=forward,TargetGroupArn=$TG" \
             --query 'Listeners[0].ListenerArn' --output text 2>/dev/null)
    [ -n "$L443" ] && [ "$L443" != "None" ] \
      && echo "    created ${L443##*/}" || { echo "    FAILED to create" >&2; exit 1; }
  fi
fi

# --------------------------------------------------------------- SNI cert
if [ -n "$SNI_CERT" ]; then
  echo
  echo "=== additional (SNI) certificate ==="
  if [ "$DRY" -eq 0 ] && aws elbv2 describe-listener-certificates --listener-arn "$L443" \
       --region "$REGION" --query 'Certificates[].CertificateArn' --output text 2>/dev/null \
     | tr '\t' '\n' | grep -qx "$SNI_CERT"; then
    echo "  already attached"
  else
    run aws elbv2 add-listener-certificates --listener-arn "$L443" --region "$REGION" \
          --certificates "CertificateArn=$SNI_CERT" \
      && echo "  attached ${SNI_CERT##*/}" || echo "  FAILED to attach" >&2
  fi
fi

# ------------------------------------------------------------------- /api/* rule
echo
echo "=== /api/* rule on :443 ==="
if [ "$DRY" -eq 0 ]; then
  EXISTING=$(aws elbv2 describe-rules --listener-arn "$L443" --region "$REGION" \
              --query "Rules[?Conditions[?Field=='path-pattern']].RuleArn | [0]" --output text 2>/dev/null)
else
  EXISTING="None"
fi

if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "  exists - updating target"
  run aws elbv2 modify-rule --rule-arn "$EXISTING" --region "$REGION" \
        --conditions "Field=path-pattern,PathPatternConfig={Values=[/api/*]}" \
        --actions "Type=forward,TargetGroupArn=$TG" \
    && echo "    updated" || echo "    FAILED to update" >&2
else
  echo "  creating at priority 2"
  run aws elbv2 create-rule --listener-arn "$L443" --region "$REGION" \
        --priority 2 \
        --conditions "Field=path-pattern,PathPatternConfig={Values=[/api/*]}" \
        --actions "Type=forward,TargetGroupArn=$TG" \
    && echo "    created" || echo "    FAILED to create" >&2
fi

# ------------------------------------------------------------ :80 redirect
echo
echo "=== :80 redirect to HTTPS ==="
L80=$(aws elbv2 describe-listeners --load-balancer-arn "$LB" --region "$REGION" \
       --query "Listeners[?Port==\`80\`].ListenerArn | [0]" --output text 2>/dev/null)
if [ -n "$L80" ] && [ "$L80" != "None" ]; then
  run aws elbv2 modify-listener --listener-arn "$L80" --region "$REGION" \
        --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
    && echo "  :80 now redirects 301 to HTTPS:443" || echo "  FAILED to set redirect" >&2
else
  echo "  WARNING: no :80 listener found (Terraform should have created it)" >&2
fi

# ---------------------------------------------------------------- verification
echo
echo "=== result ==="
if [ "$DRY" -eq 1 ]; then
  echo "  dry run - nothing changed"
  exit 0
fi
aws elbv2 describe-listeners --load-balancer-arn "$LB" --region "$REGION" \
  --query 'Listeners[].[Port,Protocol,SslPolicy,DefaultActions[0].Type]' --output text 2>/dev/null | sed 's/^/  /'
echo "  certificates on :443:"
aws elbv2 describe-listener-certificates --listener-arn "$L443" --region "$REGION" \
  --query 'Certificates[].CertificateArn' --output text 2>/dev/null | tr '\t' '\n' | sort -u \
| while read -r a; do
    [ -z "$a" ] && continue
    d=$(aws acm describe-certificate --certificate-arn "$a" --region "$REGION" \
          --query 'Certificate.DomainName' --output text 2>/dev/null)
    echo "    $d"
  done

echo
echo "Verify with:  curl -sS -o /dev/null -w '%{http_code}\\n' https://<your-host>/health"
