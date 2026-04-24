#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

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
OLD_DB_USER="${OLD_DB_USER:-}"
OLD_DB_PASS="${OLD_DB_PASS:-}"
NATIVE_UPDATE_PATH="${PWD}/native_update.sh"

log() {
  printf '%s\n' "$*"
}

log_db() {
  printf '[DB] %s\n' "$*"
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
  local containers=()

  if mapfile -t containers < <(
    docker ps --format '{{.Names}}|{{.Image}}|{{.Ports}}' | awk -F'|' '
      {
        name=tolower($1)
        image=tolower($2)
        ports=tolower($3)
        if (image ~ /mongo/ ||
            image ~ /database/ ||
            image ~ /usee_database/ ||
            name ~ /mongo/ ||
            name ~ /database/ ||
            name ~ /uss_database/ ||
            ports ~ /27017/) {
          print $1
        }
      }
    ' | awk 'NF' | sort -u
  ); then
    printf '%s\n' "${containers[@]}"
    return 0
  fi

  return 1
}

update_credentials_in_db_container() {
  local container="$1"
  local shell_bin=""
  local db_cli=""
  local output=""
  local retry_output=""
  local inspect_image=""
  local inspect_status=""

  inspect_image="$(docker inspect -f '{{.Config.Image}}' "$container" 2>/dev/null || true)"
  inspect_status="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
  log_db "Container: $container | image: ${inspect_image:-unknown} | status: ${inspect_status:-unknown}"

  if docker exec "$container" sh -lc 'command -v sh >/dev/null 2>&1'; then
    shell_bin="sh"
  elif docker exec "$container" bash -lc 'command -v bash >/dev/null 2>&1'; then
    shell_bin="bash"
  else
    warn "Container $container senza shell supportata: skip"
    return 1
  fi
  log_db "Shell rilevata in $container: $shell_bin"

  if ! db_cli="$(docker exec "$container" "$shell_bin" -lc 'if command -v mongosh >/dev/null 2>&1; then echo mongosh; elif command -v mongo >/dev/null 2>&1; then echo mongo; fi')"; then
    warn "Impossibile rilevare client mongo in $container: skip"
    return 1
  fi

  if [[ -z "$db_cli" ]]; then
    warn "Nessun client mongo (mongosh/mongo) nel container $container: skip"
    return 1
  fi

  log_db "Client DB rilevato in $container: $db_cli"
  log_db "Tentativo update utenti su DB admin senza autenticazione"

  if output="$(
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
    var dbNames=adminDb.getMongo().getDBNames(); \
    for (var i=0;i<dbNames.length;i++) { \
      var dbName=dbNames[i]; \
      if (dbName === \"admin\" || dbName === \"local\" || dbName === \"config\") { continue; } \
      try { \
        var targetDb=db.getSiblingDB(dbName); \
        var colls=targetDb.getCollectionNames(); \
        if (colls.indexOf(\"microservicesInstanceConfiguration\") === -1) { \
          print(\"broker_update db=\" + dbName + \" updated=0 (collection_missing)\"); \
          continue; \
        } \
        var coll=targetDb.getCollection(\"microservicesInstanceConfiguration\"); \
        var cursor=coll.find({ broker: { \\$type: \"string\" } }, { broker: 1 }); \
        var updated=0; \
        while (cursor.hasNext()) { \
          var doc=cursor.next(); \
          var broker=doc.broker; \
          var newBroker=broker; \
          if (/^(amqps?):\\/\\/[^@]+@(.+)$/.test(broker)) { \
            newBroker=broker.replace(/^(amqps?):\\/\\/[^@]+@(.+)$/, \"$1://\" + user + \":\" + pass + \"@$2\"); \
          } else if (/^(amqps?):\\/\\/(.+)$/.test(broker)) { \
            newBroker=broker.replace(/^(amqps?):\\/\\/(.+)$/, \"$1://\" + user + \":\" + pass + \"@$2\"); \
          } \
          if (newBroker !== broker) { \
            coll.updateOne({ _id: doc._id }, { \\$set: { broker: newBroker } }); \
            updated++; \
          } \
        } \
        print(\"broker_update db=\" + dbName + \" updated=\" + updated); \
      } catch (e) { \
        print(\"broker_update db=\" + dbName + \" error=\" + e); \
      } \
    } \
    print(\"ok\");"

    if command -v mongosh >/dev/null 2>&1; then
      mongosh --quiet --host 127.0.0.1 --port 27017 --eval "$js"
    else
      mongo --quiet --host 127.0.0.1 --port 27017 --eval "$js"
    fi
  '
  2>&1
  )"; then
    if grep -Eqi 'Authentication failed|MongoServerError|Error:' <<< "$output"; then
      warn "Il comando DB su $container ha riportato errori nonostante exit code 0"
      while IFS= read -r line; do
        [[ -n "$line" ]] && warn "[DB:$container] $line"
      done <<< "$output"
    elif grep -Eiq '(^|[[:space:]])ok($|[[:space:]])' <<< "$output"; then
      log_db "Update credenziali completato su $container"
      while IFS= read -r line; do
        [[ -n "$line" ]] && log_db "Output $container: $line"
      done <<< "$output"
      return 0
    else
      warn "Output inatteso dal comando DB su $container"
      while IFS= read -r line; do
        [[ -n "$line" ]] && warn "[DB:$container] $line"
      done <<< "$output"
    fi
  fi

  if [[ -n "$OLD_DB_USER" && -n "$OLD_DB_PASS" ]]; then
    log_db "Retry su $container con autenticazione ${OLD_DB_USER}/********"
    if retry_output="$(
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
      var dbNames=adminDb.getMongo().getDBNames(); \
      for (var i=0;i<dbNames.length;i++) { \
        var dbName=dbNames[i]; \
        if (dbName === \"admin\" || dbName === \"local\" || dbName === \"config\") { continue; } \
        try { \
          var targetDb=db.getSiblingDB(dbName); \
          var colls=targetDb.getCollectionNames(); \
          if (colls.indexOf(\"microservicesInstanceConfiguration\") === -1) { \
            print(\"broker_update db=\" + dbName + \" updated=0 (collection_missing)\"); \
            continue; \
          } \
          var coll=targetDb.getCollection(\"microservicesInstanceConfiguration\"); \
          var cursor=coll.find({ broker: { \\$type: \"string\" } }, { broker: 1 }); \
          var updated=0; \
          while (cursor.hasNext()) { \
            var doc=cursor.next(); \
            var broker=doc.broker; \
            var newBroker=broker; \
            if (/^(amqps?):\\/\\/[^@]+@(.+)$/.test(broker)) { \
              newBroker=broker.replace(/^(amqps?):\\/\\/[^@]+@(.+)$/, \"$1://\" + user + \":\" + pass + \"@$2\"); \
            } else if (/^(amqps?):\\/\\/(.+)$/.test(broker)) { \
              newBroker=broker.replace(/^(amqps?):\\/\\/(.+)$/, \"$1://\" + user + \":\" + pass + \"@$2\"); \
            } \
            if (newBroker !== broker) { \
              coll.updateOne({ _id: doc._id }, { \\$set: { broker: newBroker } }); \
              updated++; \
            } \
          } \
          print(\"broker_update db=\" + dbName + \" updated=\" + updated); \
        } catch (e) { \
          print(\"broker_update db=\" + dbName + \" error=\" + e); \
        } \
      } \
      print(\"ok\");"

      if command -v mongosh >/dev/null 2>&1; then
        mongosh --quiet --host 127.0.0.1 --port 27017 \
          -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --eval "$js"
      else
        mongo --quiet --host 127.0.0.1 --port 27017 \
          -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --eval "$js"
      fi
    ' 2>&1
    )"; then
      if grep -Eqi 'Authentication failed|MongoServerError|Error:' <<< "$retry_output"; then
        warn "Retry autenticato su $container con output errore"
      elif grep -Eiq '(^|[[:space:]])ok($|[[:space:]])' <<< "$retry_output"; then
        log_db "Update credenziali completato su $container (retry autenticato)"
        while IFS= read -r line; do
          [[ -n "$line" ]] && log_db "Output $container: $line"
        done <<< "$retry_output"
        return 0
      fi
    fi

    if [[ -n "$retry_output" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && warn "[DB:$container] $line"
      done <<< "$retry_output"
    fi
  else
    log_db "Fallback autenticato disabilitato (OLD_DB_USER/OLD_DB_PASS non impostati)"
  fi

  if [[ -n "$output" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && log_db "Output $container: $line"
    done <<< "$output"
  fi

  warn "Update credenziali fallito su $container"
  return 1
}

update_all_databases() {
  local containers=()
  local c
  local total=0
  local ok_count=0
  local fail_count=0

  if ! mapfile -t containers < <(find_mongo_containers); then
    warn "Errore durante la ricerca dei container MongoDB"
    return 1
  fi

  if [[ "${#containers[@]}" -eq 0 ]]; then
    warn "Nessun container MongoDB rilevato in esecuzione"
    return 0
  fi

  total="${#containers[@]}"
  log "▶️  Aggiornamento credenziali DB su ${total} container MongoDB"
  for c in "${containers[@]}"; do
    log_db "-----"
    if update_credentials_in_db_container "$c"; then
      ok_count=$((ok_count + 1))
    else
      fail_count=$((fail_count + 1))
    fi
  done

  log_db "Riepilogo update DB: total=${total}, ok=${ok_count}, fail=${fail_count}"
  if [[ "$fail_count" -gt 0 ]]; then
    warn "Alcuni database non sono stati aggiornati correttamente (${fail_count}/${total})"
  fi
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
