#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
DEFAULT_COMPOSE_URL="${ABSOLUTE_PATH_BASE}/${DEPLOY_BRANCH}/installer_docker/composes/server/docker-compose.yaml"
OUTPUT_FILE="${PWD}/_restored_hypernode-install-env.log"

COMPOSE_SOURCE=""
TMP_COMPOSE=""

ENV_VARS=(
  SSL_PORT
  DOCKER_TAG
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
  STORAGE_PATH
  STORAGE_DISK_SPACE
  SNAPSHOT_PATH
  SNAPSHOT_DISK_SPACE
  DB_PORT
  DB_NAME
  PROCESS_NAME
  DATABASE_URI
  RMQ
  GRI
  INSTALL_OPTION
)

usage() {
  cat <<'EOF'
Usage: recreate_env_file.sh [options]

Options:
  -c, --compose <path|url>  Compose file to use (default: GitHub raw)
  -o, --output <path>       Output env file (default: ./_restored_hypernode-install-env.log)
  -h, --help                Show this help
EOF
}

log_info() { printf "ℹ️  %s\n" "$*"; }
log_warn() { printf "⚠️  %s\n" "$*" >&2; }
log_err() { printf "❌ %s\n" "$*" >&2; }

cleanup() {
  [[ -n "$TMP_COMPOSE" && -f "$TMP_COMPOSE" ]] && rm -f "$TMP_COMPOSE"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--compose)
      COMPOSE_SOURCE="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_err "Parametro non riconosciuto: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$COMPOSE_SOURCE" ]]; then
  COMPOSE_SOURCE="$DEFAULT_COMPOSE_URL"
fi

if [[ "$COMPOSE_SOURCE" =~ ^https?:// ]]; then
  TMP_COMPOSE=$(mktemp)
  if ! curl -fsSL "$COMPOSE_SOURCE" -o "$TMP_COMPOSE"; then
    log_err "Impossibile scaricare il compose da $COMPOSE_SOURCE"
    exit 1
  fi
  COMPOSE_SOURCE="$TMP_COMPOSE"
else
  if [[ ! -f "$COMPOSE_SOURCE" ]]; then
    log_err "Compose non trovato: $COMPOSE_SOURCE"
    exit 1
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  log_err "Docker non disponibile."
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  log_err "Docker non accessibile. Esegui con sudo."
  exit 1
fi

declare -A SERVICE_CONTAINER=()
declare -a SERVICES=()

parse_compose_services() {
  local file="$1"
  local in_services="false"
  local current_service=""
  local current_container=""

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^services: ]]; then
      in_services="true"
      continue
    fi

    if [[ "$in_services" == "false" ]]; then
      continue
    fi

    if [[ "$line" =~ ^[[:alnum:]_].* ]]; then
      break
    fi

    if [[ "$line" =~ ^[[:space:]]{2}([A-Za-z0-9._-]+):[[:space:]]*$ ]]; then
      if [[ -n "$current_service" ]]; then
        local name="${current_container:-$current_service}"
        SERVICE_CONTAINER["$current_service"]="$name"
        SERVICES+=("$current_service")
      fi
      current_service="${BASH_REMATCH[1]}"
      current_container=""
      continue
    fi

    if [[ -n "$current_service" && "$line" =~ ^[[:space:]]{4}container_name:[[:space:]]*([^[:space:]]+) ]]; then
      current_container="${BASH_REMATCH[1]}"
    fi
  done < "$file"

  if [[ -n "$current_service" ]]; then
    local name="${current_container:-$current_service}"
    SERVICE_CONTAINER["$current_service"]="$name"
    SERVICES+=("$current_service")
  fi
}

parse_compose_services "$COMPOSE_SOURCE"

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  log_err "Nessun servizio trovato nel compose."
  exit 1
fi

container_running() {
  local name="$1"
  docker ps -q -f "name=^${name}$" | grep -q .
}

get_env() {
  local container="$1"
  local key="$2"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null \
    | awk -F= -v k="$key" '$1==k{print substr($0,length(k)+2); exit}'
}

get_image_tag() {
  local container="$1"
  local image image_no_digest tag
  image="$(docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null || true)"
  image_no_digest="${image%@*}"
  if [[ "$image_no_digest" == *":"* ]]; then
    tag="${image_no_digest##*:}"
  else
    tag="latest"
  fi
  printf "%s" "$tag"
}

get_mount_source() {
  local container="$1"
  local dest="$2"
  docker inspect -f "{{range .Mounts}}{{if eq .Destination \"${dest}\"}}{{.Source}}{{end}}{{end}}" "$container" 2>/dev/null || true
}

get_port_mapping() {
  local container="$1"
  local port="$2"
  docker inspect -f "{{if (index .NetworkSettings.Ports \"${port}\")}}{{(index (index .NetworkSettings.Ports \"${port}\") 0).HostPort}}{{end}}" "$container" 2>/dev/null || true
}

parse_db_port_from_uri() {
  local uri="$1"
  local port=""
  if [[ "$uri" =~ mongodb://[^:/]+:([0-9]+) ]]; then
    port="${BASH_REMATCH[1]}"
  elif [[ "$uri" =~ mongodb://[^/]+/ ]]; then
    port="27017"
  fi
  printf "%s" "$port"
}

get_container_for_service() {
  local service="$1"
  local container="${SERVICE_CONTAINER[$service]:-}"
  if [[ -z "$container" ]]; then
    printf ""
    return
  fi
  if container_running "$container"; then
    printf "%s" "$container"
  else
    printf ""
  fi
}

GATEWAY_CONTAINER="$(get_container_for_service "gateway")"
CORETRUST_CONTAINER="$(get_container_for_service "coretrust")"
RECORDING_CONTAINER="$(get_container_for_service "recording")"
SNAPSHOT_CONTAINER="$(get_container_for_service "snapshot")"
PORTBROKER_CONTAINER="$(get_container_for_service "portbroker")"
MESSAGEBROKER_CONTAINER="$(get_container_for_service "messagebroker")"
STORAGE_CONTAINER="$(get_container_for_service "storage")"

if [[ -z "$GATEWAY_CONTAINER" ]]; then
  log_warn "Container gateway non in esecuzione. Alcuni valori potrebbero mancare."
fi
if [[ -z "$CORETRUST_CONTAINER" ]]; then
  log_warn "Container coretrust non in esecuzione. Alcuni valori potrebbero mancare."
fi

declare -A VALUES=()

if [[ -n "$PORTBROKER_CONTAINER" ]]; then
  VALUES[SSL_PORT]="$(get_port_mapping "$PORTBROKER_CONTAINER" "443/tcp")"
fi

if [[ -n "$MESSAGEBROKER_CONTAINER" ]]; then
  VALUES[DOCKER_TAG]="$(get_image_tag "$MESSAGEBROKER_CONTAINER")"
elif [[ -n "$GATEWAY_CONTAINER" ]]; then
  VALUES[DOCKER_TAG]="$(get_image_tag "$GATEWAY_CONTAINER")"
fi

if [[ -n "$CORETRUST_CONTAINER" ]]; then
  VALUES[SERIAL_NUMBER]="$(get_env "$CORETRUST_CONTAINER" "SERIAL_NUMBER")"
  VALUES[ARTECO_GLOBAL_EMAIL]="$(get_env "$CORETRUST_CONTAINER" "ARTECO_GLOBAL_EMAIL")"
  VALUES[ARTECO_GLOBAL_PASSWORD]="$(get_env "$CORETRUST_CONTAINER" "ARTECO_GLOBAL_PASSWORD")"
  VALUES[SERVER_IP_ADDRESS]="$(get_env "$CORETRUST_CONTAINER" "SERVER_IP_ADDRESS")"
  VALUES[CERTIFICATE_PROVIDER_URL]="$(get_env "$CORETRUST_CONTAINER" "CERTIFICATE_PROVIDER_URL")"
  VALUES[DNS_PROVIDER_URL]="$(get_env "$CORETRUST_CONTAINER" "DNS_PROVIDER_URL")"
  VALUES[LICENSE_PROVIDER_URL]="$(get_env "$CORETRUST_CONTAINER" "LICENSE_PROVIDER_URL")"
fi

if [[ -n "$GATEWAY_CONTAINER" ]]; then
  VALUES[SERVER_TIMEZONE]="$(get_env "$GATEWAY_CONTAINER" "SERVER_TIMEZONE")"
  VALUES[SERVER_NAME]="$(get_env "$GATEWAY_CONTAINER" "SERVER_NAME")"
  if [[ -z "${VALUES[LICENSE_PROVIDER_URL]:-}" ]]; then
    VALUES[LICENSE_PROVIDER_URL]="$(get_env "$GATEWAY_CONTAINER" "LICENSE_PROVIDER_URL")"
  fi
  VALUES[RMQ]="$(get_env "$GATEWAY_CONTAINER" "RABBITMQ_URI")"
  if [[ -z "${VALUES[DB_PORT]:-}" ]]; then
    db_uri="$(get_env "$GATEWAY_CONTAINER" "DATABASE_URI")"
    VALUES[DB_PORT]="$(parse_db_port_from_uri "$db_uri")"
  fi
fi

if [[ -n "$CORETRUST_CONTAINER" && -z "${VALUES[DB_PORT]:-}" ]]; then
  db_uri="$(get_env "$CORETRUST_CONTAINER" "DATABASE_URI")"
  VALUES[DB_PORT]="$(parse_db_port_from_uri "$db_uri")"
fi

if [[ -n "$RECORDING_CONTAINER" ]]; then
  VALUES[RECORDING_PATH]="$(get_mount_source "$RECORDING_CONTAINER" "/recording_files")"
  VALUES[RECORDING_DISK_SPACE]="$(get_env "$RECORDING_CONTAINER" "RECORDING_DISK_SPACE")"
fi

if [[ -n "$SNAPSHOT_CONTAINER" ]]; then
  VALUES[SNAPSHOT_PATH]="$(get_mount_source "$SNAPSHOT_CONTAINER" "/snapshot_files")"
  VALUES[SNAPSHOT_DISK_SPACE]="$(get_env "$SNAPSHOT_CONTAINER" "SNAPSHOT_DISK_SPACE")"
fi

if [[ -n "$STORAGE_CONTAINER" ]]; then
  VALUES[STORAGE_PATH]="$(get_mount_source "$STORAGE_CONTAINER" "/storage_files")"
  VALUES[STORAGE_DISK_SPACE]="$(get_env "$STORAGE_CONTAINER" "STORAGE_DISK_SPACE")"
fi

if [[ -z "${VALUES[DB_NAME]:-}" ]]; then
  if container_running "USS_SERVER"; then
    VALUES[DB_NAME]="USS_SERVER"
  else
    VALUES[DB_NAME]="USS_SERVER"
  fi
fi

VALUES[PROCESS_NAME]="--"
VALUES[DATABASE_URI]=""
VALUES[GRI]=""
VALUES[INSTALL_OPTION]="1"

tmp_file="$(mktemp)"
for var_name in "${ENV_VARS[@]}"; do
  if [[ -n "${VALUES[$var_name]:-}" ]]; then
    printf '%s=%q\n' "$var_name" "${VALUES[$var_name]}" >> "$tmp_file"
  else
    printf '%s=\n' "$var_name" >> "$tmp_file"
  fi
done

mv "$tmp_file" "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE" 2>/dev/null || true

log_info "File ricreato: $OUTPUT_FILE"
log_info "Compose usato: $COMPOSE_SOURCE"
