#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.hypernode-update-check.conf"
STATE_FILE="$SCRIPT_DIR/.hypernode-update-check.state"
RUN_CHECK_SCRIPT="$SCRIPT_DIR/run-hypernode-update-check.sh"
WATCHTOWER_IMAGE="containrrr/watchtower:1.7.1"

DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
USER_LOGIN="${USER_LOGIN:-}"
USER_PASSWORD="${USER_PASSWORD:-}"
SERIAL="${SERIAL:-}"
LICENSING_URL="${LICENSING_URL:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"
LOGIN_PERFORMED="false"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker non è disponibile sul sistema." >&2
  exit 1
fi

if [[ ! -f "$RUN_CHECK_SCRIPT" ]]; then
  echo "❌ Script $RUN_CHECK_SCRIPT non trovato." >&2
  exit 1
fi

if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin >/dev/null
  LOGIN_PERFORMED="true"
else
  echo "ℹ️  Nessuna credenziale Docker fornita: salto il login." >&2
fi

trap 'if [[ "$LOGIN_PERFORMED" == "true" ]]; then docker logout >/dev/null 2>&1 || true; fi' EXIT

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$WATCHTOWER_IMAGE" --run-once

if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" && -n "$USER_LOGIN" && -n "$USER_PASSWORD" && -n "$SERIAL" && -n "$LICENSING_URL" ]]; then
  "$RUN_CHECK_SCRIPT" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --user-login="$USER_LOGIN" \
    --user-password="$USER_PASSWORD" \
    --serial="$SERIAL" \
    --licensing-url="$LICENSING_URL" \
    ${INTERVAL_SECONDS:+--interval="${INTERVAL_SECONDS}s"}
else
  rm -f "$STATE_FILE"
  "$RUN_CHECK_SCRIPT" --use-config
fi
