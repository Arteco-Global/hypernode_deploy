#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE=""
SERVICE_OVERRIDE=""
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
COMPOSE_CMD="docker compose"
SYSTEM_ENV_DIR="/etc/.hypernode"
DOCKER_CMD="docker"
IGNORE_ENV_VALIDATION="false"
MACHINE=""
MACHINE_JSON_NAME="machine.json"
MACHINE_FILE_LOCAL="${PWD}/${MACHINE_JSON_NAME}"
MACHINE_FILE_SYSTEM="${SYSTEM_ENV_DIR}/${MACHINE_JSON_NAME}"
MACHINE_FILE=""
AGENT_K_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/agent-k"

usage() {
    cat <<'EOF'
Usage: native_service_update.sh [options]

Options:
  --env-file <path>       Path to env file (optional; otherwise uses running containers)
  --deploy-branch <name>  Deploy branch for compose files (default: main)
  --service <name>        Override service (camera|auth|event|storage|snapshot|recording|metadata)
  --ignoreValidation      Skip env validation against compose variables
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

wait_for_tcp_port() {
    local label="$1"
    local host="$2"
    local port="$3"
    local timeout="${4:-180}"
    local started_at
    local elapsed

    started_at=$(date +%s)
    echo "⌛ Waiting for $label on ${host}:${port}"

    while true; do
        if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
            echo "✅ $label is reachable on ${host}:${port}"
            return 0
        fi

        elapsed=$(( $(date +%s) - started_at ))
        if (( elapsed >= timeout )); then
            echo "❌ Timeout waiting for $label on ${host}:${port}"
            return 1
        fi

        sleep 2
    done
}

extract_required_envs_from_compose() {
    local compose_file="$1"

    grep -oE '\$\{[^}]+\}' "$compose_file" 2>/dev/null \
        | sed -E 's/^\$\{([^}]+)\}$/\1/' \
        | awk '
            {
                expr=$0
                name=expr
                sub(/^!/, "", name)
                sub(/:.*/, "", name)
                sub(/[-+?].*/, "", name)

                # Consider every env reference in compose as required,
                # including expressions with defaults like ${VAR:-value}.
                if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
                    print name
                }
            }
        ' \
        | sort -u
}

validate_required_envs_for_compose() {
    local env_file="$1"
    shift
    local compose_files=("$@")
    local required_vars=()
    local received_vars=()
    local missing_vars=()
    local var=""
    local compose_file=""

    for compose_file in "${compose_files[@]}"; do
        if [[ -f "$compose_file" ]]; then
            while IFS= read -r var; do
                [[ -n "$var" ]] && required_vars+=("$var")
            done < <(extract_required_envs_from_compose "$compose_file")
        fi
    done

    if [[ "${#required_vars[@]}" -eq 0 ]]; then
        return 0
    fi

    mapfile -t required_vars < <(printf '%s\n' "${required_vars[@]}" | sort -u)
    mapfile -t received_vars < <(
        sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' "$env_file" | sort -u
    )

    echo "ℹ️  Env ricevute da $env_file:"
    if [[ "${#received_vars[@]}" -gt 0 ]]; then
        echo "   ${received_vars[*]}"
    else
        echo "   (nessuna variabile trovata)"
    fi

    echo "ℹ️  Env necessarie dai compose:"
    echo "   ${required_vars[*]}"

    for var in "${required_vars[@]}"; do
        if ! grep -Eq "^[[:space:]]*(export[[:space:]]+)?${var}=" "$env_file"; then
            missing_vars+=("$var")
        fi
    done

    if [[ "${#missing_vars[@]}" -gt 0 ]]; then
        echo "❌ Update bloccato: variabili env obbligatorie mancanti nel file $env_file. Probabilmente questo è un tentativo di update da una versione ad un altra."
        echo "   Missing: ${missing_vars[*]}"
        echo "   Compose analizzati:"
        for compose_file in "${compose_files[@]}"; do
            echo "   - $compose_file"
        done
        exit 1
    fi

    echo "✅ Env corrette: tutte le variabili obbligatorie sono presenti. Procedo con l'update."
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

deploy_agent_k() {
    local agent_k_base_url="${ABSOLUTE_PATH_BASE}/${DEPLOY_BRANCH}/agent-k"
    local agent_k_compose_url="${agent_k_base_url}/compose.yml"
    local agent_k_config_example_url="${agent_k_base_url}/config.example.yml"
    local compose_file="${AGENT_K_DIR}/compose.yml"
    local config_file="${AGENT_K_DIR}/config.yml"
    local data_dir="${AGENT_K_DIR}/data"
    local sample_file="${AGENT_K_DIR}/config.example.yml.download"
    local merged_file="${AGENT_K_DIR}/config.yml.merged"
    local backup_file="${AGENT_K_DIR}/config.yml.bak"

    echo "▶️  Update agent-k"

    mkdir -p "$AGENT_K_DIR" "$data_dir"

    curl -fsSL "$agent_k_compose_url" -o "$compose_file"
    curl -fsSL "$agent_k_config_example_url" -o "$sample_file"

    if [[ ! -f "$config_file" ]]; then
        mv "$sample_file" "$config_file"
        echo "ℹ️  Created agent-k config from sample: $config_file"
    else
        cp "$config_file" "$backup_file"
        merge_agent_k_config "$config_file" "$sample_file" "$merged_file"
        mv "$merged_file" "$config_file"
        rm -f "$sample_file"
        echo "ℹ️  Merged existing agent-k config with latest sample: $config_file"
        echo "ℹ️  Backup saved to: $backup_file"
        echo "ℹ️  Preserved existing custom values and added any new default parameters"
    fi

    $COMPOSE_CMD --project-directory "$AGENT_K_DIR" -f "$compose_file" pull
    $COMPOSE_CMD --project-directory "$AGENT_K_DIR" -f "$compose_file" up -d --force-recreate

    echo "✅ agent-k updated in $AGENT_K_DIR"
}

merge_agent_k_config() {
    local current_config="$1"
    local sample_config="$2"
    local merged_config="$3"

    python3 - "$current_config" "$sample_config" "$merged_config" <<'PY'
from __future__ import annotations

import ast
import copy
import sys
from pathlib import Path


def parse_scalar(value: str):
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "~"}:
        return None
    try:
        if any(ch in value for ch in ".eE"):
            return float(value)
        return int(value)
    except ValueError:
        pass
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return ast.literal_eval(value)
    return value


def parse_simple_yaml(path: Path):
    root = {}
    stack = [(-1, root)]

    lines = path.read_text().splitlines()
    for index, raw_line in enumerate(lines):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.strip()

        while stack and indent <= stack[-1][0]:
            stack.pop()

        parent = stack[-1][1]

        if line.startswith("- "):
            if not isinstance(parent, list):
                raise ValueError(f"Unexpected list item in {path}: {raw_line}")
            parent.append(parse_scalar(line[2:].strip()))
            continue

        if ":" not in line:
            raise ValueError(f"Invalid line in {path}: {raw_line}")

        key, remainder = line.split(":", 1)
        key = key.strip()
        remainder = remainder.strip()

        if remainder:
            parent[key] = parse_scalar(remainder)
            continue

        next_significant = None
        for candidate in lines[index + 1:]:
            stripped = candidate.strip()
            if not stripped or candidate.lstrip().startswith("#"):
                continue
            next_significant = candidate
            break

        if next_significant is None:
            parent[key] = {}
            stack.append((indent, parent[key]))
            continue

        next_indent = len(next_significant) - len(next_significant.lstrip(" "))
        if next_indent <= indent:
            parent[key] = {}
            stack.append((indent, parent[key]))
            continue

        if next_significant.strip().startswith("- "):
            parent[key] = []
        else:
            parent[key] = {}

        stack.append((indent, parent[key]))

    return root


def merge(defaults, existing):
    if isinstance(defaults, dict) and isinstance(existing, dict):
        merged = copy.deepcopy(defaults)
        for key, existing_value in existing.items():
            if key in merged:
                merged[key] = merge(merged[key], existing_value)
            else:
                merged[key] = copy.deepcopy(existing_value)
        return merged
    return copy.deepcopy(existing)


def format_scalar(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        if value == "" or any(ch in value for ch in ":#[]{}-,&*!?|>@`\"'"):
            return repr(value)
        return value
    raise TypeError(f"Unsupported scalar value: {value!r}")


def dump_yaml(value, indent=0):
    lines = []
    prefix = " " * indent
    if isinstance(value, dict):
        for key, item in value.items():
            if isinstance(item, dict):
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml(item, indent + 2))
            elif isinstance(item, list):
                lines.append(f"{prefix}{key}:")
                for entry in item:
                    if isinstance(entry, (dict, list)):
                        raise TypeError("Nested complex lists are not supported")
                    lines.append(f"{prefix}  - {format_scalar(entry)}")
            else:
                lines.append(f"{prefix}{key}: {format_scalar(item)}")
        return lines
    raise TypeError("Top-level YAML document must be a mapping")


current_path = Path(sys.argv[1])
sample_path = Path(sys.argv[2])
merged_path = Path(sys.argv[3])

existing = parse_simple_yaml(current_path)
defaults = parse_simple_yaml(sample_path)
merged = merge(defaults, existing)
merged_path.write_text("\n".join(dump_yaml(merged)) + "\n")
PY
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
        DB_USERNAME="${DB_USERNAME:-hypernode}"
        DB_PASSWORD="${DB_PASSWORD:-hypernode}"

        if [[ -z "${PROCESS_NAME:-}" && -n "${DB_NAME:-}" ]]; then
            PROCESS_NAME="${DB_NAME#database-for-}"
        fi

        if [[ -z "${DB_NAME:-}" && -n "${PROCESS_NAME:-}" ]]; then
            DB_NAME="database-for-${PROCESS_NAME}"
        fi

        if [[ -z "${DATABASE_URI:-}" && -n "${DB_NAME:-}" && -n "${PROCESS_NAME:-}" ]]; then
            DATABASE_URI="mongodb://${DB_USERNAME}:${DB_PASSWORD}@${DB_NAME}:27017/${PROCESS_NAME}?authSource=admin"
        fi

        export DB_PORT DOCKER_TAG PROCESS_NAME DB_NAME DB_USERNAME DB_PASSWORD DATABASE_URI

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

        if [[ "$IGNORE_ENV_VALIDATION" == "true" ]]; then
            echo "⚠️  Env validation skipped (--ignoreValidation)."
        else
            validate_required_envs_for_compose "$env_file" "$tmp_db_compose" "$tmp_service_compose"
        fi

        pull_images_from_compose "database" -f "$tmp_db_compose"
        pull_images_from_compose "$service_name" -f "$tmp_service_compose"

        echo "▶️  Recreate database"
        $COMPOSE_CMD -f "$tmp_db_compose" up -d --force-recreate --remove-orphans
        wait_for_tcp_port "database" "127.0.0.1" "${DB_PORT:-27017}"

        echo "▶️  Recreate $service_name"
        $COMPOSE_CMD -f "$tmp_service_compose" up -d --force-recreate --remove-orphans

        deploy_agent_k

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
        --ignoreValidation)
            IGNORE_ENV_VALIDATION="true"
            shift
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
