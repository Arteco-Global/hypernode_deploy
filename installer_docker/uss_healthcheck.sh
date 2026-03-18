#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
ABSOLUTE_PATH="${ABSOLUTE_PATH:-}"
SYSTEM_ENV_DIR="/etc/.hypernode"
ENV_LOG_NAME=".hypernode-install-env.log"
COMPOSE_FILES=(
  "$SCRIPT_DIR/composes/server/docker-compose.yaml"
  "$SCRIPT_DIR/composes/database/docker-compose.yaml"
)
COMPOSE_URLS=()

TMP_COMPOSES=()
COMPOSE_SOURCES=()
CONTAINERS=()
HYPERNODE_DIR=""
CONFIG_FILE=""
USER_LOGIN_VALUE=""
USER_PASSWORD_VALUE=""
LICENSING_URL_VALUE=""
SITE_PORT=""
SITE_LAN_PORT=""
SERIAL_LOWER=""
SITE_STATUS=""
SITE_IS_USS=""
REACH_LAN_OK="false"
REACH_WAN_OK="false"
DB_PORT=""
DB_NAME=""
DB_CONTAINER=""
ENV_LOG_FILE=""

declare -A INSTALL_ENV=()

info() { echo "ℹ️  $*"; }
warn() { echo "⚠️  $*" >&2; }
error() { echo "❌ $*" >&2; }
ok() { echo "✅ $*"; }

section() {
  echo ""
  echo "=== $* ==="
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -db|--deploy-branch)
      DEPLOY_BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: uss_healthcheck.sh [options]"
      echo ""
      echo "Options:"
      echo "  -db, --deploy-branch   Set the deploy branch for remote compose files (default: main)"
      exit 0
      ;;
    *)
      warn "Opzione non riconosciuta: $1"
      shift
      ;;
  esac
done

if [[ -z "$ABSOLUTE_PATH" ]]; then
  ABSOLUTE_PATH="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"
fi

COMPOSE_URLS=(
  "$ABSOLUTE_PATH/server/docker-compose.yaml"
  "$ABSOLUTE_PATH/database/docker-compose.yaml"
)

subsection() {
  echo ""
  echo "-- $* --"
}

check_prerequisites() {
  section "0) PREREQUISITI"
  local missing=0

  check_tool() {
    local tool="$1" optional="${2:-false}" note="${3:-}"
    if command -v "$tool" >/dev/null 2>&1; then
      ok "$tool disponibile${note:+ ($note)}"
    else
      if [[ "$optional" == "true" ]]; then
        warn "$tool non trovato${note:+ ($note)}"
      else
        error "$tool non trovato${note:+ ($note)}"
        missing=1
      fi
    fi
  }

  check_tool "curl"
  check_tool "openssl"
  check_tool "python3"
  check_tool "timeout" true "opzionale (timeout openssl/curl)"
  check_tool "wget" true "opzionale (solo per scaricare lo script via wget)"
  check_tool "dig" true "opzionale (DNS)"
  check_tool "nslookup" true "opzionale (DNS)"
  check_tool "host" true "opzionale (DNS)"
  check_tool "getent" true "opzionale (DNS)"
  check_tool "jq" true "opzionale (non richiesto attualmente)"

  if (( missing > 0 )); then
    error "Prerequisiti mancanti: installare gli strumenti sopra e riprovare."
    exit 1
  fi
}

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

read_shell_var() {
  local file="$1" var_name="$2" result=""

  [[ -f "$file" ]] || return 1

  result=$(bash -c 'set -a; source "$1"; v="$2"; printf "%s" "${!v}"' bash "$file" "$var_name" 2>/dev/null || true)
  if [[ -n "$result" ]]; then
    printf "%s" "$result"
    return 0
  fi

  return 1
}

find_install_env_file() {
  local candidate
  local -a candidates=(
    "$PWD/$ENV_LOG_NAME"
    "$PWD/hypernode-install-env.log"
    "$SCRIPT_DIR/$ENV_LOG_NAME"
    "$SCRIPT_DIR/../$ENV_LOG_NAME"
    "$SYSTEM_ENV_DIR/$ENV_LOG_NAME"
    "$SYSTEM_ENV_DIR/hypernode-install-env.log"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf "%s" "$candidate"
      return 0
    fi
  done

  return 1
}

load_install_env() {
  local file="${1:-}"
  local key value
  local -a vars=(
    DB_NAME
    DB_PORT
    SSL_PORT
    DOCKER_TAG
    RECORDING_PATH
    SNAPSHOT_PATH
    STORAGE_PATH
  )

  if [[ -z "$file" ]]; then
    file="$(find_install_env_file || true)"
  fi

  if [[ -z "$file" || ! -f "$file" ]]; then
    warn "File env install non trovato: i controlli useranno fallback runtime."
    return 1
  fi

  ENV_LOG_FILE="$file"
  for key in "${vars[@]}"; do
    value="$(read_shell_var "$file" "$key" || true)"
    if [[ -n "$value" ]]; then
      INSTALL_ENV["$key"]="$value"
    fi
  done

  if [[ -n "${INSTALL_ENV[DB_NAME]:-}" ]]; then
    DB_NAME="${INSTALL_ENV[DB_NAME]}"
  fi

  if [[ -n "${INSTALL_ENV[DB_PORT]:-}" ]]; then
    DB_PORT="${INSTALL_ENV[DB_PORT]}"
  fi

  info "Env install rilevato: $ENV_LOG_FILE"
  return 0
}

resolve_compose_value() {
  local value="$1"
  local match var_name default_value replacement="" use_default_when_empty="false"

  while [[ "$value" =~ (\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}) ]]; do
    match="${BASH_REMATCH[1]}"
    var_name=""
    default_value=""
    replacement=""
    use_default_when_empty="false"

    if [[ "$match" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\}$ ]]; then
      var_name="${BASH_REMATCH[1]}"
      default_value="${BASH_REMATCH[2]}"
      use_default_when_empty="true"
    elif [[ "$match" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
      var_name="${BASH_REMATCH[1]}"
    else
      break
    fi

    if [[ -n "$var_name" && -n "${!var_name+x}" ]]; then
      replacement="${!var_name}"
      if [[ "$use_default_when_empty" == "true" && -z "$replacement" ]]; then
        replacement="$default_value"
      fi
    elif [[ -n "${INSTALL_ENV[$var_name]+x}" ]]; then
      replacement="${INSTALL_ENV[$var_name]}"
      if [[ "$use_default_when_empty" == "true" && -z "$replacement" ]]; then
        replacement="$default_value"
      fi
    else
      replacement="$default_value"
    fi

    value="${value//$match/$replacement}"
  done

  printf "%s" "$value"
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
      current_container="$(resolve_compose_value "${BASH_REMATCH[1]}")"
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

find_database_container() {
  local name image
  local -a candidates=()

  if [[ -n "${DB_NAME:-}" ]]; then
    candidates+=("$DB_NAME")
  fi

  if [[ -n "${INSTALL_ENV[DB_NAME]:-}" ]]; then
    candidates+=("${INSTALL_ENV[DB_NAME]}")
  fi

  while IFS="|" read -r name image; do
    [[ -n "$name" && -n "$image" ]] || continue
    if [[ "$image" == artecoglobalcompany/usee_database* ]]; then
      candidates+=("$name")
    fi
  done < <(docker ps -a --format '{{.Names}}|{{.Image}}')

  dedupe_array candidates

  for name in "${candidates[@]}"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      DB_CONTAINER="$name"
      return 0
    fi
  done

  return 1
}

find_database_port() {
  local container="" host_binding=""

  if find_database_container; then
    container="$DB_CONTAINER"
  elif [[ -n "${INSTALL_ENV[DB_PORT]:-}" ]]; then
    DB_PORT="${INSTALL_ENV[DB_PORT]}"
    warn "Container DB non trovato, uso DB_PORT dall'env install: $DB_PORT"
    return 0
  else
    warn "Container DB non trovato e DB_PORT non disponibile nell'env install."
    return 1
  fi

  host_binding=$(docker inspect --format '{{range $port, $bindings := .HostConfig.PortBindings}}{{if eq $port "27017/tcp"}}{{range $bindings}}{{printf "%s:%s\n" .HostIp .HostPort}}{{end}}{{end}}{{end}}' "$container" 2>/dev/null | awk 'NF{print; exit}' || true)
  if [[ -z "$host_binding" ]]; then
    host_binding=$(docker port "$container" 27017/tcp 2>/dev/null | awk 'NR==1{print $0}' || true)
  fi
  if [[ -z "$host_binding" ]]; then
    host_binding=$(docker inspect --format '{{range $port, $bindings := .NetworkSettings.Ports}}{{if eq $port "27017/tcp"}}{{range $bindings}}{{printf "%s:%s\n" .HostIp .HostPort}}{{end}}{{end}}{{end}}' "$container" 2>/dev/null | awk 'NF{print; exit}' || true)
  fi

  if [[ -n "$host_binding" ]]; then
    DB_PORT="${host_binding##*:}"
    ok "$container: porta DB host ${DB_PORT} (binding ${host_binding})"
    return 0
  fi

  if [[ -n "${INSTALL_ENV[DB_PORT]:-}" ]]; then
    DB_PORT="${INSTALL_ENV[DB_PORT]}"
    warn "$container: binding 27017/tcp non rilevato, uso DB_PORT dall'env install: $DB_PORT"
    return 0
  fi

  warn "$container: impossibile determinare la porta DB (27017/tcp)."
  return 1
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
    "installer_docker/installer.sh"
    "installer_docker/uss_healthcheck.sh"
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

find_update_check_config() {
  local base="$1"
  local candidate
  local -a candidates=(
    "$SCRIPT_DIR/.hypernode-update-check.conf"
    "$base/installer_docker/.hypernode-update-check.conf"
    "$base/.hypernode-update-check.conf"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf "%s" "$candidate"
      return 0
    fi
  done

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

read_config_var() {
  local file="$1" var_name="$2" result=""
  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # Usa una subshell bash per interpretare gli escape come farebbe la shell.
  result=$(bash -c 'set -a; source "$1"; v="$2"; printf "%s" "${!v}"' bash "$file" "$var_name" 2>/dev/null || true)
  if [[ -n "$result" ]]; then
    echo "$result"
    return 0
  fi

  return 1
}

parse_licensing_ports() {
  local response_file="$1" serial="$2"

  if [[ -z "$serial" ]]; then
    warn "Seriale non disponibile per l'analisi del payload /sites."
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 non disponibile: impossibile analizzare la risposta /sites."
    return 1
  fi

  local output
  output=$(python3 - "$response_file" "$serial" <<'PY'
import json, sys

resp_file, serial = sys.argv[1], sys.argv[2]
serial_norm = serial.strip().lower()

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from walk(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk(item)

try:
    with open(resp_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"⚠️  Impossibile leggere/parsare la risposta /sites: {exc}", file=sys.stdout)
    sys.exit(1)

match = None
for obj in walk(data):
    if not isinstance(obj, dict):
        continue
    serial_val = str(obj.get("serialno") or obj.get("serial") or "").strip().lower()
    if serial_val == serial_norm:
        site_port = obj.get("site_port", "n/d")
        site_lan_port = obj.get("site_lan_port", "n/d")
        status = obj.get("status", "n/d")
        is_uss = obj.get("is_uss", "n/d")
        print(f"MSG:✅ Licensing /sites -> serial {serial}: site_port={site_port}, site_lan_port={site_lan_port}, status={status}, is_uss={is_uss}")
        print(f"SITE_PORT:{site_port}")
        print(f"SITE_LAN_PORT:{site_lan_port}")
        print(f"STATUS:{status}")
        print(f"IS_USS:{is_uss}")
        sys.exit(0)

print(f"MSG:⚠️  Nessun record con serial '{serial}' trovato nella risposta /sites.")
sys.exit(1)
PY
  ) || true

  if [[ -n "$output" ]]; then
    echo "$output"
  fi
}

licensing_sites_check() {
  local url="$1" login="$2" password="$3" serial="$4"
  if [[ -z "$url" || -z "$login" || -z "$password" || -z "$serial" ]]; then
    warn "Parametri licensing incompleti: salto chiamata /sites."
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl non disponibile: salto chiamata /sites."
    return 1
  fi

  local endpoint payload response_file error_file http_code masked_login masked_serial
  endpoint="${url%/}/sites"

  masked_login="$login"
  masked_serial="$serial"
  payload=$(USS_LOGIN="$login" USS_PASSWORD="$password" USS_SERIAL="$serial" python3 - <<'PY'
import json, os
print(json.dumps({
    "user_login": os.environ.get("USS_LOGIN", ""),
    "user_password": os.environ.get("USS_PASSWORD", ""),
    "serial": os.environ.get("USS_SERIAL", ""),
}))
PY
  ) || {
    warn "Impossibile costruire il payload JSON per /sites."
    return 1
  }

  response_file=$(mktemp)
  error_file=$(mktemp)

  http_code=$(curl -sS -o "$response_file" -w '%{http_code}' \
    -X POST "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>"$error_file" || true)

  if [[ "$http_code" == "200" ]]; then
    ok "Licensing /sites OK (HTTP 200) per serial $masked_serial, login $masked_login."
    local parsed line
    parsed=$(parse_licensing_ports "$response_file" "$serial")
    while IFS= read -r line; do
      case "$line" in
        SITE_PORT:*)
          SITE_PORT="${line#SITE_PORT:}"
          ;;
        SITE_LAN_PORT:*)
          SITE_LAN_PORT="${line#SITE_LAN_PORT:}"
          ;;
        STATUS:*)
          SITE_STATUS="${line#STATUS:}"
          ;;
        IS_USS:*)
          SITE_IS_USS="${line#IS_USS:}"
          ;;
        *)
          ;;
      esac
    done <<< "${parsed:-}"
  else
    local curl_err body
    curl_err=$(cat "$error_file")
    body=$(cat "$response_file")
    warn "Licensing /sites non OK (HTTP ${http_code:-n/d}) - err: ${curl_err:-n/d} body: ${body:-n/d}"
  fi

  rm -f "$response_file" "$error_file"
}

check_https_certificate() {
  local host="$1" port="$2"
  if [[ -z "$host" || -z "$port" ]]; then
    warn "Parametri mancanti per verifica certificato ($host:$port)."
    return 1
  fi

  local s_client_cmd output not_after verify_line verify_code expiry_info
  s_client_cmd="openssl s_client -servername \"$host\" -connect \"$host:$port\" < /dev/null"
  if command -v timeout >/dev/null 2>&1; then
    s_client_cmd="timeout 10 $s_client_cmd"
  fi

  output=$(bash -c "$s_client_cmd" 2>/dev/null || true)
  if [[ -z "$output" ]]; then
    warn "Impossibile leggere il certificato da $host:$port (handshake fallito)."
    return 1
  fi

  # Prova a estrarre la data di scadenza dal certificato.
  not_after=$(printf '%s\n' "$output" | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  if [[ -z "$not_after" ]]; then
    not_after=$(printf '%s\n' "$output" | awk '/notAfter=/{print $0; exit}' | sed 's/ *notAfter=//')
  fi
  verify_line=$(printf '%s\n' "$output" | grep -m1 'Verify return code')
  verify_code=$(echo "$verify_line" | awk -F: '{print $2}' | awk '{print $1}')

  if [[ -n "$not_after" ]] && command -v python3 >/dev/null 2>&1; then
    expiry_info=$(python3 - <<PY
import sys
from datetime import datetime, timezone

not_after = """$not_after"""
try:
    exp = datetime.strptime(not_after, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    delta = exp - now
    days = delta.days
    print(f"{not_after} (tra {days} giorni)")
except Exception as exc:
    print(not_after)
PY
    )
  else
    expiry_info="$not_after"
  fi

  if [[ "${verify_code:-1}" == "0" ]]; then
    ok "Certificato HTTPS valido per $host:$port (scadenza: ${expiry_info:-n/d})"
  else
    warn "Certificato HTTPS NON valido per $host:$port (verify code ${verify_code:-n/d}, scadenza: ${expiry_info:-n/d})"
  fi
}

diag_api_check() {
  local serial="$1" host="$2" port="$3" label="$4"

  if [[ -z "$serial" || -z "$host" || -z "$port" ]]; then
    warn "Parametri mancanti per diagnostica API ($label: serial/host/port)."
    return 1
  fi

  local url tmp_body tmp_err http_code
  url="https://${host}:${port}/api/v1/"

  info "Verifica API diagnostica $label: $url"

  tmp_body=$(mktemp)
  tmp_err=$(mktemp)
  http_code=$(curl -k -sS -o "$tmp_body" -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 --location "$url" 2>"$tmp_err" || true)

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    ok "API diagnostica $label raggiungibile (HTTP $http_code)."
    if [[ "$label" == "LAN" ]]; then
      REACH_LAN_OK="true"
    else
      REACH_WAN_OK="true"
    fi
  else
    if [[ "$label" == "WAN" ]]; then
      warn "API diagnostica WAN non raggiungibile (HTTP ${http_code:-n/d}): $(cat "$tmp_err")"
      REACH_WAN_OK="false"
      rm -f "$tmp_body" "$tmp_err"
      return 0
    fi
    warn "API diagnostica $label non raggiungibile/errore (HTTP ${http_code:-n/d}): $(cat "$tmp_err")"
    [[ "$label" == "LAN" ]] && REACH_LAN_OK="false"
    rm -f "$tmp_body" "$tmp_err"
    return 1
  fi

  local parse_out
  parse_out=$(python3 - "$tmp_body" "$serial" <<'PY'
import json, sys

body_file, serial = sys.argv[1], sys.argv[2]
serial_norm = serial.strip().lower()

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from walk(v)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk(item)

try:
    with open(body_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"⚠️  Impossibile leggere/parsare la risposta API: {exc}")
    sys.exit(1)

# Prova percorsi noti prima di ricorrere alla ricerca.
candidates = []
if isinstance(data, dict):
    if isinstance(data.get("server"), dict):
        candidates.append(data["server"])
    if isinstance(data.get("root"), dict) and isinstance(data["root"].get("server"), dict):
        candidates.append(data["root"]["server"])

server_serial = ""
for cand in candidates:
    val = str(cand.get("serial") or "").strip().lower()
    if val:
        server_serial = val
        break

if not server_serial:
    for obj in walk(data):
        if not isinstance(obj, dict):
            continue
        val = str(obj.get("serial") or "").strip().lower()
        if val:
            server_serial = val
            break

if not server_serial:
    print("⚠️  Campo server.serial assente nella risposta API.")
    sys.exit(1)

if server_serial == serial_norm:
    print(f"✅ API diagnostica: server.serial combacia ({server_serial}).")
    sys.exit(0)
else:
    print(f"⚠️  API diagnostica: server.serial={server_serial} non combacia con {serial_norm}.")
    sys.exit(1)
PY
  ) || true

  [[ -n "$parse_out" ]] && echo "$parse_out"
  rm -f "$tmp_body" "$tmp_err"
}

check_prerequisites

section "1) DOCKER"
ensure_docker_running
load_install_env || true

download_compose_sources
for compose in "${COMPOSE_SOURCES[@]:-}"; do
  parse_compose_container_names "$compose"
done
dedupe_array CONTAINERS
check_container_statuses || true

section "2) DATABASE"
find_database_port || true

section "3) SCRIPT NECESSARI"
if find_hypernode_dir; then
  ok "Cartella hypernode_deploy trovata: $HYPERNODE_DIR"
else
  error "Cartella hypernode_deploy non trovata nel sistema."
  exit 1
fi

if [[ -z "$ENV_LOG_FILE" ]]; then
  load_install_env "$HYPERNODE_DIR/$ENV_LOG_NAME" || true
fi

check_required_files "$HYPERNODE_DIR" || true

CONFIG_FILE="$(find_update_check_config "$HYPERNODE_DIR" || true)"
SERIAL_VALUE=""
USER_LOGIN_VALUE=""
USER_PASSWORD_VALUE=""
LICENSING_URL_VALUE=""

if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  SERIAL_VALUE=$(read_config_var "$CONFIG_FILE" "SERIAL" || true)
  USER_LOGIN_VALUE=$(read_config_var "$CONFIG_FILE" "USER_LOGIN" || true)
  USER_PASSWORD_VALUE=$(read_config_var "$CONFIG_FILE" "USER_PASSWORD" || true)
  LICENSING_URL_VALUE=$(read_config_var "$CONFIG_FILE" "LICENSING_URL" || true)
else
  warn "File di configurazione .hypernode-update-check.conf mancante."
fi

if [[ -n "$SERIAL_VALUE" ]]; then
  SERIAL_LOWER=$(echo "$SERIAL_VALUE" | tr '[:upper:]' '[:lower:]')
else
  if [[ -n "$CONFIG_FILE" ]]; then
    warn "Impossibile leggere SERIAL da $CONFIG_FILE."
  else
    warn "Impossibile leggere SERIAL dal file di configurazione."
  fi
fi

section "4) NETWORK"
subsection "4.1) IP"

LOCAL_IP=$(current_local_ip || true)
PUBLIC_IP=$(current_public_ip || true)
[[ -n "$LOCAL_IP" ]] && info "IP locale corrente: $LOCAL_IP" || warn "IP locale non determinato."
[[ -n "$PUBLIC_IP" ]] && info "IP pubblico corrente: $PUBLIC_IP" || warn "IP pubblico non determinato."

subsection "4.2) DNS"
if [[ -n "$SERIAL_LOWER" ]]; then
  LOCAL_HOST="${SERIAL_LOWER}.lan.omniaweb.cloud"
  PUBLIC_HOST="${SERIAL_LOWER}.my.omniaweb.cloud"
  compare_dns_ip "DNS LAN" "$LOCAL_HOST" "$LOCAL_IP"
  compare_dns_ip "DNS pubblico" "$PUBLIC_HOST" "$PUBLIC_IP"
else
  warn "Seriale non disponibile: impossibile verificare il DNS."
fi

subsection "4.3) PORTS"
licensing_sites_check "$LICENSING_URL_VALUE" "$USER_LOGIN_VALUE" "$USER_PASSWORD_VALUE" "$SERIAL_VALUE"
if [[ -n "$SITE_PORT" || -n "$SITE_LAN_PORT" ]]; then
  ok "serial ${SERIAL_VALUE:-n/d}: site_port=${SITE_PORT:-n/d}, site_lan_port=${SITE_LAN_PORT:-n/d}, status=${SITE_STATUS:-n/d}, is_uss=${SITE_IS_USS:-n/d}"
fi

LAN_HOST=""
WAN_HOST=""
if [[ -n "$SERIAL_LOWER" ]]; then
  LAN_HOST="${SERIAL_LOWER}.lan.omniaweb.cloud"
  WAN_HOST="${SERIAL_LOWER}.my.omniaweb.cloud"
fi

subsection "4.4) REACHABILITY"
subsection "4.4.1) LAN"
if [[ -n "$SERIAL_VALUE" && -n "$SITE_LAN_PORT" && "$SITE_LAN_PORT" != "n/d" ]]; then
  diag_api_check "$SERIAL_VALUE" "$LAN_HOST" "$SITE_LAN_PORT" "LAN"
else
  warn "Porta LAN o seriale non disponibili: salto diagnostica LAN."
fi

subsection "4.4.2) WAN"
if [[ -n "$SERIAL_VALUE" && -n "$SITE_PORT" && "$SITE_PORT" != "n/d" ]]; then
  diag_api_check "$SERIAL_VALUE" "$WAN_HOST" "$SITE_PORT" "WAN"
else
  warn "Porta WAN o seriale non disponibili: salto diagnostica WAN."
fi

subsection "4.5) CERTIFICATE"
if [[ -n "$LAN_HOST" && -n "$SITE_LAN_PORT" && "$SITE_LAN_PORT" != "n/d" ]]; then
  if [[ "$REACH_LAN_OK" == "true" ]]; then
    check_https_certificate "$LAN_HOST" "$SITE_LAN_PORT" || true
  else
    warn "Certificato LAN non verificato: API LAN non raggiungibile."
  fi
else
  warn "Certificato LAN non verificabile: host/porta mancanti."
fi

if [[ -n "$WAN_HOST" && -n "$SITE_PORT" && "$SITE_PORT" != "n/d" ]]; then
  if [[ "$REACH_WAN_OK" == "true" ]]; then
    check_https_certificate "$WAN_HOST" "$SITE_PORT" || true
  else
    info "Certificato WAN non verificato: endpoint non raggiungibile."
  fi
fi
