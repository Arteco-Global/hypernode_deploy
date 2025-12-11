#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.hypernode-update-check.conf"
STATE_FILE="$SCRIPT_DIR/.hypernode-update-check.state"
RUN_CHECK_SCRIPT="$SCRIPT_DIR/run-hypernode-update-check.sh"
WATCHTOWER_IMAGE="containrrr/watchtower:1.7.1"
ABSOLUTE_PATH="${ABSOLUTE_PATH:-https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/composes}"
COMPOSE_FILES=(
  "$SCRIPT_DIR/composes/server/docker-compose.yaml"
  "$SCRIPT_DIR/composes/database/docker-compose.yaml"
)
COMPOSE_URLS=(
  "$ABSOLUTE_PATH/server/docker-compose.yaml"
  "$ABSOLUTE_PATH/database/docker-compose.yaml"
)
DEBUG_LOG="${DEBUG_LOG:-0}"

DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"
DOCKER_CONFIG_DIR="${DOCKER_CONFIG_DIR:-}"
USER_LOGIN="${USER_LOGIN:-}"
USER_PASSWORD="${USER_PASSWORD:-}"
SERIAL="${SERIAL:-}"
LICENSING_URL="${LICENSING_URL:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-}"
LOGIN_PERFORMED="false"
TEMP_CONFIG_DIR=""
COMPOSE_TMP_FILES=()

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker non è disponibile sul sistema." >&2
  exit 1
fi

if [[ ! -f "$RUN_CHECK_SCRIPT" ]]; then
  echo "❌ Script $RUN_CHECK_SCRIPT non trovato." >&2
  exit 1
fi

if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin >/dev/null
  LOGIN_PERFORMED="true"
  echo "ℹ️  Login Docker effettuato con l'utente $DOCKER_USERNAME."
else
  echo "ℹ️  Nessuna credenziale Docker fornita: salto il login." >&2
fi

cleanup() {
  if [[ -n "$TEMP_CONFIG_DIR" && -d "$TEMP_CONFIG_DIR" ]]; then
    rm -rf "$TEMP_CONFIG_DIR"
  fi
  for tmp in "${COMPOSE_TMP_FILES[@]:-}"; do
    [[ -f "$tmp" ]] && rm -f "$tmp"
  done
  if [[ "$LOGIN_PERFORMED" == "true" ]]; then
    docker logout >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

if [[ "$DEBUG_LOG" == "1" ]]; then
  set -x
fi
echo "▶️  Avvio update_uss.sh"

HYPERNODE_CONTAINERS=()
BROKER_CONTAINER="messagebroker"
PORTBROKER_CONTAINER="portbroker"
WEBSERVER_CONTAINER="webserver"
DATABASE_CONTAINER="USS_SERVER"
INDEPENDENT_CONTAINERS=()
COMPOSE_SOURCES=()
UPDATED_INDEPENDENT="false"

load_compose_sources() {
  local idx file url tmp
  for idx in "${!COMPOSE_FILES[@]}"; do
    file="${COMPOSE_FILES[$idx]}"
    url="${COMPOSE_URLS[$idx]}"

    if [[ -f "$file" ]]; then
      COMPOSE_SOURCES+=("$file")
      echo "ℹ️  Uso il compose locale: $file"
      continue
    fi

    tmp=$(mktemp)
    if curl -fsSL "$url" -o "$tmp"; then
      COMPOSE_SOURCES+=("$tmp")
      COMPOSE_TMP_FILES+=("$tmp")
      echo "ℹ️  Compose scaricato da $url"
    else
      echo "⚠️  Impossibile scaricare il compose da $url" >&2
      rm -f "$tmp"
    fi
  done
}

dedupe_arrays() {
  local -n arr_ref=$1
  local -A seen=()
  local new_arr=()

  for item in "${arr_ref[@]}"; do
    [[ -z "$item" ]] && continue
    if [[ -z "${seen[$item]:-}" ]]; then
      new_arr+=("$item")
      seen[$item]=1
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
        HYPERNODE_CONTAINERS+=("$name")
        if [[ "$current_service" == "messagebroker" ]]; then
          BROKER_CONTAINER="$name"
        elif [[ "$current_service" == "portbroker" ]]; then
          PORTBROKER_CONTAINER="$name"
        elif [[ "$current_service" == "webserver" ]]; then
          WEBSERVER_CONTAINER="$name"
        elif [[ "$current_service" == "database" ]]; then
          DATABASE_CONTAINER="$name"
          INDEPENDENT_CONTAINERS+=("$name")
        fi
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
    HYPERNODE_CONTAINERS+=("$name")
    if [[ "$current_service" == "messagebroker" ]]; then
      BROKER_CONTAINER="$name"
    elif [[ "$current_service" == "portbroker" ]]; then
      PORTBROKER_CONTAINER="$name"
    elif [[ "$current_service" == "webserver" ]]; then
      WEBSERVER_CONTAINER="$name"
    elif [[ "$current_service" == "database" ]]; then
      DATABASE_CONTAINER="$name"
      INDEPENDENT_CONTAINERS+=("$name")
    fi
  fi
}

container_exists() {
  docker ps -aq -f "name=^${1}$" | grep -q .
}

container_running() {
  docker ps -q -f "name=^${1}$" | grep -q .
}

wait_for_container_ready() {
  local name="$1"
  local timeout="${2:-180}"
  local start now status health last_log

  echo "⏳ Attendo che $name diventi pronto (timeout ${timeout}s)..."

  start=$(date +%s)
  last_log="$start"
  while true; do
    if ! container_exists "$name"; then
      echo "ℹ️  Container $name non trovato durante l'attesa." >&2
      return 1
    fi

    IFS="|" read -r status health <<< "$(docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name" 2>/dev/null || echo "unknown|")"

    if [[ "$health" == "healthy" ]] || { [[ "$status" == "running" ]] && [[ -z "$health" ]]; }; then
      echo "✅ $name pronto (stato: ${health:-$status})."
      return 0
    fi

    now=$(date +%s)
    if (( now - last_log >= 5 )); then
      echo "⏳ $name ancora in stato ${health:-$status}..."
      last_log="$now"
    fi
    if (( now - start >= timeout )); then
      echo "❌ Timeout in attesa che $name sia pronto (stato: ${health:-$status})." >&2
      return 1
    fi
    sleep 2
  done
}

ensure_container_running() {
  local name="$1"

  if ! container_exists "$name"; then
    return 1
  fi

  if ! container_running "$name"; then
    echo "🔄 Avvio $name (era fermo)..."
    docker start "$name" >/dev/null
  fi

  wait_for_container_ready "$name"
}

restart_container_ordered() {
  local name="$1"

  if ! container_exists "$name"; then
    echo "ℹ️  Container $name non presente, salto." >&2
    return 0
  fi

  if container_running "$name"; then
    echo "🔄 Riavvio $name..."
    docker restart "$name" >/dev/null
  else
    echo "🔄 Avvio $name..."
    docker start "$name" >/dev/null
  fi

  wait_for_container_ready "$name"
}

containers_restarted_since() {
  local since_ts="$1"
  local container started started_ts updated_independent="false"
  local -A independent_map=()
  local updated_stack="false"

  for container in "${INDEPENDENT_CONTAINERS[@]}"; do
    independent_map["$container"]=1
  done

  for container in "${HYPERNODE_CONTAINERS[@]}"; do
    started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null || true)
    if [[ -z "$started" ]]; then
      continue
    fi
    started_ts=$(date -d "$started" +%s 2>/dev/null || true)
    if [[ -n "$started_ts" && "$started_ts" -ge "$since_ts" ]]; then
      if [[ -n "${independent_map[$container]:-}" ]]; then
        updated_independent="true"
      else
        updated_stack="true"
      fi
    fi
  done

  if [[ "$updated_stack" == "true" ]]; then
    return 0
  fi

  if [[ "$updated_independent" == "true" ]]; then
    UPDATED_INDEPENDENT="true"
  fi

  return 1
}

restart_stack_in_dependency_order() {
  local services=()

  # Usa l'ordine del compose (HYPERNODE_CONTAINERS) escludendo broker e portbroker
  for svc in "${HYPERNODE_CONTAINERS[@]}"; do
    if [[ "$svc" == "$BROKER_CONTAINER" || "$svc" == "$PORTBROKER_CONTAINER" ]]; then
      continue
    fi
    services+=("$svc")
  done

  if [[ ${#services[@]} -eq 0 ]]; then
    services=(
      gateway
      camera
      coretrust
      storage
      recording
      event
      auth
      snapshot
      webserver
      configurator
    )
  fi

  if ! container_exists "$BROKER_CONTAINER"; then
    echo "ℹ️  Nessun container $BROKER_CONTAINER trovato: riavvio ordinato non eseguito." >&2
    return
  fi

  echo "ℹ️  Riavvio ordinato dei container per rispettare le dipendenze..."

  ensure_container_running "$BROKER_CONTAINER"

  for service in "${services[@]}"; do
    restart_container_ordered "$service"
  done

  if container_exists "$PORTBROKER_CONTAINER"; then
    wait_for_container_ready "$BROKER_CONTAINER"
    if container_exists "$WEBSERVER_CONTAINER"; then
      wait_for_container_ready "$WEBSERVER_CONTAINER"
    fi
    restart_container_ordered "$PORTBROKER_CONTAINER"
  fi
}

run_with_spinner() {
  local message="$1"
  shift

  local spin='|/-\\'
  local i=0
  local pid status

  "$@" &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    printf "\r[%c] %s" "${spin:i%4:1}" "$message"
    sleep 0.2
    ((i++))
  done

  # Non far fallire lo script con set -e se il comando termina con errore
  status=0
  if ! wait "$pid"; then
    status=$?
  fi

  if [[ $status -eq 0 ]]; then
    printf "\r✅ %s\n" "$message"
  else
    printf "\r❌ %s (exit %s)\n" "$message" "$status"
  fi

  return $status
}

if [[ -z "$DOCKER_CONFIG_DIR" ]]; then
  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    DOCKER_CONFIG_DIR="${DOCKER_CONFIG%/}"
  else
    DOCKER_CONFIG_DIR="$HOME/.docker"
  fi
fi

if [[ "$DOCKER_CONFIG_DIR" == */config.json ]]; then
  DOCKER_CONFIG_DIR="$(dirname "$DOCKER_CONFIG_DIR")"
fi

watchtower_args=(
  --rm
  -v "/var/run/docker.sock:/var/run/docker.sock"
)

# Docker 25+ removes support for API versions < 1.44. The bundled
# watchtower image still defaults to 1.25, so explicitly use the server
# API level to avoid "client version ... is too old" errors after an
# apt upgrade.
DOCKER_SERVER_API_VERSION="$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || true)"
if [[ -n "$DOCKER_SERVER_API_VERSION" ]]; then
  watchtower_args+=(
    -e "DOCKER_API_VERSION=$DOCKER_SERVER_API_VERSION"
  )
fi

if [[ -d "$DOCKER_CONFIG_DIR" && -f "$DOCKER_CONFIG_DIR/config.json" ]]; then
  watchtower_args+=(
    -v "$DOCKER_CONFIG_DIR:/config:ro"
    -e "DOCKER_CONFIG=/config"
  )
elif [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  TEMP_CONFIG_DIR=$(mktemp -d)
  auth_b64=$(printf '%s:%s' "$DOCKER_USERNAME" "$DOCKER_PASSWORD" | base64 | tr -d '\n')
  cat > "$TEMP_CONFIG_DIR/config.json" <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "$auth_b64"
    }
  }
}
EOF
  watchtower_args+=(
    -v "$TEMP_CONFIG_DIR:/config:ro"
    -e "DOCKER_CONFIG=/config"
  )
else
  echo "⚠️  Config Docker non trovato in $DOCKER_CONFIG_DIR/config.json e nessuna credenziale disponibile per generarlo: eseguo watchtower senza credenziali." >&2
fi

load_compose_sources || true
if [[ ${#COMPOSE_SOURCES[@]} -gt 0 ]]; then
  for compose in "${COMPOSE_SOURCES[@]}"; do
    echo "ℹ️  Carico servizi dal compose: $compose"
    if ! parse_compose_container_names "$compose"; then
      echo "⚠️  Impossibile leggere il compose $compose: userò elenco statico se nessun servizio viene trovato." >&2
    fi
  done
else
  echo "⚠️  Nessun compose disponibile: userò elenco statico." >&2
fi

dedupe_arrays HYPERNODE_CONTAINERS
dedupe_arrays INDEPENDENT_CONTAINERS

if [[ ${#HYPERNODE_CONTAINERS[@]} -eq 0 ]]; then
  HYPERNODE_CONTAINERS=(
    messagebroker
    gateway
    camera
    coretrust
    storage
    recording
    event
    auth
    snapshot
    webserver
    configurator
    portbroker
  )
  BROKER_CONTAINER="messagebroker"
  PORTBROKER_CONTAINER="portbroker"
  DATABASE_CONTAINER="USS_SERVER"
  INDEPENDENT_CONTAINERS=("$DATABASE_CONTAINER")
  echo "⚠️  Impossibile leggere i servizi dal compose: uso l'elenco statico." >&2
else
  echo "ℹ️  Servizi rilevati dal compose (${#HYPERNODE_CONTAINERS[@]}): ${HYPERNODE_CONTAINERS[*]}"
fi

WATCHTOWER_START_TS=$(date +%s)
echo "🚀 Lancio watchtower (one-shot)..."
WATCHTOWER_EXIT=0
if ! run_with_spinner "Watchtower in esecuzione..." docker run "${watchtower_args[@]}" "$WATCHTOWER_IMAGE" --run-once; then
  WATCHTOWER_EXIT=$?
  echo "❌ Watchtower terminato con errore (exit $WATCHTOWER_EXIT)."
else
  echo "✅ Watchtower terminato."
fi

if containers_restarted_since "$WATCHTOWER_START_TS"; then
  echo "ℹ️  Aggiornamenti rilevati: eseguo riavvio ordinato."
  restart_stack_in_dependency_order
else
  if [[ "$UPDATED_INDEPENDENT" == "true" ]]; then
    echo "ℹ️  Aggiornamenti rilevati solo su container indipendenti (es. database): nessun riavvio dello stack necessario."
  fi
  echo "ℹ️  Nessun container aggiornato da watchtower: salto il riavvio ordinato." >&2
fi

if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" && -n "$USER_LOGIN" && -n "$USER_PASSWORD" && -n "$SERIAL" && -n "$LICENSING_URL" ]]; then
  "$RUN_CHECK_SCRIPT" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --user-login="$USER_LOGIN" \
    --user-password="$USER_PASSWORD" \
    --serial="$SERIAL" \
    --licensing-url="$LICENSING_URL" \
    ${INTERVAL_SECONDS:+--interval="${INTERVAL_SECONDS}s"}
else
  rm -f "$STATE_FILE"
  "$RUN_CHECK_SCRIPT" --use-config
fi
