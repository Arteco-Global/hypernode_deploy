#!/bin/bash

set -euo pipefail

ENV_FILE="${PWD}/.hypernode-install-env.log"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SERVICE_NAME=""
TMP_DB_COMPOSE=""
TMP_SERVICE_COMPOSE=""

usage() {
    cat <<'EOF'
Usage: native_update.sh [options]

Options:
  --env-file <path>       Path to env file (default: ./.hypernode-install-env.log)
  --deploy-branch <name>  Deploy branch for compose files (default: main)
  --service <name>        Service to update (server|camera|auth|event|storage|snapshot|recording|metadata)
  -h, --help              Show this help
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --deploy-branch)
            DEPLOY_BRANCH="$2"
            shift 2
            ;;
        --service)
            SERVICE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Env file not found: $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "$SERVICE_NAME" ]]; then
    case "${INSTALL_OPTION:-}" in
        1|8) SERVICE_NAME="server" ;;
        2|9) SERVICE_NAME="camera" ;;
        3|10) SERVICE_NAME="auth" ;;
        4|11) SERVICE_NAME="event" ;;
        5|12) SERVICE_NAME="storage" ;;
        6|13) SERVICE_NAME="snapshot" ;;
        7) SERVICE_NAME="recording" ;;
        15|16) SERVICE_NAME="metadata" ;;
        *)
            echo "❌ Unable to infer service from INSTALL_OPTION."
            echo "   Provide --service <name>."
            exit 1
            ;;
    esac
fi

if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "❌ Neither 'docker compose' nor 'docker-compose' found."
    exit 1
fi

ABSOLUTE_PATH="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"
DB_COMPOSE_URL="$ABSOLUTE_PATH/database/docker-compose.yaml"
SERVICE_COMPOSE_URL="$ABSOLUTE_PATH/$SERVICE_NAME/docker-compose.yaml"

cleanup_tmp() {
    rm -f "$TMP_DB_COMPOSE" "$TMP_SERVICE_COMPOSE"
}
trap cleanup_tmp EXIT

TMP_DB_COMPOSE=$(mktemp)
TMP_SERVICE_COMPOSE=$(mktemp)

curl -sSL "$DB_COMPOSE_URL" -o "$TMP_DB_COMPOSE"
curl -sSL "$SERVICE_COMPOSE_URL" -o "$TMP_SERVICE_COMPOSE"

echo "▶️  Pull database images"
$COMPOSE_CMD -f "$TMP_DB_COMPOSE" pull
echo "▶️  Recreate database"
$COMPOSE_CMD -f "$TMP_DB_COMPOSE" up -d --force-recreate --remove-orphans

echo "▶️  Pull $SERVICE_NAME images"
$COMPOSE_CMD -f "$TMP_SERVICE_COMPOSE" pull
echo "▶️  Recreate $SERVICE_NAME"
$COMPOSE_CMD -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate --remove-orphans

echo "✅ Update completed for $SERVICE_NAME."
