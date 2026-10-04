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
# One wildcard per environment is usually all an ALB needs. Dev uses
# *.dev.binbon.ch, which covers api.dev.binbon.ch and api-gateway.dev.binbon.ch.
# A wildcard matches exactly ONE label, which is the usual surprise here:
#   *.example.com        covers  dev.example.com
#   *.example.com        does NOT cover  api.dev.example.com
#   *.dev.example.com    covers  api.dev.example.com
# Add a second certificate only for a host the first doesn't cover; the ALB
# serves the extras by SNI.
#
# The printed env.hcl lines make the first wildcard (or else the first host)
# the default and list only the OTHERS as additional. Never list the default
# there too: AWS won't remove a listener's default certificate as an extra one,
# so a later change would need a `terragrunt state rm` to untangle.
#
# Keep each validation CNAME in DNS for good: ACM re-checks it at renewal.
#
# Usage:
#   ./scripts/request-certs.sh --domain '*.dev.binbon.ch'   # the usual case
#   ./scripts/request-certs.sh --domain a --domain b        # several
#   ./scripts/request-certs.sh                              # prompts instead
#   ./scripts/request-certs.sh --wait ...                   # poll until ISSUED
set -uo pipefail

REGION="${AWS_REGION:-eu-central-1}"
WAIT=0
DOMAINS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAINS+=("${2:?--domain needs a value}"); shift 2 ;;
    --region) REGION="${2:?--region needs a value}"; shift 2 ;;
    --wait)   WAIT=1; shift ;;
    -h|--help) sed -n '2,/^set -uo/{/^set -uo/d;s/^# \{0,1\}//;p}' "$0"; exit 0 ;;
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
  echo "Enter each domain exactly as clients will request it. One wildcard per"
  echo "environment is usually enough."
  echo "Examples:  *.dev.example.com        every host one level under dev"
  echo "           api.dev.example.com      a single host"
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

# Default: the first wildcard, since it covers the most hosts; else the first
# host. Additional: every OTHER certificate, never the default again (see the
# header), and no ARN twice.
DEFAULT_ARN=""
for i in "${!R_DOMAIN[@]}"; do
  case "${R_DOMAIN[$i]}" in \*.*) DEFAULT_ARN="${R_ARN[$i]}"; break ;; esac
done
[ -n "$DEFAULT_ARN" ] || DEFAULT_ARN="${R_ARN[0]}"

EXTRA=""
for i in "${!R_ARN[@]}"; do
  a="${R_ARN[$i]}"
  [ "$a" = "$DEFAULT_ARN" ] && continue
  case " $EXTRA " in *" \"$a\" "*) continue ;; esac
  EXTRA="${EXTRA:+$EXTRA, }\"$a\""
done

echo
echo "All certificates ISSUED. Next step: set these in env.hcl"
echo
echo "  alb_certificate_arn             = \"$DEFAULT_ARN\""
echo "  alb_additional_certificate_arns = [$EXTRA]"
echo
echo "then apply alb. It builds :443, makes :80 redirect, and swaps or adds"
echo "certificates in place:"
echo
echo "  ./scripts/tg.sh alb apply"
echo
echo "The first time HTTPS is turned on, also apply services: api-gateway's"
echo "/api/* and /health rule moves to :443 with it."
echo
echo "  ./scripts/tg.sh services apply"
