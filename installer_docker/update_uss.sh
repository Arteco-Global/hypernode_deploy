#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.hypernode-update-check.conf"
STATE_FILE="$SCRIPT_DIR/.hypernode-update-check.state"
RUN_CHECK_SCRIPT="$SCRIPT_DIR/run-hypernode-update-check.sh"
WATCHTOWER_IMAGE="containrrr/watchtower:1.7.1"

DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-}"
USER_LOGIN="${USER_LOGIN:-}"
USER_PASSWORD="${USER_PASSWORD:-}"
SERIAL="${SERIAL:-}"
LICENSING_URL="${LICENSING_URL:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"
LOGIN_PERFORMED="false"
TEMP_CONFIG_DIR=""

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

cleanup() {
  if [[ -n "$TEMP_CONFIG_DIR" && -d "$TEMP_CONFIG_DIR" ]]; then
    rm -rf "$TEMP_CONFIG_DIR"
  fi
  if [[ "$LOGIN_PERFORMED" == "true" ]]; then
    docker logout >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if [[ -z "$DOCKER_CONFIG_DIR" ]]; then
  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    DOCKER_CONFIG_DIR="${DOCKER_CONFIG%/}"
  else
    DOCKER_CONFIG_DIR="$HOME/.docker"
  fi
fi

if [[ "$DOCKER_CONFIG_DIR" == */config.json ]]; then
  DOCKER_CONFIG_DIR="$(dirname "$DOCKER_CONFIG_DIR")"
fi

watchtower_args=(
  --rm
  -v "/var/run/docker.sock:/var/run/docker.sock"
)

if [[ -d "$DOCKER_CONFIG_DIR" && -f "$DOCKER_CONFIG_DIR/config.json" ]]; then
  watchtower_args+=(
    -v "$DOCKER_CONFIG_DIR:/config:ro"
    -e "DOCKER_CONFIG=/config"
  )
elif [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  TEMP_CONFIG_DIR=$(mktemp -d)
  auth_b64=$(printf '%s:%s' "$DOCKER_USERNAME" "$DOCKER_PASSWORD" | base64 | tr -d '\n')
  cat > "$TEMP_CONFIG_DIR/config.json" <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$auth_b64"
    }
  }
}
EOF
  watchtower_args+=(
    -v "$TEMP_CONFIG_DIR:/config:ro"
    -e "DOCKER_CONFIG=/config"
  )
else
  echo "⚠️  Config Docker non trovato in $DOCKER_CONFIG_DIR/config.json e nessuna credenziale disponibile per generarlo: eseguo watchtower senza credenziali." >&2
fi

docker run "${watchtower_args[@]}" "$WATCHTOWER_IMAGE" --run-once

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
