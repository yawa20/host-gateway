#!/usr/bin/env bash
set -euo pipefail

GATEWAY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${GATEWAY_ROOT}/docker-compose.yaml"
DEV_COMPOSE_FILE="${GATEWAY_ROOT}/docker-compose.dev.yaml"
ENV_FILE="${GATEWAY_ROOT}/.env"

compose_gateway() {
  docker compose -f "${COMPOSE_FILE}" --project-directory "${GATEWAY_ROOT}" --env-file "${ENV_FILE}" "$@"
}

compose_gateway_dev() {
  docker compose -f "${DEV_COMPOSE_FILE}" --project-directory "${GATEWAY_ROOT}" --env-file "${ENV_FILE}" "$@"
}

load_gateway_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Missing ${ENV_FILE} — copy host-gateway/.env.example and edit." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  set -a
  source "${ENV_FILE}"
  set +a
  if [[ -z "${YAKOSLOTS_DOMAIN:-}" && -n "${BASE_DOMAIN:-}" ]]; then
    echo "WARNING: BASE_DOMAIN is deprecated for the gateway — set YAKOSLOTS_DOMAIN in ${ENV_FILE}." >&2
    export YAKOSLOTS_DOMAIN="${BASE_DOMAIN}"
  fi
}