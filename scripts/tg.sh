#!/usr/bin/env bash
# Runs terragrunt inside this repo's dev/eu-central-1 environment and nothing else.
#
# Purpose: give Claude Code (or CI, or a teammate) a single narrow entry point
# for terragrunt. The working directory is fixed below and the only binary this
# script ever executes is terragrunt, so granting permission to run this script
# does not amount to granting arbitrary shell access.
#
# Usage: scripts/tg.sh [<component>] <terragrunt args...>
#   scripts/tg.sh run-all apply
#   scripts/tg.sh foundation plan
#   scripts/tg.sh redpanda apply
#   scripts/tg.sh github-oidc output
set -euo pipefail

# The repo is this script's parent directory, wherever it is checked out.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$REPO/terragrunt"
DEFAULT_UNIT="$ROOT/envs/dev/eu-central-1"
export AWS_PROFILE="${AWS_PROFILE:-default}"

# A first argument naming a directory selects it: either a unit under the default
# environment (e.g. "opensearch") or a path relative to the terragrunt tree
# (e.g. "github-oidc"). Anything else is passed straight through to terragrunt.
dir="$DEFAULT_UNIT"
if [ "$#" -gt 0 ]; then
  if [ -d "$DEFAULT_UNIT/$1" ]; then
    dir="$DEFAULT_UNIT/$1"; shift
  elif [ -d "$ROOT/$1" ]; then
    dir="$ROOT/$1"; shift
  fi
fi

if [ "$#" -eq 0 ]; then
  echo "usage: tg.sh [<component>] <terragrunt args...>" >&2
  exit 2
fi

cd "$dir"
echo "==> $(pwd)"
echo "==> terragrunt $*"
exec terragrunt "$@"
