#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

MODE="${1:-prod}"

load_gateway_env
"${SCRIPT_DIR}/ensure-network.sh"

case "${MODE}" in
  prod)
    # deploy-hooks-loopback must be listed: --remove-orphans would drop it
    # if only `gateway` were named. Dev does not start the loopback.
    compose_gateway up -d --remove-orphans gateway deploy-hooks-loopback
  ;;
  dev)
    compose_gateway_dev up -d --remove-orphans gateway
  ;;
  *)
    echo "Usage: $0 [prod|dev]" >&2
    exit 1
  ;;
esac

echo "Gateway is up (${MODE})."