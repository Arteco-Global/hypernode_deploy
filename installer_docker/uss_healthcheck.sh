#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ABSOLUTE_PATH="${ABSOLUTE_PATH:-https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/composes}"
COMPOSE_FILES=(
  "$SCRIPT_DIR/composes/server/docker-compose.yaml"
  "$SCRIPT_DIR/composes/database/docker-compose.yaml"
)
COMPOSE_URLS=(
  "$ABSOLUTE_PATH/server/docker-compose.yaml"
  "$ABSOLUTE_PATH/database/docker-compose.yaml"
)

TMP_COMPOSES=()
COMPOSE_SOURCES=()
CONTAINERS=()
HYPERNODE_DIR=""

info() { echo "ℹ️  $*"; }
warn() { echo "⚠️  $*" >&2; }
error() { echo "❌ $*" >&2; }
ok() { echo "✅ $*"; }

cleanup() {
  for tmp in "${TMP_COMPOSES[@]:-}"; do
    [[ -f "$tmp" ]] && rm -f "$tmp"
  done
}
trap cleanup EXIT

ensure_docker_running() {
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker non è installato o non è nel PATH."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    error "Docker non è in esecuzione. Avviare il demone e riprovare."
    exit 1
  fi

  ok "Docker è in esecuzione."
}

download_compose_sources() {
  local idx file url tmp

  for idx in "${!COMPOSE_FILES[@]}"; do
    file="${COMPOSE_FILES[$idx]}"
    url="${COMPOSE_URLS[$idx]}"

    tmp=$(mktemp)
    if curl -fsSL "$url" -o "$tmp"; then
      COMPOSE_SOURCES+=("$tmp")
      TMP_COMPOSES+=("$tmp")
      info "Compose scaricato da $url"
    else
      warn "Impossibile scaricare il compose da $url"
      rm -f "$tmp"
    fi

    if [[ -f "$file" ]]; then
      COMPOSE_SOURCES+=("$file")
      info "Compose locale disponibile: $file"
    fi
  done

  if [[ ${#COMPOSE_SOURCES[@]} -eq 0 ]]; then
    warn "Nessun compose disponibile (né remoto né locale)."
  fi
}

dedupe_array() {
  local -n arr_ref=$1
  local -A seen=()
  local new_arr=()

  for item in "${arr_ref[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ -z "${seen[$item]:-}" ]]; then
      new_arr+=("$item")
      seen["$item"]=1
    fi
  done

  arr_ref=("${new_arr[@]}")
}

parse_compose_container_names() {
  local file="$1"
  local in_services="false"
  local current_service=""
  local current_container=""

  [[ -f "$file" ]] || return

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
        CONTAINERS+=("$name")
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
    CONTAINERS+=("$name")
  fi
}

check_container_statuses() {
  local name status health running all_ok=0

  if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
    warn "Nessun container individuato dai compose."
    return 1
  fi

  for name in "${CONTAINERS[@]}"; do
    if ! docker inspect "$name" >/dev/null 2>&1; then
      warn "$name: container non trovato."
      all_ok=1
      continue
    fi

    IFS="|" read -r status health <<< "$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null || echo "unknown|")"
    running="no"
    [[ "$status" == "running" ]] && running="si"

    if [[ "$status" == "running" && ( -z "$health" || "$health" == "healthy" ) ]]; then
      ok "$name -> stato: $status, health: ${health:-n/a}, running: $running"
    else
      warn "$name -> stato: ${status:-unknown}, health: ${health:-n/a}, running: $running"
      all_ok=1
    fi
  done

  return $all_ok
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

  parent="$(cd "$SCRIPT_DIR/.." && pwd)"
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

stat_summary() {
  local file="$1"
  if stat --version >/dev/null 2>&1; then
    stat -c '%A %U %G %s %y' "$file"
  else
    stat -f '%Sp %Su %Sg %z %Sm' "$file"
  fi
}

check_required_files() {
  local base="$1"
  local -a required=(
    "check-container-updates.sh"
    "container_update_report.json"
    "container_versions.json"
    "dump-container-versions.sh"
    ".hypernode-update-check.conf"
    "hypernode-update-check.log"
    ".hypernode-update-check.state"
    "installer.sh"
    "run-hypernode-update-check.sh"
    "update_uss.sh"
  )

  local missing=0 path
  for rel in "${required[@]}"; do
    path="$base/$rel"
    if [[ -e "$path" ]]; then
      ok "$rel presente ($(stat_summary "$path"))"
    else
      warn "$rel mancante in $base"
      missing=1
    fi
  done

  return $missing
}

read_serial_from_config() {
  local file="$1" line value
  line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?SERIAL=' "$file" | tail -n 1 || true)
  if [[ -z "$line" ]]; then
    return 1
  fi

  value="${line#*=}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"

  if [[ -n "$value" ]]; then
    echo "$value"
    return 0
  fi

  return 1
}

resolve_host() {
  local host="$1" ip=""

  if command -v getent >/dev/null 2>&1; then
    ip=$(getent hosts "$host" | awk 'NR==1 {print $1}')
  fi

  if [[ -z "$ip" ]] && command -v dig >/dev/null 2>&1; then
    ip=$(dig +short "$host" A | awk 'NF {print $1; exit}')
  fi

  if [[ -z "$ip" ]] && command -v nslookup >/dev/null 2>&1; then
    ip=$(nslookup "$host" | awk '/^Address: / {print $2; exit}')
  fi

  if [[ -z "$ip" ]] && command -v host >/dev/null 2>&1; then
    ip=$(host "$host" | awk '/ has address / {print $4; exit}')
  fi

  if [[ -n "$ip" ]]; then
    echo "$ip"
    return 0
  fi

  return 1
}

current_local_ip() {
  local ip=""
  ip=$(python3 - <<'PY'
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    print(s.getsockname()[0])
finally:
    s.close()
PY
  ) || true

  if [[ -z "$ip" ]]; then
    if command -v hostname >/dev/null 2>&1; then
      ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
  fi

  [[ -n "$ip" ]] && echo "$ip" && return 0
  return 1
}

current_public_ip() {
  local ip=""
  ip=$(curl -fsSL https://api.ipify.org 2>/dev/null || true)
  if [[ -z "$ip" ]]; then
    ip=$(curl -fsSL https://ifconfig.me 2>/dev/null || true)
  fi

  [[ -n "$ip" ]] && echo "$ip" && return 0
  return 1
}

compare_dns_ip() {
  local label="$1" host="$2" expected_ip="$3"
  local resolved=""

  if [[ -z "$expected_ip" ]]; then
    warn "$label: IP atteso non disponibile."
    return
  fi

  resolved=$(resolve_host "$host" || true)
  if [[ -z "$resolved" ]]; then
    warn "$label: impossibile risolvere $host"
    return
  fi

  if [[ "$resolved" == "$expected_ip" ]]; then
    ok "$label: $host risolve in $resolved (atteso: $expected_ip)"
  else
    warn "$label: $host risolve in $resolved (atteso: $expected_ip)"
  fi
}

run_update_check() {
  local script_path="$1"
  if [[ ! -x "$script_path" ]]; then
    warn "Script $script_path non trovato o non eseguibile."
    return 1
  fi

  info "Eseguo $(basename "$script_path") --use-config --force-send"
  if (cd "$(dirname "$script_path")" && "$script_path" --use-config --force-send); then
    ok "run-hypernode-update-check.sh completato."
  else
    warn "run-hypernode-update-check.sh terminato con errore."
  fi
}

ensure_docker_running

download_compose_sources
for compose in "${COMPOSE_SOURCES[@]:-}"; do
  parse_compose_container_names "$compose"
done
dedupe_array CONTAINERS
check_container_statuses || true

if find_hypernode_dir; then
  ok "Cartella hypernode_deploy trovata: $HYPERNODE_DIR"
else
  error "Cartella hypernode_deploy non trovata nel sistema."
  exit 1
fi

check_required_files "$HYPERNODE_DIR" || true

CONFIG_FILE="$HYPERNODE_DIR/.hypernode-update-check.conf"
SERIAL_VALUE=""
if [[ -f "$CONFIG_FILE" ]]; then
  SERIAL_VALUE=$(read_serial_from_config "$CONFIG_FILE" || true)
else
  warn "File di configurazione $CONFIG_FILE mancante."
fi

if [[ -n "$SERIAL_VALUE" ]]; then
  ok "SERIAL rilevato: $SERIAL_VALUE"
  SERIAL_LOWER=$(echo "$SERIAL_VALUE" | tr '[:upper:]' '[:lower:]')
  LOCAL_HOST="${SERIAL_LOWER}.lan.omniaweb.cloud"
  PUBLIC_HOST="${SERIAL_LOWER}.my.omniaweb.cloud"

  LOCAL_IP=$(current_local_ip || true)
  PUBLIC_IP=$(current_public_ip || true)

  [[ -n "$LOCAL_IP" ]] && info "IP locale corrente: $LOCAL_IP" || warn "IP locale non determinato."
  [[ -n "$PUBLIC_IP" ]] && info "IP pubblico corrente: $PUBLIC_IP" || warn "IP pubblico non determinato."

  compare_dns_ip "DNS LAN" "$LOCAL_HOST" "$LOCAL_IP"
  compare_dns_ip "DNS pubblico" "$PUBLIC_HOST" "$PUBLIC_IP"
else
  warn "Impossibile leggere SERIAL da $CONFIG_FILE."
fi

run_update_check "$HYPERNODE_DIR/run-hypernode-update-check.sh"
