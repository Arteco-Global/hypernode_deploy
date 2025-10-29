#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"
DUMP_SCRIPT="$SCRIPT_DIR/dump-container-versions.sh"
CHECK_SCRIPT="$SCRIPT_DIR/check-container-updates.sh"
JSON_FILE="$SCRIPT_DIR/container_versions.json"
CONFIG_FILE="$SCRIPT_DIR/.hypernode-update-check.conf"
STATE_FILE="$SCRIPT_DIR/.hypernode-update-check.state"
LOG_FILE=${LOG_FILE:-"$SCRIPT_DIR/hypernode-update-check.log"}

DOCKER_USERNAME=""
DOCKER_PASSWORD=""
INTERVAL_SPEC=""
INTERVAL_SECONDS=""
USE_CONFIG="false"
REMOVE_SCHEDULE="false"

log() {
  local ts message
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  message=$*
  printf '[%s] %s\n' "$ts" "$message" >> "$LOG_FILE"
}

ensure_log_file() {
  umask 077
  if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "❌ Impossibile creare il file di log $LOG_FILE" >&2
    exit 1
  fi
  chmod 600 "$LOG_FILE" 2>/dev/null || true
}

ensure_log_file
log "---- Avvio script run-hypernode-update-check.sh"

parse_interval_to_seconds() {
  local value="$1"
  if [[ "$value" =~ ^([0-9]+)([smhd]?)$ ]]; then
    local number="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      ""|"m")
        echo $((number * 60))
        ;;
      s)
        echo "$number"
        ;;
      h)
        echo $((number * 3600))
        ;;
      d)
        echo $((number * 86400))
        ;;
      *)
        return 1
        ;;
    esac
  else
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-username=*)
      DOCKER_USERNAME="${1#*=}"
      shift
      ;;
    --docker-password=*)
      DOCKER_PASSWORD="${1#*=}"
      shift
      ;;
    --interval=*)
      INTERVAL_SPEC="${1#*=}"
      shift
      ;;
    --use-config)
      USE_CONFIG="true"
      shift
      ;;
    --remove-schedule)
      REMOVE_SCHEDULE="true"
      shift
      ;;
    *)
      log "Opzione non riconosciuta: $1"
      echo "Opzione non riconosciuta: $1" >&2
      exit 1
      ;;
  esac
done
if [[ "$REMOVE_SCHEDULE" != "true" ]]; then
  if [[ "$USE_CONFIG" == "true" ]]; then
    log "Modalità pianificata (--use-config) richiesta"
    if [ ! -f "$CONFIG_FILE" ]; then
      log "Configurazione pianificata non trovata ($CONFIG_FILE)"
      echo "❌ Configurazione pianificata non trovata ($CONFIG_FILE)." >&2
      exit 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [[ -z "${DOCKER_USERNAME:-}" || -z "${DOCKER_PASSWORD:-}" ]]; then
      log "Configurazione salvata priva delle credenziali Docker"
      echo "❌ La configurazione salvata non contiene le credenziali Docker." >&2
      exit 1
    fi

    if [[ -z "${INTERVAL_SECONDS:-}" ]]; then
      log "Configurazione salvata priva dell'intervallo"
      echo "❌ La configurazione salvata non contiene l'intervallo." >&2
      exit 1
    fi
    if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || (( INTERVAL_SECONDS <= 0 )); then
      log "Intervallo non valido nella configurazione salvata: ${INTERVAL_SECONDS:-}"
      echo "❌ L'intervallo salvato non è valido." >&2
      exit 1
    fi
    log "Intervallo recuperato dalla configurazione: ${INTERVAL_SECONDS}s"
  else
    log "Modalità manuale (parametri CLI) richiesta"
    if [[ -z "$DOCKER_USERNAME" || -z "$DOCKER_PASSWORD" ]]; then
      log "Credenziali mancanti nei parametri CLI"
      echo "❌ Specifica --docker-username e --docker-password." >&2
      exit 1
    fi

    if [[ -n "$INTERVAL_SPEC" ]]; then
      if ! INTERVAL_SECONDS=$(parse_interval_to_seconds "$INTERVAL_SPEC"); then
        log "Intervallo CLI non valido: $INTERVAL_SPEC"
        echo "❌ Valore di --interval non valido. Usa numeri con suffisso opzionale s|m|h|d (es. 30m, 2h)." >&2
        exit 1
      fi
      if (( INTERVAL_SECONDS <= 0 )); then
        log "Intervallo CLI non maggiore di zero: $INTERVAL_SPEC"
        echo "❌ L'intervallo deve essere maggiore di zero." >&2
        exit 1
      fi
      log "Intervallo impostato da CLI: $INTERVAL_SPEC (${INTERVAL_SECONDS}s)"
    else
      log "Nessun intervallo specificato: esecuzione singola senza pianificazione"
    fi
  fi

  if [[ -z "$INTERVAL_SECONDS" && "$USE_CONFIG" == "true" ]]; then
    log "Intervallo non definito durante l'esecuzione pianificata"
    echo "❌ Intervallo non definito nella configurazione." >&2
    exit 1
  fi

  if [ ! -f "$DUMP_SCRIPT" ]; then
    log "Script dump-container-versions.sh non trovato in $DUMP_SCRIPT"
    echo "❌ Script $DUMP_SCRIPT non trovato." >&2
    exit 1
  fi

  if [ ! -f "$CHECK_SCRIPT" ]; then
    log "Script check-container-updates.sh non trovato in $CHECK_SCRIPT"
    echo "❌ Script $CHECK_SCRIPT non trovato." >&2
    exit 1
  fi
fi

maybe_skip_for_interval() {
  if [[ -z "$INTERVAL_SECONDS" || "$USE_CONFIG" != "true" ]]; then
    return 0
  fi

  local now last_run diff
  now=$(date +%s)

  if [[ -f "$STATE_FILE" ]]; then
    last_run=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  else
    last_run=0
  fi

  if [[ -z "$last_run" ]]; then
    last_run=0
  fi

  diff=$((now - last_run))

  if (( diff < INTERVAL_SECONDS )); then
    log "Esecuzione saltata: ultimi ${diff}s, intervallo ${INTERVAL_SECONDS}s"
    exit 0
  fi
}

update_last_run() {
  if [[ -z "$INTERVAL_SECONDS" ]]; then
    return
  fi

  local now
  now=$(date +%s)
  umask 077
  local tmp_file
  tmp_file=$(mktemp)
  printf '%s\n' "$now" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
  log "Timestamp ultima esecuzione aggiornato a $now"
}

write_config() {
  if [[ -z "$INTERVAL_SECONDS" ]]; then
    return
  fi

  umask 077
  local tmp_file
  tmp_file=$(mktemp)
  {
    printf 'DOCKER_USERNAME=%q\n' "$DOCKER_USERNAME"
    printf 'DOCKER_PASSWORD=%q\n' "$DOCKER_PASSWORD"
    printf 'INTERVAL_SECONDS=%q\n' "$INTERVAL_SECONDS"
    printf 'SCRIPT_PATH=%q\n' "$SCRIPT_PATH"
  } > "$tmp_file"
  mv "$tmp_file" "$CONFIG_FILE"
  log "Configurazione salvata in $CONFIG_FILE (intervallo ${INTERVAL_SECONDS}s)"
}

install_cron_job() {
  if [[ -z "$INTERVAL_SECONDS" ]]; then
    return
  fi

  if ! command -v crontab >/dev/null 2>&1; then
    log "crontab non disponibile; impossibile configurare la pianificazione automatica"
    echo "⚠️  crontab non disponibile; impossibile configurare la pianificazione automatica." >&2
    return
  fi

  local marker="# hypernode-update-check"
  local cron_cmd="\"$SCRIPT_PATH\" --use-config"
  local cron_entry="* * * * * /bin/bash -lc '$cron_cmd' $marker"
  local tmp_file

  tmp_file=$(mktemp)
  crontab -l 2>/dev/null | grep -v "$marker" > "$tmp_file" || true
  echo "$cron_entry" >> "$tmp_file"
  crontab "$tmp_file"
  rm -f "$tmp_file"
  log "Voce cron installata per esecuzione periodica"
}

remove_cron_job() {
  if ! command -v crontab >/dev/null 2>&1; then
    log "crontab non disponibile; nessuna pianificazione da rimuovere"
    return
  fi

  local marker="# hypernode-update-check"
  local current tmp_file
  current=$(crontab -l 2>/dev/null || true)

  if [[ -z "$current" || "$current" != *"$marker"* ]]; then
    log "Nessuna voce cron da rimuovere"
    return
  fi

  tmp_file=$(mktemp)
  printf '%s\n' "$current" | grep -v "$marker" > "$tmp_file" || true
  crontab "$tmp_file"
  rm -f "$tmp_file"
  log "Voce cron rimossa"
}

if [[ "$REMOVE_SCHEDULE" == "true" ]]; then
  log "Richiesta di rimozione pianificazione ricevuta"
  remove_cron_job
  rm -f "$CONFIG_FILE" "$STATE_FILE"
  log "File di configurazione e stato rimossi"
  echo "✅ Pianificazione automatica disattivata."
  exit 0
fi

maybe_skip_for_interval

chmod +x "$DUMP_SCRIPT"
log "Esecuzione di $DUMP_SCRIPT"
"$DUMP_SCRIPT"

if ! command -v jq >/dev/null 2>&1; then
  log "jq non trovato: avvio installazione tramite apt-get"
  echo "ℹ️  jq non trovato, provo ad installarlo tramite apt-get..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y jq
  else
    apt-get update
    apt-get install -y jq
  fi
  log "Installazione jq completata"
fi

chmod +x "$CHECK_SCRIPT"
log "Esecuzione di $CHECK_SCRIPT"
DOCKER_USERNAME="$DOCKER_USERNAME" DOCKER_PASSWORD="$DOCKER_PASSWORD" JSON_FILE="$JSON_FILE" "$CHECK_SCRIPT"

update_last_run

if [[ "$USE_CONFIG" != "true" ]]; then
  write_config
  install_cron_job
fi

log "Esecuzione completata"
