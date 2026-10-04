#!/usr/bin/env bash
# Request ACM certificates interactively and print, for each one, the ARN and
# the CNAME record that must be added at your DNS provider to validate it.
#
# Run this AFTER `terragrunt run --all apply`. Once every certificate is ISSUED,
# put the ARNs it prints into env.hcl (alb_certificate_arn and
# alb_additional_certificate_arns) and apply alb, then services: Terraform owns
# the HTTPS listener from there.
#
# Certificates are deliberately NOT managed by Terraform: DNS validation needs
# records added at an external registrar (there is no Route 53 zone), so an
# apply would block indefinitely waiting for a human.
#
# A wildcard matches exactly ONE label, which is the usual surprise here:
#   *.example.com        covers  dev.example.com
#   *.example.com        does NOT cover  api.dev.example.com
#   *.dev.example.com    covers  api.dev.example.com
# Request whichever names you actually serve; the ALB presents several via SNI.
#
# Usage:
#   ./scripts/request-certs.sh                     # prompts for count + domains
#   ./scripts/request-certs.sh --domain a --domain b   # skip the prompts
#   ./scripts/request-certs.sh --wait              # poll until each is ISSUED
set -uo pipefail

REGION="${AWS_REGION:-eu-central-1}"
WAIT=0
DOMAINS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAINS+=("${2:?--domain needs a value}"); shift 2 ;;
    --region) REGION="${2:?--region needs a value}"; shift 2 ;;
    --wait)   WAIT=1; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------- prompts
if [ "${#DOMAINS[@]}" -eq 0 ]; then
  printf 'How many certificates do you want to request? '
  read -r COUNT
  case "$COUNT" in
    ''|*[!0-9]*) echo "ERROR: enter a whole number." >&2; exit 2 ;;
  esac
  [ "$COUNT" -ge 1 ] || { echo "ERROR: enter a number of 1 or more." >&2; exit 2; }

  echo
  echo "Enter each domain exactly as clients will request it."
  echo "Examples:  api.dev.example.com      a single host"
  echo "           *.dev.example.com        every host one level under dev"
  echo
  i=1
  while [ "$i" -le "$COUNT" ]; do
    printf '  domain %d of %d: ' "$i" "$COUNT"
    read -r D
    D="$(printf '%s' "$D" | tr -d '[:space:]')"
    if [ -z "$D" ]; then
      echo "    empty - try again" >&2
      continue
    fi
    case "$D" in
      *.*) ;;
      *) echo "    '$D' does not look like a domain - try again" >&2; continue ;;
    esac
    DOMAINS+=("$D")
    i=$((i + 1))
  done
  echo
fi

echo "region  : $REGION"
echo "domains : ${#DOMAINS[@]}"
for d in "${DOMAINS[@]}"; do echo "    $d"; done
echo

# ------------------------------------------------------------------- request
declare -a R_DOMAIN=() R_ARN=() R_STATUS=() R_CNAME_NAME=() R_CNAME_VALUE=()
PENDING=0

for DOMAIN in "${DOMAINS[@]}"; do
  echo "=== $DOMAIN ==="

  # Reuse an ISSUED certificate rather than requesting a duplicate.
  ARN=$(aws acm list-certificates --region "$REGION" \
          --query "CertificateSummaryList[?DomainName=='${DOMAIN}'&&Status=='ISSUED'].CertificateArn | [0]" \
          --output text 2>/dev/null)

  if [ -n "$ARN" ] && [ "$ARN" != "None" ]; then
    echo "  reusing ISSUED certificate"
  else
    # A pending certificate from an earlier run is reused too, so re-running
    # after adding DNS records never piles up requests.
    ARN=$(aws acm list-certificates --region "$REGION" \
            --query "CertificateSummaryList[?DomainName=='${DOMAIN}'].CertificateArn | [0]" \
            --output text 2>/dev/null)
    if [ -z "$ARN" ] || [ "$ARN" = "None" ]; then
      echo "  requesting new certificate (DNS validation)..."
      ARN=$(aws acm request-certificate --region "$REGION" \
              --domain-name "$DOMAIN" \
              --validation-method DNS \
              --key-algorithm RSA_2048 \
              --query CertificateArn --output text 2>/dev/null)
      [ -n "$ARN" ] && [ "$ARN" != "None" ] || { echo "  ERROR: request failed" >&2; exit 1; }
      sleep 8   # validation options are not populated immediately
    else
      echo "  reusing existing certificate (not yet issued)"
    fi
  fi

  STATUS=$(aws acm describe-certificate --certificate-arn "$ARN" --region "$REGION" \
            --query 'Certificate.Status' --output text 2>/dev/null)

  if [ "$STATUS" != "ISSUED" ] && [ "$WAIT" -eq 1 ]; then
    printf '  waiting for issuance'
    for _ in $(seq 1 60); do          # up to ~30 minutes
      sleep 30; printf '.'
      STATUS=$(aws acm describe-certificate --certificate-arn "$ARN" --region "$REGION" \
                --query 'Certificate.Status' --output text 2>/dev/null)
      [ "$STATUS" = "ISSUED" ] && break
    done
    echo " $STATUS"
  fi

  # The CNAME ACM wants for this domain. Still present after issuance, because
  # ACM re-checks it at renewal time - so keep the record in place permanently.
  read -r CN CV < <(aws acm describe-certificate --certificate-arn "$ARN" --region "$REGION" \
    --query "Certificate.DomainValidationOptions[?DomainName=='${DOMAIN}'].[ResourceRecord.Name,ResourceRecord.Value] | [0]" \
    --output text 2>/dev/null)
  [ "${CN:-None}" = "None" ] && CN=""
  [ "${CV:-None}" = "None" ] && CV=""

  echo "  status : $STATUS"
  [ "$STATUS" != "ISSUED" ] && PENDING=1

  R_DOMAIN+=("$DOMAIN"); R_ARN+=("$ARN"); R_STATUS+=("$STATUS")
  R_CNAME_NAME+=("${CN:--}"); R_CNAME_VALUE+=("${CV:--}")
  echo
done

# -------------------------------------------------------------------- output
echo "================================================================"
echo " CERTIFICATES"
echo "================================================================"
for i in "${!R_DOMAIN[@]}"; do
  echo
  echo "  domain      : ${R_DOMAIN[$i]}"
  echo "  status      : ${R_STATUS[$i]}"
  echo "  arn         : ${R_ARN[$i]}"
  echo "  CNAME name  : ${R_CNAME_NAME[$i]}"
  echo "  CNAME value : ${R_CNAME_VALUE[$i]}"
done
echo
echo "================================================================"

if [ "$PENDING" -eq 1 ]; then
  echo
  echo "Add the CNAME records above at your DNS provider. ACM validates within"
  echo "minutes of the record resolving. Re-run this script (or use --wait) to"
  echo "check; once every certificate is ISSUED it prints the env.hcl lines."
  exit 1
fi

# The host certificate is the ALB's default (it is the name clients request);
# any wildcard is served alongside it over SNI.
DEFAULT_ARN=""; SNI_ARN=""
for i in "${!R_DOMAIN[@]}"; do
  case "${R_DOMAIN[$i]}" in
    \*.*) [ -z "$SNI_ARN" ] && SNI_ARN="${R_ARN[$i]}" ;;
    *)    [ -z "$DEFAULT_ARN" ] && DEFAULT_ARN="${R_ARN[$i]}" ;;
  esac
done
[ -n "$DEFAULT_ARN" ] || DEFAULT_ARN="${R_ARN[0]}"

echo
echo "All certificates ISSUED. Next step: set these in env.hcl"
echo
echo "  alb_certificate_arn             = \"$DEFAULT_ARN\""
echo "  alb_additional_certificate_arns = [${SNI_ARN:+\"$SNI_ARN\"}]"
echo
echo "then apply alb (HTTPS listener, :80 redirect) and services (the /api/* rule"
echo "moves to :443):"
echo
echo "  ./scripts/tg.sh alb apply && ./scripts/tg.sh services apply"
