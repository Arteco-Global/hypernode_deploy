#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DUMP_SCRIPT="$SCRIPT_DIR/dump-container-versions.sh"
CHECK_SCRIPT="$SCRIPT_DIR/check-container-updates.sh"
JSON_FILE="$SCRIPT_DIR/container_versions.json"

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
JSON_FILE="$JSON_FILE" "$CHECK_SCRIPT"
