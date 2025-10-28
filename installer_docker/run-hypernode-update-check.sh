#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUMP_SCRIPT="$SCRIPT_DIR/dump-container-versions.sh"
CHECK_SCRIPT="$SCRIPT_DIR/check-container-updates.sh"
JSON_FILE="$SCRIPT_DIR/container_versions.json"

DOCKER_USERNAME=""
DOCKER_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-username=*)
      DOCKER_USERNAME="${1#*=}"
      shift
      ;;
    --docker-password=*)
      DOCKER_PASSWORD="${1#*=}"
      shift
      ;;
    *)
      echo "Opzione non riconosciuta: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$DOCKER_USERNAME" || -z "$DOCKER_PASSWORD" ]]; then
  echo "❌ Specifica --docker-username e --docker-password." >&2
  exit 1
fi

if [ ! -f "$DUMP_SCRIPT" ]; then
  echo "❌ Script $DUMP_SCRIPT non trovato." >&2
  exit 1
fi

if [ ! -f "$CHECK_SCRIPT" ]; then
  echo "❌ Script $CHECK_SCRIPT non trovato." >&2
  exit 1
fi

chmod +x "$DUMP_SCRIPT"
"$DUMP_SCRIPT"

if ! command -v jq >/dev/null 2>&1; then
  echo "ℹ️  jq non trovato, provo ad installarlo tramite apt-get..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y jq
  else
    apt-get update
    apt-get install -y jq
  fi
fi

chmod +x "$CHECK_SCRIPT"
DOCKER_USERNAME="$DOCKER_USERNAME" DOCKER_PASSWORD="$DOCKER_PASSWORD" JSON_FILE="$JSON_FILE" "$CHECK_SCRIPT"
