#!/usr/bin/env bash
# Verify the external Docker network exists (created by the Slotify app stack).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

load_gateway_env
NET="${SLOTIFY_NETWORK_NAME:-slotify}"

if docker network inspect "${NET}" >/dev/null 2>&1; then
  echo "Docker network '${NET}' is ready."
  exit 0
fi

echo "ERROR: Docker network '${NET}' does not exist." >&2
echo "Start the Slotify app stack first so it creates the network:" >&2
echo "  cd /opt/slotify && ./deploy/deploy.sh" >&2
echo "Or create it manually (advanced):" >&2
echo "  docker network create ${NET}" >&2
exit 1