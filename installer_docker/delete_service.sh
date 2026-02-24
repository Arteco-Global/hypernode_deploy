#!/bin/bash

set -euo pipefail

SYSTEM_ENV_DIR="/etc/.hypernode"
DOCKER_CMD="docker"
TARGET_SERVICE_CONTAINER=""
SKIP_CONFIRMATION="false"

usage() {
    cat <<'EOF'
Usage: delete_service.sh

Descrizione:
  Rimuove tutti i servizi aggiuntivi rilevati su host (container *_additional-*)
  insieme ai rispettivi database, path dati, volumi Docker e file env log.

Opzioni:
  --service <name>   Elimina solo il container servizio indicato
                     (es: camera_additional-pippo)
  -y, --yes          Salta la conferma interattiva
  -h, --help         Mostra questo help
EOF
}

confirm_action_or_exit() {
    local answer=""

    if [[ ! -t 0 ]]; then
        echo "❌ Prompt di conferma non disponibile senza terminale interattivo."
        exit 1
    fi

    read -r -p "Sei sicuro di voler procedere? [s/N] " answer
    case "$answer" in
        s|S|si|SI|Si|sI) return 0 ;;
        *)
            echo "ℹ️  Operazione annullata."
            exit 0
            ;;
    esac
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

get_running_container_names() {
    $DOCKER_CMD ps --format '{{.Names}}'
}

resolve_env_file_for_instance() {
    local instance="$1"
    local local_file="$PWD/.hypernode-install-${instance}-env.log"
    local system_file="$SYSTEM_ENV_DIR/.hypernode-install-${instance}-env.log"

    if [[ -f "$local_file" ]]; then
        printf '%s\n' "$local_file"
        return 0
    fi

    if [[ -f "$system_file" ]]; then
        printf '%s\n' "$system_file"
        return 0
    fi

    return 1
}

collect_additional_service_entries() {
    local target_service_container="${1:-}"
    local names
    local name
    local instance
    local env_file
    local missing=()
    local entries=()
    declare -A service_container_by_instance=()
    declare -A db_container_by_instance=()

    if ! names="$(get_running_container_names)"; then
        echo "❌ Unable to list running containers."
        exit 1
    fi

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue

        if [[ "$name" == database-for-additional-* ]]; then
            instance="${name#database-for-}"
            [[ -n "$instance" ]] || continue
            db_container_by_instance["$instance"]="$name"
            continue
        fi

        if [[ "$name" != *_additional-* ]]; then
            continue
        fi
        if [[ -n "$target_service_container" && "$name" != "$target_service_container" ]]; then
            continue
        fi

        instance="${name#*_}"
        [[ -n "$instance" ]] || continue
        service_container_by_instance["$instance"]="$name"
    done <<< "$names"

    if [[ "${#service_container_by_instance[@]}" -eq 0 ]]; then
        if [[ -n "$target_service_container" ]]; then
            echo "❌ Target service container not found in running containers: $target_service_container"
        else
            echo "❌ No eligible running additional service containers found."
        fi
        exit 1
    fi

    for instance in "${!service_container_by_instance[@]}"; do
        if ! env_file="$(resolve_env_file_for_instance "$instance")"; then
            missing+=(".hypernode-install-${instance}-env.log")
            continue
        fi

        local service_container="${service_container_by_instance[$instance]}"
        local db_container="${db_container_by_instance[$instance]:-database-for-${instance}}"
        entries+=("${instance}|${service_container}|${db_container}|${env_file}")
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        echo "❌ Missing env file(s) for running additional services:"
        for file in "${missing[@]}"; do
            echo "   - $file"
        done
        exit 1
    fi

    printf '%s\n' "${entries[@]}"
}

is_safe_directory_path() {
    local path="$1"
    case "$path" in
        ""|"/"|"/."|"/.."|"."|"..") return 1 ;;
        *) return 0 ;;
    esac
}

extract_storage_paths_from_env_file() {
    local env_file="$1"
    local source_file="$env_file"
    local tmp_file=""

    if [[ ! -r "$env_file" ]]; then
        if command -v sudo >/dev/null 2>&1 && sudo test -r "$env_file" 2>/dev/null; then
            tmp_file="$(mktemp)"
            sudo cat "$env_file" > "$tmp_file"
            source_file="$tmp_file"
        else
            echo "❌ Env file not readable: $env_file" >&2
            return 1
        fi
    fi

    (
        set -a
        source "$source_file"
        set +a

        [[ -n "${STORAGE_PATH:-}" ]] && printf '%s\n' "${STORAGE_PATH}"
        [[ -n "${SNAPSHOT_PATH:-}" ]] && printf '%s\n' "${SNAPSHOT_PATH}"
        [[ -n "${RECORDING_PATH:-}" ]] && printf '%s\n' "${RECORDING_PATH}"
    )

    if [[ -n "$tmp_file" ]]; then
        rm -f "$tmp_file"
    fi
}

remove_directory_forcefully() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "ℹ️  Path not found, skip: $path"
        return 0
    fi

    if rm -rf -- "$path" 2>/dev/null; then
        echo "🗑️  Removed path: $path"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo rm -rf -- "$path" 2>/dev/null; then
            echo "🗑️  Removed path (sudo): $path"
            return 0
        fi
    fi

    echo "⚠️  Unable to remove path: $path"
    return 1
}

container_exists() {
    local container="$1"
    local found
    found="$($DOCKER_CMD ps -a --filter "name=^/${container}$" --format '{{.Names}}' 2>/dev/null | head -n 1 || true)"
    [[ "$found" == "$container" ]]
}

collect_named_volumes_from_container() {
    local container="$1"
    $DOCKER_CMD inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' "$container" 2>/dev/null \
        | awk 'NF' \
        | sort -u
}

remove_container_if_exists() {
    local container="$1"
    if container_exists "$container"; then
        echo "▶️  Removing container: $container"
        if $DOCKER_CMD rm -f -v "$container" >/dev/null 2>&1; then
            echo "🗑️  Removed container: $container"
        else
            echo "⚠️  Unable to remove container: $container"
        fi
    else
        echo "ℹ️  Container not found, skip: $container"
    fi
}

remove_named_volume_if_exists() {
    local volume="$1"
    if [[ -z "$volume" ]]; then
        return 0
    fi

    echo "▶️  Removing volume: $volume"
    if $DOCKER_CMD volume rm -f "$volume" >/dev/null 2>&1; then
        echo "🗑️  Removed volume: $volume"
    else
        echo "ℹ️  Volume already absent or not removable: $volume"
    fi
}

remove_file_if_exists() {
    local file="$1"

    if [[ ! -e "$file" ]]; then
        return 0
    fi

    if rm -f -- "$file" 2>/dev/null; then
        echo "🗑️  Removed env log: $file"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo rm -f -- "$file" 2>/dev/null; then
            echo "🗑️  Removed env log (sudo): $file"
            return 0
        fi
    fi

    echo "⚠️  Unable to remove env log: $file"
    return 1
}

remove_env_log_replicas() {
    local env_file="$1"
    local base_name
    base_name="$(basename "$env_file")"
    declare -A targets=()

    targets["$env_file"]=1
    targets["${env_file}.original"]=1
    targets["$PWD/$base_name"]=1
    targets["$PWD/${base_name}.original"]=1
    targets["$SYSTEM_ENV_DIR/$base_name"]=1
    targets["$SYSTEM_ENV_DIR/${base_name}.original"]=1

    for target in "${!targets[@]}"; do
        remove_file_if_exists "$target" || true
    done
}

delete_additional_service() {
    local instance="$1"
    local service_container="$2"
    local db_container="$3"
    local env_file="$4"
    local path
    local volume
    local removed_any_path=0
    declare -A volumes=()

    echo ""
    echo "=============================================="
    echo "▶️  Start delete for instance: $instance"
    echo "   Service container:  $service_container"
    echo "   Database container: $db_container"
    echo "   Env file:           $env_file"
    echo "=============================================="

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if ! is_safe_directory_path "$path"; then
            echo "⚠️  Unsafe path skipped: $path"
            continue
        fi
        remove_directory_forcefully "$path" || true
        removed_any_path=1
    done < <(extract_storage_paths_from_env_file "$env_file" | awk 'NF' | sort -u)

    if [[ "$removed_any_path" -eq 0 ]]; then
        echo "ℹ️  No storage/snapshot/recording paths found in env."
    fi

    if container_exists "$service_container"; then
        while IFS= read -r volume; do
            [[ -z "$volume" ]] && continue
            volumes["$volume"]=1
        done < <(collect_named_volumes_from_container "$service_container")
    fi

    if container_exists "$db_container"; then
        while IFS= read -r volume; do
            [[ -z "$volume" ]] && continue
            volumes["$volume"]=1
        done < <(collect_named_volumes_from_container "$db_container")
    fi

    remove_container_if_exists "$service_container"
    remove_container_if_exists "$db_container"

    for volume in "${!volumes[@]}"; do
        remove_named_volume_if_exists "$volume"
    done

    remove_env_log_replicas "$env_file"

    echo "✅ Delete completed for instance: $instance"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --service)
            TARGET_SERVICE_CONTAINER="${2:-}"
            if [[ -z "$TARGET_SERVICE_CONTAINER" ]]; then
                echo "❌ Missing value for --service"
                usage
                exit 1
            fi
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION="true"
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

detect_docker_cmd

entries=()
while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    entries+=("$entry")
done < <(collect_additional_service_entries "$TARGET_SERVICE_CONTAINER")

echo "⚠️  Operazione distruttiva: verranno rimossi container, volumi, path dati e env log."
echo "Servizi da eliminare:"
for entry in "${entries[@]}"; do
    IFS='|' read -r instance service_container db_container env_file <<< "$entry"
    echo " - ${service_container} (db: ${db_container})"
done
if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
    echo "ℹ️  Conferma saltata per flag --yes."
else
    confirm_action_or_exit
fi

for entry in "${entries[@]}"; do
    IFS='|' read -r instance service_container db_container env_file <<< "$entry"
    delete_additional_service "$instance" "$service_container" "$db_container" "$env_file"
done

echo ""
echo "🏁 All additional services have been processed."
