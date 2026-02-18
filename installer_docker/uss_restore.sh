#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="$(pwd -P)"
DEFAULT_ENV_FILE="${INSTALL_DIR}/.hypernode-install-env.log"
ENV_FILE="$DEFAULT_ENV_FILE"
ENV_FILE_PROVIDED="false"
ENV_FILE_COPIED="false"
DEPLOY_BRANCH="main"
DEPLOY_BRANCH_PROVIDED="false"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
RESTORE_DIR="$(cd "$INSTALL_DIR/.." && pwd -P)/hypernode_deploy"
NATIVE_UPDATE_PATH="${RESTORE_DIR}/native_update.sh"
HYPERNODE_DIR=""
GUI_INSTALL_DIR="/opt/uSee-Service-Suite-Launcher/ussinstaller"
GUI_ENV_FILE="${GUI_INSTALL_DIR}/.hypernode-install-env.log"
SYSTEM_ENV_DIR="/etc/.hypernode"
SYSTEM_ENV_FILE="${SYSTEM_ENV_DIR}/.hypernode-install-env.log"
SYSTEM_ENV_ORIGINAL="${SYSTEM_ENV_DIR}/.hypernode-install-env.log.original"
MACHINE=""
MACHINE_JSON_NAME="machine.json"
MACHINE_FILE_LOCAL="${INSTALL_DIR}/${MACHINE_JSON_NAME}"
MACHINE_FILE_SYSTEM="${SYSTEM_ENV_DIR}/${MACHINE_JSON_NAME}"
MACHINE_FILE=""

ENV_VARS=(
    SSL_PORT
    DOCKER_TAG
    MACHINE
    SERIAL_NUMBER
    SERVER_TIMEZONE
    SERVER_NAME
    ARTECO_GLOBAL_EMAIL
    ARTECO_GLOBAL_PASSWORD
    SERVER_IP_ADDRESS
    CERTIFICATE_PROVIDER_URL
    DNS_PROVIDER_URL
    LICENSE_PROVIDER_URL
    RECORDING_PATH
    RECORDING_DISK_SPACE
    SNAPSHOT_PATH
    SNAPSHOT_DISK_SPACE
    DB_PORT
    DB_NAME
    RMQ
)

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

is_docker_logged_in() {
    local config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    if command -v jq >/dev/null 2>&1; then
        if jq -e '.auths and ( .auths | length > 0 )' "$config" >/dev/null 2>&1; then
            return 0
        fi
        if jq -e '.credsStore or (.credHelpers | length > 0)' "$config" >/dev/null 2>&1; then
            return 0
        fi
    else
        if grep -q '"auth"[[:space:]]*:' "$config"; then
            return 0
        fi
        if grep -q '"credsStore"[[:space:]]*:' "$config" || grep -q '"credHelpers"[[:space:]]*:' "$config"; then
            return 0
        fi
    fi

    return 1
}

is_interactive() {
    [[ -t 0 && -t 1 ]]
}

find_hypernode_dir() {
    local parent search_paths=(
        "$SCRIPT_DIR/.."
        "/Users"
        "/home"
        "/root"
        "/opt"
        "/usr/local"
        "/var"
        "/"
    )

    parent="$(cd "$SCRIPT_DIR/.." && pwd -P)"
    if [[ "$(basename "$parent")" == "hypernode_deploy" ]]; then
        HYPERNODE_DIR="$parent"
        return 0
    fi

    local base path
    for base in "${search_paths[@]}"; do
        [[ -d "$base" ]] || continue
        while IFS= read -r path; do
            HYPERNODE_DIR="$path"
            return 0
        done < <(find "$base" -type d -name hypernode_deploy 2>/dev/null || true)
    done

    return 1
}

prompt_var() {
    local var_name="$1"
    local prompt="$2"
    local default_value="${3:-}"
    local secret="${4:-false}"
    local input

    while true; do
        if [[ "$secret" == "true" ]]; then
            if [[ -n "$default_value" ]]; then
                read -r -s -p "${prompt} [${default_value}]: " input
            else
                read -r -s -p "${prompt}: " input
            fi
            echo
        else
            if [[ -n "$default_value" ]]; then
                read -r -p "${prompt} [${default_value}]: " input
            else
                read -r -p "${prompt}: " input
            fi
        fi

        if [[ -z "$input" && -n "$default_value" ]]; then
            input="$default_value"
        fi

        if [[ -n "$input" ]]; then
            break
        fi

        echo "Value required."
    done

    printf -v "$var_name" '%s' "$input"
}

write_env_file() {
    local tmp_file
    tmp_file=$(mktemp)
    {
        for var_name in "${ENV_VARS[@]}"; do
            if [[ -z "${!var_name+x}" ]]; then
                printf '%s=\n' "$var_name"
            else
                printf '%s=%q\n' "$var_name" "${!var_name}"
            fi
        done
    } > "$tmp_file"

    mv "$tmp_file" "$DEFAULT_ENV_FILE"
    chmod 600 "$DEFAULT_ENV_FILE" 2>/dev/null || true
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

prompt_env_vars() {
    if ! is_interactive; then
        echo "❌ Env file not found and no interactive input available."
        exit 1
    fi

    prompt_var "SSL_PORT" "SSL_PORT" "10446"
    prompt_var "DOCKER_TAG" "DOCKER_TAG" "staging"
    prompt_var "SERIAL_NUMBER" "SERIAL_NUMBER"
    prompt_var "SERVER_TIMEZONE" "SERVER_TIMEZONE" "Europe/Rome"
    prompt_var "SERVER_NAME" "SERVER_NAME"
    prompt_var "ARTECO_GLOBAL_EMAIL" "ARTECO_GLOBAL_EMAIL"
    prompt_var "ARTECO_GLOBAL_PASSWORD" "ARTECO_GLOBAL_PASSWORD" "" "true"
    prompt_var "SERVER_IP_ADDRESS" "SERVER_IP_ADDRESS"
    prompt_var "CERTIFICATE_PROVIDER_URL" "CERTIFICATE_PROVIDER_URL" "https://urkuhpucyi.execute-api.eu-central-1.amazonaws.com/Cert/renew_hypernode"
    prompt_var "DNS_PROVIDER_URL" "DNS_PROVIDER_URL" "https://oxkqg67wjd.execute-api.eu-central-1.amazonaws.com/dyndns/update_hypernode"
    prompt_var "LICENSE_PROVIDER_URL" "LICENSE_PROVIDER_URL" "https://giz0827jc3.execute-api.eu-central-1.amazonaws.com/en/wp-json/sso-provider/login"
    prompt_var "RECORDING_PATH" "RECORDING_PATH" "/recording"
    prompt_var "RECORDING_DISK_SPACE" "RECORDING_DISK_SPACE"
    prompt_var "SNAPSHOT_PATH" "SNAPSHOT_PATH" "/snapshot"
    prompt_var "SNAPSHOT_DISK_SPACE" "SNAPSHOT_DISK_SPACE"
    prompt_var "DB_PORT" "DB_PORT" "27017"
    prompt_var "DB_NAME" "DB_NAME" "uss_database"
    prompt_var "RMQ" "RMQ" "amqp://hypernode:hypernode@messagebroker:5672"

    write_env_file
}

resolve_env_file() {
    local candidate=""

    if [[ "$ENV_FILE_PROVIDED" == "true" ]]; then
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "❌ Env file not found: $ENV_FILE"
            exit 1
        fi
        return
    fi

    if [[ -f "$DEFAULT_ENV_FILE" ]]; then
        echo "ℹ️  Using env file from: $DEFAULT_ENV_FILE"
        ENV_FILE="$DEFAULT_ENV_FILE"
        return
    fi

    candidate="${INSTALL_DIR}/../hypernode_deploy/.hypernode-install-env.log"
    if [[ -f "$candidate" ]]; then
        echo "ℹ️  Using env file from: $candidate"
        cp "$candidate" "$DEFAULT_ENV_FILE"
        ENV_FILE_COPIED="true"
        ENV_FILE="$DEFAULT_ENV_FILE"
        return
    fi

    candidate="/etc/.hypernode/.hypernode-install-env.log"
    if [[ -f "$candidate" ]]; then
        echo "ℹ️  Using env file from: $candidate"
        cp "$candidate" "$DEFAULT_ENV_FILE"
        ENV_FILE_COPIED="true"
        ENV_FILE="$DEFAULT_ENV_FILE"
        return
    fi

    if find_hypernode_dir; then
        candidate="${HYPERNODE_DIR}/.hypernode-install-env.log"
        if [[ -f "$candidate" ]]; then
            echo "ℹ️  Using env file from: $candidate"
            cp "$candidate" "$DEFAULT_ENV_FILE"
            ENV_FILE_COPIED="true"
            ENV_FILE="$DEFAULT_ENV_FILE"
            return
        fi
    fi

    echo "ℹ️  Env file not found. Collecting values interactively."
    prompt_env_vars
    ENV_FILE="$DEFAULT_ENV_FILE"
}

usage() {
    cat <<'EOF'
Usage: uss_restore.sh [options]

Options:
  --env-file <path>       Path to env file (default: ./.hypernode-install-env.log)
  --deploy-branch <name>  Deploy branch for native_update.sh (default: main)
  -h, --help              Show this help
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            ENV_FILE_PROVIDED="true"
            shift 2
            ;;
        --deploy-branch)
            DEPLOY_BRANCH="$2"
            DEPLOY_BRANCH_PROVIDED="true"
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

resolve_env_file
ENV_FILE="$(cd "$(dirname "$ENV_FILE")" && pwd -P)/$(basename "$ENV_FILE")"
if [[ "$ENV_FILE_COPIED" == "true" ]]; then
    echo "ℹ️  Env file copied to: $ENV_FILE"
fi

ensure_machine_env_in_file "$ENV_FILE" || true

if [[ "$DEPLOY_BRANCH_PROVIDED" != "true" ]]; then
    if ! is_interactive; then
        echo "❌ --deploy-branch option not provided and no interactive input available."
        exit 1
    fi
    while true; do
        read -r -p "⚠️  --deploy-branch option not provided: should I use the default (main)? [y/n] " reply
        case "$reply" in
            y|Y)
                break
                ;;
            n|N)
                echo "❌ Aborted. Please provide --deploy-branch."
                exit 1
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

if ! is_docker_logged_in; then
    if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
        echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
    else
        if ! is_interactive; then
            echo "❌ Docker not logged in and no credentials provided; cannot prompt for login in non-interactive mode."
            exit 1
        fi
        read -r -p "Docker username [artecoglobalcompany]: " DOCKER_USERNAME_INPUT
        DOCKER_USERNAME_INPUT="${DOCKER_USERNAME_INPUT:-artecoglobalcompany}"
        read -r -s -p "Docker access token: " DOCKER_PASSWORD_INPUT
        echo
        echo "$DOCKER_PASSWORD_INPUT" | docker login -u "$DOCKER_USERNAME_INPUT" --password-stdin
    fi
fi

mkdir -p "$RESTORE_DIR"
chmod 777 "$RESTORE_DIR"

if [[ "$ENV_FILE" != "$DEFAULT_ENV_FILE" ]]; then
    cp "$ENV_FILE" "$DEFAULT_ENV_FILE"
fi

cp "$DEFAULT_ENV_FILE" "${RESTORE_DIR}/.hypernode-install-env.log"
chmod 644 "${RESTORE_DIR}/.hypernode-install-env.log"

sync_env_to_system "$DEFAULT_ENV_FILE" || true

if [[ -d "$GUI_INSTALL_DIR" ]]; then
    if cp "$DEFAULT_ENV_FILE" "$GUI_ENV_FILE" 2>/dev/null; then
        chmod 644 "$GUI_ENV_FILE" 2>/dev/null || true
        echo "ℹ️  Env file updated in GUI installer dir: $GUI_ENV_FILE"
    else
        echo "⚠️  Unable to update env file in GUI installer dir: $GUI_ENV_FILE"
    fi
fi

NATIVE_UPDATE_URL="${ABSOLUTE_PATH_BASE}/${DEPLOY_BRANCH}/installer_docker/native_update.sh"
curl -sSL "$NATIVE_UPDATE_URL" -o "$NATIVE_UPDATE_PATH"
chmod +x "$NATIVE_UPDATE_PATH"

pushd "$RESTORE_DIR" >/dev/null
if [[ "$DEPLOY_BRANCH_PROVIDED" == "true" ]]; then
    ./native_update.sh --deploy-branch "$DEPLOY_BRANCH"
else
    ./native_update.sh
fi
popd >/dev/null

rm -f "$NATIVE_UPDATE_PATH"

echo "Configurator URL (if finalized): https://${SERIAL_NUMBER}.lan.omniaweb.cloud:${SSL_PORT}"
echo "Configurator URL (before finalizing): https://${SERVER_IP_ADDRESS}:${SSL_PORT}"
