#!/usr/bin/env bash
# Manage OpenVPN Access Server logins on an environment's VPN host without
# logging in to it, and without a password ever passing through a command line
# or the SSM command history.
#
# How: each password is generated here and stored in Secrets Manager
# (binbon-<env>-vpn-admin, binbon-<env>-vpn-user-<name>). The host is driven over
# SSM Run Command, and the command carries only the secret's NAME: the host
# reads the value itself (its instance role may read binbon-<env>-vpn-* and
# nothing else, modules/vpn) and hands it to sacli.
#
# Commands:
#   admin-password [--rotate]   create (or, with --rotate, regenerate) the
#                               password of the `openvpn` admin for the admin UI
#                               at https://<vpn-ip>:943/admin
#   add <user>                  create a VPN login with a generated password
#   reset <user>                regenerate a login's password
#   password <user|admin>       print a stored password (for you to hand on)
#   profile <user> [file]       save that user's .ovpn profile (default
#                               ./<user>.ovpn, mode 600) to import in OpenVPN
#                               Connect. It holds the user's certificate: keep it
#                               private and out of git.
#   remove <user>               revoke the user's certificates (old profiles stop
#                               working), delete the login, and schedule its
#                               secret for deletion (7-day recovery window)
#   list                        logins on the server
#   info                        the server address and what clients get routed
#
# OpenVPN Connect can also import without a file: Import Profile -> URL ->
# https://<vpn-ip>, then log in with the user and password.
#
# Environment: ENVIRONMENT (default dev), REGION (default eu-central-1),
# AWS_PROFILE (default "default").
#
# Usage:
#   ./scripts/vpn-user.sh admin-password
#   ./scripts/vpn-user.sh add gerges
#   ./scripts/vpn-user.sh password gerges
#   ./scripts/vpn-user.sh profile gerges
#   ./scripts/vpn-user.sh remove gerges
set -euo pipefail

ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${REGION:-eu-central-1}"
export AWS_PROFILE="${AWS_PROFILE:-default}"
PREFIX="binbon-${ENVIRONMENT}"
ADMIN_USER="openvpn"

usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; }
die() { echo "ERROR: $*" >&2; exit 1; }

CMD="${1:-}"; [ $# -gt 0 ] && shift
case "$CMD" in ""|-h|--help|help) usage; exit 0 ;; esac

valid_user() {
  [[ "$1" =~ ^[a-z][a-z0-9._-]{1,31}$ ]] || die "user names are 2-32 chars: lowercase letters, digits, . _ - (got '$1')"
  [ "$1" != "$ADMIN_USER" ] || die "'$ADMIN_USER' is the admin; use admin-password"
}

secret_for() { [ "$1" = admin ] && echo "${PREFIX}-vpn-admin" || echo "${PREFIX}-vpn-user-$1"; }

secret_exists() {
  aws secretsmanager describe-secret --secret-id "$1" --region "$REGION" >/dev/null 2>&1
}

new_password() { openssl rand -base64 36 | tr -d '=+/\n' | head -c 24; }

# Store a fresh password. The value goes through stdin, so it never appears in
# this machine's process list either.
store_password() {   # $1 secret name, $2 create|rotate
  local name="$1" mode="$2"
  if [ "$mode" = create ]; then
    new_password | aws secretsmanager create-secret --name "$name" --region "$REGION" \
      --description "OpenVPN Access Server login, managed by scripts/vpn-user.sh" \
      --secret-string file:///dev/stdin --query Name --output text >/dev/null
  else
    new_password | aws secretsmanager put-secret-value --secret-id "$name" --region "$REGION" \
      --secret-string file:///dev/stdin --query Name --output text >/dev/null
  fi
}

INSTANCE=""
instance() {
  [ -n "$INSTANCE" ] && return
  INSTANCE=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=${PREFIX}-vpn" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
  [ -n "$INSTANCE" ] && [ "$INSTANCE" != "None" ] || die "no running instance tagged ${PREFIX}-vpn in $REGION"
}

# The part that runs on the VPN host, as root, through SSM. Arguments are an
# action, a user and a secret NAME; the password is read from Secrets Manager
# here and only ever handed to sacli.
read -r -d '' AGENT <<'PY' || true
import json, subprocess, sys
import boto3

action, user, secret, region = sys.argv[1:5]
SACLI = "/usr/local/openvpn_as/scripts/sacli"

def sacli(*args, check=True):
    r = subprocess.run([SACLI, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout)[-2000:])
        sys.exit(r.returncode)
    return r.stdout

def password():
    return boto3.client("secretsmanager", region_name=region).get_secret_value(SecretId=secret)["SecretString"]

def users():
    return {k: v for k, v in json.loads(sacli("UserPropGet")).items()
            if k != "__DEFAULT__" and v.get("type") != "group"}

if action == "set-password":
    if user not in users():
        sacli("--user", user, "--key", "type", "--value", "user_connect", "UserPropPut")
    sacli("--user", user, "--new_pass", password(), "SetLocalPassword")
    print(f"password set for {user}")
elif action == "remove":
    if user not in users():
        print(f"{user}: no such login on the server")
        sys.exit(0)
    sacli("--user", user, "RevokeUser", check=False)
    sacli("--user", user, "UserPropDelAll")
    print(f"{user}: certificates revoked, login removed")
elif action == "list":
    for name, props in sorted(users().items()):
        role = "admin" if props.get("prop_superuser") == "true" else "user"
        pw = "password set" if any(k.startswith("pvt_password") for k in props) else "NO password"
        print(f"{name:24} {role:6} {pw}")
elif action == "profile":
    if user not in users():
        sys.stderr.write(f"{user}: no such login on the server\n")
        sys.exit(1)
    # Access Server 3.x takes --user here; --cn is ignored, and the request is
    # then refused as coming from nobody (9403).
    sys.stdout.write(sacli("--user", user, "GetUserlogin"))
elif action == "info":
    cfg = json.loads(sacli("ConfigQuery"))
    nets = [v for k, v in sorted(cfg.items()) if k.startswith("vpn.server.routing.private_network.")]
    print("server address :", cfg.get("host.name"))
    print("routed to you  :", ", ".join(nets) or "(nothing)")
    print("all traffic    :", "yes" if cfg.get("vpn.client.routing.reroute_gw") == "true" else "no, VPC only (split tunnel)")
else:
    sys.stderr.write(f"unknown action {action}\n")
    sys.exit(2)
PY

# Run the agent on the host and print its stdout. SSM keeps the command, which
# holds only the agent's code and the secret's name.
remote() {   # $1 action, $2 user, $3 secret name
  instance
  local b64 line params id status
  b64=$(printf '%s' "$AGENT" | base64 -w0)
  line="echo $b64 | base64 -d > /tmp/vpn-agent.py && python3 /tmp/vpn-agent.py '$1' '$2' '$3' '$REGION'; rc=\$?; rm -f /tmp/vpn-agent.py; exit \$rc"
  # As JSON: the CLI's shorthand syntax can't carry the quotes and ; above.
  params=$(python3 -c 'import json,sys; print(json.dumps({"commands": [sys.argv[1]]}))' "$line")
  id=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
        --document-name AWS-RunShellScript --comment "vpn-user.sh $1 $2" \
        --parameters "$params" --query Command.CommandId --output text)
  aws ssm wait command-executed --region "$REGION" --command-id "$id" --instance-id "$INSTANCE" 2>/dev/null || true
  status=$(aws ssm get-command-invocation --region "$REGION" --command-id "$id" --instance-id "$INSTANCE" --query Status --output text)
  if [ "$status" != "Success" ]; then
    aws ssm get-command-invocation --region "$REGION" --command-id "$id" --instance-id "$INSTANCE" \
      --query StandardErrorContent --output text >&2
    die "$1 failed on the VPN host ($status)"
  fi
  aws ssm get-command-invocation --region "$REGION" --command-id "$id" --instance-id "$INSTANCE" \
    --query StandardOutputContent --output text
}

vpn_ip() {
  instance
  aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}

case "$CMD" in
  admin-password)
    S=$(secret_for admin)
    if secret_exists "$S"; then
      [ "${1:-}" = "--rotate" ] || { echo "$S already exists; it is the admin password. Use --rotate for a new one."; exit 0; }
      store_password "$S" rotate
    else
      store_password "$S" create
    fi
    remote set-password "$ADMIN_USER" "$S"
    echo "Admin UI: https://$(vpn_ip):943/admin  user: $ADMIN_USER"
    echo "Password: ./scripts/vpn-user.sh password admin"
    ;;
  add|reset)
    U="${1:?usage: $0 $CMD <user>}"; valid_user "$U"; S=$(secret_for "$U")
    if [ "$CMD" = add ]; then
      secret_exists "$S" && die "$U already exists ($S); use reset for a new password"
      store_password "$S" create
    else
      secret_exists "$S" || die "$U has no stored password ($S); use add"
      store_password "$S" rotate
    fi
    remote set-password "$U" "$S"
    IP=$(vpn_ip)
    echo
    echo "OpenVPN Connect: Import Profile -> URL -> https://$IP"
    echo "                 then log in as '$U' with the password from:"
    echo "  ./scripts/vpn-user.sh password $U"
    echo "or save a profile file: ./scripts/vpn-user.sh profile $U"
    ;;
  password)
    U="${1:?usage: $0 password <user|admin>}"; S=$(secret_for "$U")
    secret_exists "$S" || die "no stored password for $U ($S)"
    aws secretsmanager get-secret-value --secret-id "$S" --region "$REGION" --query SecretString --output text
    ;;
  profile)
    U="${1:?usage: $0 profile <user> [file]}"; valid_user "$U"; F="${2:-./$U.ovpn}"
    OUT=$(remote profile "$U" "-")
    # SSM returns at most 24,000 characters of output; a cut-off profile would
    # import and then fail to connect, so refuse it.
    [ "${#OUT}" -lt 24000 ] || die "profile too large to fetch over SSM; import by URL instead (https://$(vpn_ip))"
    grep -q '^client' <<<"$OUT" || die "the host did not return a profile"
    ( umask 077; printf '%s\n' "$OUT" > "$F" )
    echo "saved $F (mode 600; on a Windows drive under /mnt the mode is not enforced)."
    echo "Import it in OpenVPN Connect; it asks for $U's password."
    ;;
  remove)
    U="${1:?usage: $0 remove <user>}"; valid_user "$U"; S=$(secret_for "$U")
    remote remove "$U" "-"
    if secret_exists "$S"; then
      aws secretsmanager delete-secret --secret-id "$S" --region "$REGION" --recovery-window-in-days 7 >/dev/null
      echo "$S scheduled for deletion (7 days)"
    fi
    ;;
  list) remote list "-" "-" ;;
  info) remote info "-" "-" ;;
  *) echo "unknown command: $CMD" >&2; usage >&2; exit 2 ;;
esac
