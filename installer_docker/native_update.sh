#!/bin/bash

set -euo pipefail

ENV_FILE="${PWD}/.hypernode-install-env.log"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SERVICE_NAME="server"
TMP_DB_COMPOSE=""
TMP_SERVICE_COMPOSE=""
COMPOSE_PROJECT_NAME=""

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
SERVICE_COMPOSE_URL="$ABSOLUTE_PATH/server/docker-compose.yaml"

detect_compose_project() {
    local candidates=()

    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
        return
    fi

    if [[ "$SERVICE_NAME" == "server" ]]; then
        candidates=(
            recording
            messagebroker
            gateway
            camera
            metadata
            coretrust
            event
            auth
            webserver
            configurator
            portbroker
            snapshot
        )
    else
        candidates=("$SERVICE_NAME")
    fi

    for c in "${candidates[@]}"; do
        if docker inspect "$c" >/dev/null 2>&1; then
            local project
            project=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$c" 2>/dev/null || true)
            if [[ -n "$project" && "$project" != "<no value>" ]]; then
                COMPOSE_PROJECT_NAME="$project"
                return
            fi
        fi
    done
}

cleanup_tmp() {
    rm -f "$TMP_DB_COMPOSE" "$TMP_SERVICE_COMPOSE"
}
trap cleanup_tmp EXIT

TMP_DB_COMPOSE=$(mktemp)
TMP_SERVICE_COMPOSE=$(mktemp)

curl -fsSL "$DB_COMPOSE_URL" -o "$TMP_DB_COMPOSE"
curl -fsSL "$SERVICE_COMPOSE_URL" -o "$TMP_SERVICE_COMPOSE"

detect_compose_project

SERVICE_COMPOSE_ARGS=()
if [[ -n "$COMPOSE_PROJECT_NAME" ]]; then
    SERVICE_COMPOSE_ARGS=(--project-name "$COMPOSE_PROJECT_NAME")
fi

pull_images_from_compose() {
    local label="$1"
    shift
    local images=()

    if ! mapfile -t images < <($COMPOSE_CMD "$@" config --images | awk 'NF'); then
        echo "❌ Failed to resolve images for $label."
        return 1
    fi

    if [[ "${#images[@]}" -eq 0 ]]; then
        echo "❌ No images resolved for $label."
        return 1
    fi

    echo "▶️  Pull $label images"
    for image in "${images[@]}"; do
        echo "   ⬇️  $image"
        docker pull "$image"
    done
}

pull_images_from_compose "database" -f "$TMP_DB_COMPOSE"
pull_images_from_compose "$SERVICE_NAME" "${SERVICE_COMPOSE_ARGS[@]}" -f "$TMP_SERVICE_COMPOSE"

echo "▶️  Recreate database"
$COMPOSE_CMD -f "$TMP_DB_COMPOSE" up -d --force-recreate --remove-orphans

echo "▶️  Recreate $SERVICE_NAME"
$COMPOSE_CMD "${SERVICE_COMPOSE_ARGS[@]}" -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate --remove-orphans

echo "✅ Update completed for $SERVICE_NAME."
