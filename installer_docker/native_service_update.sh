#!/bin/bash

set -euo pipefail

ENV_FILE=""
SERVICE_OVERRIDE=""
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SYSTEM_ENV_DIR="/etc/.hypernode"

usage() {
    cat <<'EOF'
Usage: native_service_update.sh [options]

Options:
  --env-file <path>       Path to env file (default: auto-detect additional env)
  --deploy-branch <name>  Deploy branch for compose files (default: main)
  --service <name>        Override service (camera|auth|event|storage|snapshot|recording|metadata)
  -h, --help              Show this help
EOF
}

detect_compose_cmd() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        echo "❌ Neither 'docker compose' nor 'docker-compose' found."
        exit 1
    fi
}

sync_env_to_system() {
    local src="$1"
    local base_name
    local system_file
    local system_original

    if [[ -z "$src" || ! -f "$src" ]]; then
        echo "⚠️  Env file sorgente non trovato: $src"
        return 1
    fi

    base_name=$(basename "$src")
    system_file="${SYSTEM_ENV_DIR}/${base_name}"
    system_original="${system_file}.original"

    if mkdir -p "$SYSTEM_ENV_DIR" 2>/dev/null; then
        :
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$SYSTEM_ENV_DIR" 2>/dev/null || true
    fi

    if [[ ! -d "$SYSTEM_ENV_DIR" ]]; then
        echo "⚠️  Impossibile creare $SYSTEM_ENV_DIR"
        return 1
    fi

    if [[ ! -f "$system_original" ]]; then
        local original_src="$src"
        if [[ -f "$system_file" ]]; then
            original_src="$system_file"
        fi
        echo "📝 Salvo env originale in: $system_original (source: $original_src)"
        if cp "$original_src" "$system_original" 2>/dev/null; then
            chmod 600 "$system_original" 2>/dev/null || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo cp "$original_src" "$system_original" 2>/dev/null || true
            sudo chmod 600 "$system_original" 2>/dev/null || true
        else
            echo "⚠️  Impossibile scrivere $system_original (permessi)."
        fi
    else
        echo "ℹ️  Env originale già presente: $system_original"
    fi

    echo "📝 Aggiorno env di sistema: $system_file"
    if cp "$src" "$system_file" 2>/dev/null; then
        chmod 600 "$system_file" 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo cp "$src" "$system_file" 2>/dev/null || true
        sudo chmod 600 "$system_file" 2>/dev/null || true
    else
        echo "⚠️  Impossibile scrivere $system_file (permessi)."
    fi
}

require_env_file() {
    if [[ -z "${ENV_FILE:-}" ]]; then
        echo "❌ --env-file is required for native_service_update.sh"
        usage
        exit 1
    fi
}

resolve_service_from_install_option() {
    case "${INSTALL_OPTION:-}" in
        2|9) echo "camera" ;;
        3|10) echo "auth" ;;
        4|11) echo "event" ;;
        5|12) echo "storage" ;;
        6|13) echo "snapshot" ;;
        7) echo "recording" ;;
        15|16) echo "metadata" ;;
        1|8) echo "server" ;;
        *) echo "" ;;
    esac
}

is_valid_service() {
    case "$1" in
        camera|auth|event|storage|snapshot|recording|metadata) return 0 ;;
        *) return 1 ;;
    esac
}

require_nonempty() {
    local var_name="$1"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        echo "❌ Missing required value: $var_name"
        return 1
    fi
}

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
            SERVICE_OVERRIDE="$2"
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

require_env_file

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Env file not found: $ENV_FILE"
    exit 1
fi

sync_env_to_system "$ENV_FILE" || true

set -a
source "$ENV_FILE"
set +a

DB_PORT="${DB_PORT:-27017}"
DOCKER_TAG="${DOCKER_TAG:-latest}"

if [[ -z "${PROCESS_NAME:-}" && -n "${DB_NAME:-}" ]]; then
    PROCESS_NAME="${DB_NAME#database-for-}"
fi

if [[ -z "${DB_NAME:-}" && -n "${PROCESS_NAME:-}" ]]; then
    DB_NAME="database-for-${PROCESS_NAME}"
fi

if [[ -z "${DATABASE_URI:-}" && -n "${DB_NAME:-}" && -n "${PROCESS_NAME:-}" ]]; then
    DATABASE_URI="mongodb://${DB_NAME}:27017/${PROCESS_NAME}"
fi

export DB_PORT DOCKER_TAG PROCESS_NAME DB_NAME DATABASE_URI

SERVICE_NAME=""
if [[ -n "$SERVICE_OVERRIDE" ]]; then
    SERVICE_NAME="$SERVICE_OVERRIDE"
else
    SERVICE_NAME="$(resolve_service_from_install_option)"
fi

if [[ -z "$SERVICE_NAME" ]]; then
    echo "❌ Unable to determine service. Provide --service or ensure INSTALL_OPTION is set in the env file."
    exit 1
fi

if [[ "$SERVICE_NAME" == "server" ]]; then
    echo "❌ INSTALL_OPTION indicates a full suite update. Use native_update.sh instead."
    exit 1
fi

if ! is_valid_service "$SERVICE_NAME"; then
    echo "❌ Invalid service: $SERVICE_NAME"
    usage
    exit 1
fi

if [[ -z "${PROCESS_NAME:-}" ]]; then
    echo "❌ PROCESS_NAME is required for additional services. Check the env file."
    exit 1
fi

case "$SERVICE_NAME" in
    storage)
        require_nonempty STORAGE_PATH
        ;;
    snapshot)
        require_nonempty SNAPSHOT_PATH
        ;;
    recording)
        require_nonempty RECORDING_PATH
        ;;
esac

detect_compose_cmd

ABSOLUTE_PATH="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"
DB_COMPOSE_URL="$ABSOLUTE_PATH/database/docker-compose.yaml"
SERVICE_COMPOSE_URL="$ABSOLUTE_PATH/$SERVICE_NAME/docker-compose.yaml"

TMP_DB_COMPOSE=$(mktemp)
TMP_SERVICE_COMPOSE=$(mktemp)

cleanup_tmp() {
    rm -f "$TMP_DB_COMPOSE" "$TMP_SERVICE_COMPOSE"
}
trap cleanup_tmp EXIT

curl -fsSL "$DB_COMPOSE_URL" -o "$TMP_DB_COMPOSE"
curl -fsSL "$SERVICE_COMPOSE_URL" -o "$TMP_SERVICE_COMPOSE"

pull_images_from_compose "database" -f "$TMP_DB_COMPOSE"
pull_images_from_compose "$SERVICE_NAME" -f "$TMP_SERVICE_COMPOSE"

echo "▶️  Recreate database"
$COMPOSE_CMD -f "$TMP_DB_COMPOSE" up -d --force-recreate --remove-orphans

echo "▶️  Recreate $SERVICE_NAME"
$COMPOSE_CMD -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate --remove-orphans

echo "✅ Update completed for $SERVICE_NAME."
