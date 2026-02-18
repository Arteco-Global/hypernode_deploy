#!/bin/bash

set -euo pipefail

ENV_FILE=""
SERVICE_OVERRIDE=""
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SYSTEM_ENV_DIR="/etc/.hypernode"
DOCKER_CMD="docker"

usage() {
    cat <<'EOF'
Usage: native_service_update.sh [options]

Options:
  --env-file <path>       Path to env file (optional; otherwise uses running containers)
  --deploy-branch <name>  Deploy branch for compose files (default: main)
  --service <name>        Override service (camera|auth|event|storage|snapshot|recording|metadata)
  -h, --help              Show this help
EOF
}

detect_docker_cmd() {
    if docker ps >/dev/null 2>&1; then
        DOCKER_CMD="docker"
        return
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo docker ps >/dev/null 2>&1; then
            DOCKER_CMD="sudo docker"
            return
        fi
    fi

    echo "❌ Unable to run docker commands (permission or missing docker)."
    exit 1
}

detect_compose_cmd() {
    if $DOCKER_CMD compose version >/dev/null 2>&1; then
        COMPOSE_CMD="$DOCKER_CMD compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
            COMPOSE_CMD="sudo docker-compose"
        else
            COMPOSE_CMD="docker-compose"
        fi
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
        $DOCKER_CMD pull "$image"
    done
}

get_running_container_names() {
    $DOCKER_CMD ps --format '{{.Names}}'
}

collect_env_files_from_running_containers() {
    local names
    local name
    local instance
    local env_file
    local missing=()
    local found=()
    declare -A seen=()

    if ! names="$(get_running_container_names)"; then
        echo "❌ Unable to list running containers."
        exit 1
    fi

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ "$name" == database-for-* ]] && continue
        if [[ "$name" != *_* ]]; then
            continue
        fi
        instance="${name#*_}"
        if [[ -z "$instance" ]]; then
            continue
        fi
        if [[ -n "${seen[$instance]:-}" ]]; then
            continue
        fi
        seen[$instance]=1

        env_file="$PWD/.hypernode-install-${instance}-env.log"
        if [[ ! -f "$env_file" && -d "$SYSTEM_ENV_DIR" ]]; then
            if [[ -f "$SYSTEM_ENV_DIR/.hypernode-install-${instance}-env.log" ]]; then
                env_file="$SYSTEM_ENV_DIR/.hypernode-install-${instance}-env.log"
            fi
        fi

        if [[ ! -f "$env_file" ]]; then
            missing+=(".hypernode-install-${instance}-env.log")
        else
            found+=("$env_file")
        fi
    done <<< "$names"

    if [[ "${#missing[@]}" -gt 0 ]]; then
        echo "❌ Missing env file(s) for running services:"
        for m in "${missing[@]}"; do
            echo "   - $m"
        done
        exit 1
    fi

    if [[ "${#found[@]}" -eq 0 ]]; then
        echo "❌ No eligible running service containers found."
        exit 1
    fi

    printf '%s\n' "${found[@]}"
}

update_with_env_file() {
    local env_file="$1"
    local service_override="$2"

    if [[ ! -f "$env_file" ]]; then
        echo "❌ Env file not found: $env_file"
        return 1
    fi

    echo "▶️  Using env file: $env_file"
    sync_env_to_system "$env_file" || true

    (
        set -a
        source "$env_file"
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

        local service_name=""
        if [[ -n "$service_override" ]]; then
            service_name="$service_override"
        else
            service_name="$(resolve_service_from_install_option)"
        fi

        if [[ -z "$service_name" ]]; then
            echo "❌ Unable to determine service for $env_file. Provide --service."
            exit 1
        fi

        if [[ "$service_name" == "server" ]]; then
            echo "❌ Env file indicates a full suite update. Use native_update.sh instead."
            exit 1
        fi

        if ! is_valid_service "$service_name"; then
            echo "❌ Invalid service: $service_name"
            exit 1
        fi

        if [[ -z "${PROCESS_NAME:-}" ]]; then
            echo "❌ PROCESS_NAME is required for additional services. Check the env file."
            exit 1
        fi

        case "$service_name" in
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

        local absolute_path="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"
        local db_compose_url="$absolute_path/database/docker-compose.yaml"
        local service_compose_url="$absolute_path/$service_name/docker-compose.yaml"

        local tmp_db_compose
        local tmp_service_compose
        tmp_db_compose=$(mktemp)
        tmp_service_compose=$(mktemp)

        cleanup_tmp() {
            rm -f "$tmp_db_compose" "$tmp_service_compose"
        }
        trap cleanup_tmp EXIT

        curl -fsSL "$db_compose_url" -o "$tmp_db_compose"
        curl -fsSL "$service_compose_url" -o "$tmp_service_compose"

        pull_images_from_compose "database" -f "$tmp_db_compose"
        pull_images_from_compose "$service_name" -f "$tmp_service_compose"

        echo "▶️  Recreate database"
        $COMPOSE_CMD -f "$tmp_db_compose" up -d --force-recreate --remove-orphans

        echo "▶️  Recreate $service_name"
        $COMPOSE_CMD -f "$tmp_service_compose" up -d --force-recreate --remove-orphans

        echo "✅ Update completed for $service_name."
    )
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

detect_docker_cmd
detect_compose_cmd

if [[ -n "$SERVICE_OVERRIDE" && -z "$ENV_FILE" ]]; then
    echo "❌ --service can be used only together with --env-file"
    exit 1
fi

env_files=()
if [[ -n "$ENV_FILE" ]]; then
    env_files=("$ENV_FILE")
else
    while IFS= read -r env_path; do
        [[ -z "$env_path" ]] && continue
        env_files+=("$env_path")
    done < <(collect_env_files_from_running_containers)
fi

for env_path in "${env_files[@]}"; do
    update_with_env_file "$env_path" "$SERVICE_OVERRIDE"
done
