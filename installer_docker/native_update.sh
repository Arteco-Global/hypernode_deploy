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
SYSTEM_ENV_DIR="/etc/.hypernode"
SYSTEM_ENV_FILE="${SYSTEM_ENV_DIR}/.hypernode-install-env.log"
SYSTEM_ENV_ORIGINAL="${SYSTEM_ENV_DIR}/.hypernode-install-env.log.original"
MACHINE=""
MACHINE_JSON_NAME="machine.json"
MACHINE_FILE_LOCAL="${PWD}/${MACHINE_JSON_NAME}"
MACHINE_FILE_SYSTEM="${SYSTEM_ENV_DIR}/${MACHINE_JSON_NAME}"
MACHINE_FILE=""

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
    local severity="${3:-error}"
    local prefix="❌"
    local parent=""
    local example=""

    if [[ "$severity" == "warn" ]]; then
        prefix="⚠️ "
    fi

    example="$(suggest_mount_path "$var_name")"

    if [[ -z "$value" ]]; then
        echo "$prefix Missing required value: $var_name"
        echo "   Set $var_name to a host directory path such as $example in $ENV_FILE and rerun the update."
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

update_server_suite() {
    local core_services=(
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
    )
    local media_services=()
    local skipped_services=()

    if validate_directory_mount_path "RECORDING_PATH" "${RECORDING_PATH:-}" "warn"; then
        media_services+=(recording)
    else
        skipped_services+=(recording)
    fi

    if validate_directory_mount_path "SNAPSHOT_PATH" "${SNAPSHOT_PATH:-}" "warn"; then
        media_services+=(snapshot)
    else
        skipped_services+=(snapshot)
    fi

    echo "▶️  Recreate server core services"
    $COMPOSE_CMD "${SERVICE_COMPOSE_ARGS[@]}" -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate --remove-orphans "${core_services[@]}"

    if [[ "${#media_services[@]}" -gt 0 ]]; then
        echo "▶️  Recreate optional media services: ${media_services[*]}"
        if ! $COMPOSE_CMD "${SERVICE_COMPOSE_ARGS[@]}" -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate "${media_services[@]}"; then
            echo "⚠️  Optional media services failed to start: ${media_services[*]}"
            echo "   Fix RECORDING_PATH/SNAPSHOT_PATH in $ENV_FILE and rerun the update for those services."
        fi
    fi

    if [[ "${#skipped_services[@]}" -gt 0 ]]; then
        echo "⚠️  Suite update completed without: ${skipped_services[*]}"
        echo "   Fix the related mount path variables in $ENV_FILE before retrying those services."
    fi
}

sync_env_to_system() {
    local src="$1"

    if [[ -z "$src" || ! -f "$src" ]]; then
        echo "⚠️  Env file sorgente non trovato: $src"
        return 1
    fi

    if mkdir -p "$SYSTEM_ENV_DIR" 2>/dev/null; then
        :
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$SYSTEM_ENV_DIR" 2>/dev/null || true
    fi

    if [[ ! -d "$SYSTEM_ENV_DIR" ]]; then
        echo "⚠️  Impossibile creare $SYSTEM_ENV_DIR"
        return 1
    fi

    if [[ ! -f "$SYSTEM_ENV_ORIGINAL" ]]; then
        local original_src="$src"
        if [[ -f "$SYSTEM_ENV_FILE" ]]; then
            original_src="$SYSTEM_ENV_FILE"
        fi
        echo "📝 Salvo env originale in: $SYSTEM_ENV_ORIGINAL (source: $original_src)"
        if cp "$original_src" "$SYSTEM_ENV_ORIGINAL" 2>/dev/null; then
            chmod 600 "$SYSTEM_ENV_ORIGINAL" 2>/dev/null || true
        elif command -v sudo >/dev/null 2>&1; then
            sudo cp "$original_src" "$SYSTEM_ENV_ORIGINAL" 2>/dev/null || true
            sudo chmod 600 "$SYSTEM_ENV_ORIGINAL" 2>/dev/null || true
        else
            echo "⚠️  Impossibile scrivere $SYSTEM_ENV_ORIGINAL (permessi)."
        fi
    else
        echo "ℹ️  Env originale già presente: $SYSTEM_ENV_ORIGINAL"
    fi

    echo "📝 Aggiorno env di sistema: $SYSTEM_ENV_FILE"
    if cp "$src" "$SYSTEM_ENV_FILE" 2>/dev/null; then
        chmod 600 "$SYSTEM_ENV_FILE" 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo cp "$src" "$SYSTEM_ENV_FILE" 2>/dev/null || true
        sudo chmod 600 "$SYSTEM_ENV_FILE" 2>/dev/null || true
    else
        echo "⚠️  Impossibile scrivere $SYSTEM_ENV_FILE (permessi)."
    fi
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

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Env file not found: $ENV_FILE"
    echo "🔄 Provo a ricrearlo con recreate_env_file.sh..."

    RECREATE_SCRIPT="${PWD}/recreate_env_file.sh"
    RECREATE_URL="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/recreate_env_file.sh"
    RESTORED_FILE="${PWD}/_restored_hypernode-install-env.log"

    if [[ ! -f "$RECREATE_SCRIPT" ]]; then
        echo "⬇️  Download recreate_env_file.sh da: $RECREATE_URL"
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$RECREATE_SCRIPT" "$RECREATE_URL" || {
                echo "❌ Download fallito: $RECREATE_URL"
                exit 1
            }
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL "$RECREATE_URL" -o "$RECREATE_SCRIPT" || {
                echo "❌ Download fallito: $RECREATE_URL"
                exit 1
            }
        else
            echo "❌ Né wget né curl disponibili per scaricare recreate_env_file.sh"
            exit 1
        fi
    else
        echo "ℹ️  Script già presente: $RECREATE_SCRIPT"
    fi

    echo "🔧 Rendo eseguibile: $RECREATE_SCRIPT"
    chmod +x "$RECREATE_SCRIPT" 2>/dev/null || true

    echo "▶️  Eseguo recreate_env_file.sh (sovrascriverà l'output se esiste)"
    if ! DEPLOY_BRANCH="$DEPLOY_BRANCH" "$RECREATE_SCRIPT"; then
        echo "❌ Ricostruzione env fallita."
        exit 1
    fi

    if [[ ! -f "$RESTORED_FILE" ]]; then
        echo "❌ File ricostruito non trovato: $RESTORED_FILE"
        exit 1
    fi

    echo "📝 Sovrascrivo env file: $ENV_FILE"
    mv "$RESTORED_FILE" "$ENV_FILE"
    echo "✅ Env file ricreato: $ENV_FILE"
fi

ensure_machine_env_in_file "$ENV_FILE" || true
sync_env_to_system "$ENV_FILE" || true

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
if [[ "$SERVICE_NAME" == "server" ]]; then
    update_server_suite
else
    case "$SERVICE_NAME" in
        recording)
            validate_directory_mount_path "RECORDING_PATH" "${RECORDING_PATH:-}"
            ;;
        snapshot)
            validate_directory_mount_path "SNAPSHOT_PATH" "${SNAPSHOT_PATH:-}"
            ;;
        storage)
            validate_directory_mount_path "STORAGE_PATH" "${STORAGE_PATH:-}"
            ;;
    esac
    $COMPOSE_CMD "${SERVICE_COMPOSE_ARGS[@]}" -f "$TMP_SERVICE_COMPOSE" up -d --force-recreate --remove-orphans
fi

echo "✅ Update completed for $SERVICE_NAME."
