#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY_DIR="$(cd "${INSTALLER_DIR}/.." && pwd)"

DEPLOY_BRANCH="${DEPLOY_BRANCH:-feature/userAndPasswordProtection}"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
NATIVE_UPDATE_URL=""

ENV_FILE_DEFAULT="${PWD}/.hypernode-install-env.log"
if [[ ! -f "$ENV_FILE_DEFAULT" && -f "${DEPLOY_DIR}/.hypernode-install-env.log" ]]; then
  ENV_FILE_DEFAULT="${DEPLOY_DIR}/.hypernode-install-env.log"
fi
ENV_FILE="${ENV_FILE:-$ENV_FILE_DEFAULT}"

NEW_USER="hypernode"
OLD_DB_USER="hypernode"
OLD_DB_PASS="hypernode"
NATIVE_UPDATE_PATH="${PWD}/native_update.sh"

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*"
}

die() {
  printf '❌ %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --deploy-branch <name>   Branch da usare per scaricare/avviare native_update.sh
                           (default: feature/userAndPasswordProtection)
  -h, --help               Mostra questo help
EOF
}

generate_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 12
    return
  fi

  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12
}

strip_quotes() {
  local v="$1"
  v="${v#\"}"
  v="${v%\"}"
  v="${v#\'}"
  v="${v%\'}"
  printf '%s' "$v"
}

get_env_raw_value() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi

  awk -F= -v k="$key" '
    BEGIN { val="" }
    $0 ~ "^[[:space:]]*"k"=" {
      sub(/^[[:space:]]*[^=]+=/, "", $0)
      val=$0
    }
    END { print val }
  ' "$ENV_FILE"
}

upsert_env_key() {
  local key="$1"
  local value="$2"
  local tmp found line

  tmp="$(mktemp)"
  found=0

  if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^[[:space:]]*$key= ]]; then
        if [[ "$found" -eq 0 ]]; then
          printf "%s='%s'\n" "$key" "$value" >> "$tmp"
          found=1
        fi
        continue
      fi
      printf '%s\n' "$line" >> "$tmp"
    done < "$ENV_FILE"
  else
    :
  fi

  if [[ "$found" -eq 0 ]]; then
    printf "%s='%s'\n" "$key" "$value" >> "$tmp"
  fi

  mv "$tmp" "$ENV_FILE"
}

update_uri_credentials() {
  local key="$1"
  local scheme_regex="$2"
  local default_value="$3"
  local current cleaned new_value

  current="$(get_env_raw_value "$key")"
  cleaned="$(strip_quotes "$current")"

  if [[ -z "$cleaned" ]]; then
    new_value="$default_value"
  elif [[ "$cleaned" =~ ^(${scheme_regex})://[^@]+@(.+)$ ]]; then
    new_value="${BASH_REMATCH[1]}://${NEW_USER}:${NEW_PASSWORD}@${BASH_REMATCH[2]}"
  elif [[ "$cleaned" =~ ^(${scheme_regex})://(.+)$ ]]; then
    new_value="${BASH_REMATCH[1]}://${NEW_USER}:${NEW_PASSWORD}@${BASH_REMATCH[2]}"
  else
    new_value="$default_value"
  fi

  upsert_env_key "$key" "$new_value"
}

ensure_env_updates() {
  [[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"

  upsert_env_key "DOCKER_TAG" "userAndPasswordProtection"
  upsert_env_key "RABBITMQ_DEFAULT_USER" "$NEW_USER"
  upsert_env_key "RABBITMQ_DEFAULT_PASS" "$NEW_PASSWORD"
  upsert_env_key "DB_USERNAME" "$NEW_USER"
  upsert_env_key "DB_PASSWORD" "$NEW_PASSWORD"

  update_uri_credentials "RMQ" "amqp|amqps" "amqp://${NEW_USER}:${NEW_PASSWORD}@messagebroker:5672"

  local current_db_name="gateway-db"
  local current_db_uri
  current_db_uri="$(strip_quotes "$(get_env_raw_value "DATABASE_URI")")"
  if [[ "$current_db_uri" =~ ^mongodb://[^@]+@[^/]+/([^?]+)(\?.*)?$ ]]; then
    current_db_name="${BASH_REMATCH[1]}"
  fi

  update_uri_credentials "DATABASE_URI" "mongodb" "mongodb://${NEW_USER}:${NEW_PASSWORD}@127.0.0.1:27017/${current_db_name}?authSource=admin"
  update_uri_credentials "LOCAL_DB_CONNECTION" "mongodb" "mongodb://${NEW_USER}:${NEW_PASSWORD}@127.0.0.1:27017/exports?authSource=admin"
}

find_mongo_containers() {
  docker ps --format '{{.Names}} {{.Image}}' | awk '
    {
      name=$1
      image=$2
      if (tolower(image) ~ /mongo/) {
        print name
      }
    }
  '
}

update_credentials_in_db_container() {
  local container="$1"
  local shell_bin=""
  local db_cli=""

  if docker exec "$container" sh -lc 'command -v sh >/dev/null 2>&1'; then
    shell_bin="sh"
  elif docker exec "$container" bash -lc 'command -v bash >/dev/null 2>&1'; then
    shell_bin="bash"
  else
    warn "Container $container senza shell supportata: skip"
    return 1
  fi

  if ! db_cli="$(docker exec "$container" "$shell_bin" -lc 'if command -v mongosh >/dev/null 2>&1; then echo mongosh; elif command -v mongo >/dev/null 2>&1; then echo mongo; fi')"; then
    warn "Impossibile rilevare client mongo in $container: skip"
    return 1
  fi

  if [[ -z "$db_cli" ]]; then
    warn "Nessun client mongo (mongosh/mongo) nel container $container: skip"
    return 1
  fi

  docker exec \
    -e HN_NEW_USER="$NEW_USER" \
    -e HN_NEW_PASS="$NEW_PASSWORD" \
    -e HN_OLD_USER="$OLD_DB_USER" \
    -e HN_OLD_PASS="$OLD_DB_PASS" \
    "$container" "$shell_bin" -lc '
    set -e
    js="var adminDb=db.getSiblingDB(\"admin\"); \
    var user=process.env.HN_NEW_USER; \
    var pass=process.env.HN_NEW_PASS; \
    var exists=adminDb.getUser(user); \
    if (exists) { adminDb.updateUser(user,{pwd:pass,roles:[{role:\"root\",db:\"admin\"}]}); } \
    else { adminDb.createUser({user:user,pwd:pass,roles:[{role:\"root\",db:\"admin\"}]}); } \
    var adminUser=adminDb.getUser(\"admin\"); \
    if (adminUser) { adminDb.updateUser(\"admin\",{pwd:pass}); } \
    print(\"ok\");"

    if command -v mongosh >/dev/null 2>&1; then
      mongosh --quiet --host 127.0.0.1 --port 27017 \
        -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --eval "$js"
    else
      mongo --quiet --host 127.0.0.1 --port 27017 \
        -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --eval "$js"
    fi
  '
}

update_all_databases() {
  local containers=()
  local c

  if ! mapfile -t containers < <(find_mongo_containers); then
    warn "Errore durante la ricerca dei container MongoDB"
    return 1
  fi

  if [[ "${#containers[@]}" -eq 0 ]]; then
    warn "Nessun container MongoDB rilevato in esecuzione"
    return 0
  fi

  log "▶️  Aggiornamento credenziali DB su ${#containers[@]} container MongoDB"
  for c in "${containers[@]}"; do
    log "   - $c"
    if ! update_credentials_in_db_container "$c"; then
      warn "Aggiornamento credenziali fallito su $c"
    fi
  done
}

remove_messagebroker_and_volumes() {
  local ids=()
  local id
  local volumes=()
  local v

  if ! mapfile -t ids < <(docker ps -aq --filter name='(^|[-_])messagebroker($|[-_])'); then
    warn "Impossibile enumerare container messagebroker"
    return 1
  fi

  if [[ "${#ids[@]}" -eq 0 ]]; then
    log "ℹ️  Nessun container messagebroker trovato"
    return 0
  fi

  for id in "${ids[@]}"; do
    mapfile -t volumes < <(docker inspect "$id" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' | awk 'NF')
    log "▶️  Rimozione container messagebroker: $id"
    docker rm -f "$id" >/dev/null

    for v in "${volumes[@]}"; do
      if [[ -n "$v" ]]; then
        log "   🧹 Rimozione volume: $v"
        docker volume rm "$v" >/dev/null 2>&1 || warn "Volume $v non rimosso (forse già assente/in uso)"
      fi
    done
  done
}

download_native_update() {
  log "⬇️  Download native_update.sh da: $NATIVE_UPDATE_URL"

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$NATIVE_UPDATE_PATH" "$NATIVE_UPDATE_URL" || die "Download fallito: $NATIVE_UPDATE_URL"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$NATIVE_UPDATE_URL" -o "$NATIVE_UPDATE_PATH" || die "Download fallito: $NATIVE_UPDATE_URL"
  else
    die "Né wget né curl disponibili"
  fi

  chmod +x "$NATIVE_UPDATE_PATH"
}

prompt_and_run_update() {
  local answer=""

  printf '\n✅ Preparazione completata.\n'
  printf '   Nuova password generata: %s\n' "$NEW_PASSWORD"
  printf '\nProcedere ora con native_update.sh? [y/N]: '
  read -r answer

  case "$answer" in
    y|Y|yes|YES)
      log "▶️  Avvio $NATIVE_UPDATE_PATH"
      "$NATIVE_UPDATE_PATH" --env-file "$ENV_FILE" --deploy-branch "$DEPLOY_BRANCH"
      ;;
    *)
      log "ℹ️  Update non avviato. Puoi eseguirlo manualmente con: $NATIVE_UPDATE_PATH --env-file $ENV_FILE --deploy-branch $DEPLOY_BRANCH"
      ;;
  esac
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deploy-branch)
        DEPLOY_BRANCH="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Parametro non riconosciuto: $1"
        ;;
    esac
  done

  NATIVE_UPDATE_URL="${ABSOLUTE_PATH_BASE}/${DEPLOY_BRANCH}/installer_docker/native_update.sh"

  [[ -f "$ENV_FILE" ]] || warn "Env file non trovato: $ENV_FILE (verrà creato)"

  if ! command -v docker >/dev/null 2>&1; then
    die "Docker non disponibile"
  fi

  NEW_PASSWORD="${NEW_PASSWORD:-$(generate_password)}"
  [[ -n "$NEW_PASSWORD" ]] || die "Impossibile generare password dinamica"

  log "▶️  Password dinamica generata"
  update_all_databases
  remove_messagebroker_and_volumes
  ensure_env_updates
  download_native_update
  prompt_and_run_update
}

main "$@"
