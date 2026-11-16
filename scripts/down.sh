#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

MODE="${1:-prod}"

case "${MODE}" in
  prod)
    compose_gateway down
  ;;
  dev)
    compose_gateway_dev down
  ;;
  *)
    echo "Usage: $0 [prod|dev]" >&2
    exit 1
  ;;
esac

echo "Gateway stopped (${MODE})."