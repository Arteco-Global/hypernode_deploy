#!/bin/bash

set -euo pipefail

ENV_FILE=""
SERVICE_OVERRIDE=""
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SYSTEM_ENV_DIR="/etc/.hypernode"
DOCKER_CMD="docker"
MACHINE=""
MACHINE_JSON_NAME="machine.json"
MACHINE_FILE_LOCAL="${PWD}/${MACHINE_JSON_NAME}"
MACHINE_FILE_SYSTEM="${SYSTEM_ENV_DIR}/${MACHINE_JSON_NAME}"
MACHINE_FILE=""

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

suggest_mount_path() {
    case "$1" in
        RECORDING_PATH) printf "/mnt/data/recording" ;;
        SNAPSHOT_PATH) printf "/mnt/data/snapshot" ;;
        STORAGE_PATH) printf "/mnt/data/storage" ;;
        *) printf "/mnt/data/service" ;;
    esac
}

validate_directory_mount_path() {
    local var_name="$1"
    local value="$2"
    local prefix="❌"
    local parent=""
    local example=""

    example="$(suggest_mount_path "$var_name")"

    if [[ -z "$value" ]]; then
        echo "$prefix Missing required value: $var_name"
        echo "   Set $var_name to a host directory path such as $example in the env file and rerun the update."
        return 1
    fi

    if [[ "$value" != /* ]]; then
        echo "$prefix $var_name must be an absolute host directory path. Current value: $value"
        echo "   Use a mounted filesystem path such as $example, not a relative path."
        return 1
    fi

    case "$value" in
        "/"|"/."|"/.."|"/dev"|"/dev/"*|"/proc"|"/proc/"*|"/sys"|"/sys/"*)
            echo "$prefix $var_name points to a system/device path: $value"
            echo "   Use a mounted filesystem directory such as $example, not a block device like /dev/sdb2."
            return 1
            ;;
    esac

    if [[ -e "$value" && ! -d "$value" ]]; then
        echo "$prefix $var_name must point to a directory. Current value exists but is not a directory: $value"
        return 1
    fi

    parent="$(dirname "$value")"
    if [[ -e "$parent" && ! -d "$parent" ]]; then
        echo "$prefix Parent path for $var_name is not a directory: $parent"
        echo "   Current value: $value"
        return 1
    fi

    return 0
}

generate_machine_id() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
        return
    fi

    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
        return
    fi

    printf '%s-%s-%s\n' "$(date +%s)" "$RANDOM" "$RANDOM"
}

read_machine_id_from_file() {
    local file="$1"
    local value=""

    if [[ -f "$file" ]]; then
        if [[ -r "$file" ]]; then
            value=$(sed -n 's/.*"MACHINE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1)
            if [[ -z "$value" ]]; then
                value=$(sed -n 's/^MACHINE=\(.*\)$/\1/p' "$file" | head -n 1)
            fi
        elif command -v sudo >/dev/null 2>&1; then
            value=$(sudo cat "$file" 2>/dev/null | sed -n 's/.*"MACHINE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            if [[ -z "$value" ]]; then
                value=$(sudo cat "$file" 2>/dev/null | sed -n 's/^MACHINE=\(.*\)$/\1/p' | head -n 1)
            fi
        fi
    fi

    printf '%s' "$value"
}

write_machine_json() {
    local file="$1"
    local id="$2"
    local dir
    local tmp

    dir=$(dirname "$file")
    if mkdir -p "$dir" 2>/dev/null; then
        :
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$dir" 2>/dev/null || true
    fi

    tmp=$(mktemp)
    printf '{\"MACHINE\":\"%s\"}\n' "$id" > "$tmp"

    if cp "$tmp" "$file" 2>/dev/null; then
        chmod 600 "$file" 2>/dev/null || true
        rm -f "$tmp"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo cp "$tmp" "$file" 2>/dev/null; then
            sudo chmod 600 "$file" 2>/dev/null || true
            rm -f "$tmp"
            return 0
        fi
    fi

    rm -f "$tmp"
    return 1
}

ensure_machine_env_in_file() {
    local file="$1"
    local tmp

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi

    tmp=$(mktemp)
    if awk -v machine="$MACHINE" '
        BEGIN {found=0}
        /^MACHINE=/ {found=1; next}
        {print}
        END {printf "MACHINE=%s\n", machine}
    ' "$file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
        chmod 600 "$file" 2>/dev/null || true
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo awk -v machine="$MACHINE" '
            BEGIN {found=0}
            /^MACHINE=/ {found=1; next}
            {print}
            END {printf "MACHINE=%s\n", machine}
        ' "$file" > "$tmp" 2>/dev/null; then
            if sudo cp "$tmp" "$file" 2>/dev/null; then
                sudo chmod 600 "$file" 2>/dev/null || true
                rm -f "$tmp"
                return 0
            fi
        fi
    fi

    rm -f "$tmp"
    return 1
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
    local prefix
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
        if [[ "$name" != *_additional-* ]]; then
            continue
        fi
        prefix="${name%%_*}"
        [[ "$prefix" == "database-for" ]] && continue
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

    ensure_machine_env_in_file "$env_file" || true
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
                validate_directory_mount_path "STORAGE_PATH" "${STORAGE_PATH:-}"
                ;;
            snapshot)
                validate_directory_mount_path "SNAPSHOT_PATH" "${SNAPSHOT_PATH:-}"
                ;;
            recording)
                validate_directory_mount_path "RECORDING_PATH" "${RECORDING_PATH:-}"
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

if [[ -f "$MACHINE_FILE_LOCAL" ]]; then
    MACHINE_FILE="$MACHINE_FILE_LOCAL"
elif [[ -f "$MACHINE_FILE_SYSTEM" ]]; then
    MACHINE_FILE="$MACHINE_FILE_SYSTEM"
fi

if [[ -n "$MACHINE_FILE" ]]; then
    MACHINE="$(read_machine_id_from_file "$MACHINE_FILE")"
    if [[ -z "$MACHINE" && ! -r "$MACHINE_FILE" ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "❌ machine.json is not readable. Run with sudo."
            exit 1
        fi
    fi
fi

if [[ -z "$MACHINE" ]]; then
    MACHINE="$(generate_machine_id)"
    if write_machine_json "$MACHINE_FILE_SYSTEM" "$MACHINE"; then
        MACHINE_FILE="$MACHINE_FILE_SYSTEM"
    else
        write_machine_json "$MACHINE_FILE_LOCAL" "$MACHINE" || true
        MACHINE_FILE="$MACHINE_FILE_LOCAL"
    fi
fi

export MACHINE
if [[ ! -f "$MACHINE_FILE_LOCAL" ]]; then
    write_machine_json "$MACHINE_FILE_LOCAL" "$MACHINE" || true
fi

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
