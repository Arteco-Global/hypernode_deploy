#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [rclone_mounter] $*"
}

log "Avvio montaggio rclone..."

# Crea directory necessarie
mkdir -p /config/rclone "$RCLONE_CACHE_DIR" "$MOUNT_PATH"

# Decodifica la configurazione
if [ -n "${RCLONE_CONFIG_BASE64:-}" ]; then
  echo "$RCLONE_CONFIG_BASE64" | base64 -d > /config/rclone/rclone.conf
  log "File rclone.conf decodificato in /config/rclone"
else
  log "⚠️  Variabile RCLONE_CONFIG_BASE64 vuota! Il mount fallirà se non configurata."
fi

# Mostra info di base per debug
log "REMOTE = ${GDRIVE_REMOTE:-<vuoto>}"
log "GDRIVE_PATH = ${GDRIVE_PATH:-<vuoto>}"
log "MOUNT_PATH = ${MOUNT_PATH:-<vuoto>}"
log "CACHE_DIR = ${RCLONE_CACHE_DIR:-<vuoto>}"

export RCLONE_CONFIG=/config/rclone/rclone.conf
REMOTE="${GDRIVE_REMOTE}:${GDRIVE_PATH}"

log "Tentativo di montaggio di $REMOTE su $MOUNT_PATH"

# Smonta eventuale mount precedente
if mountpoint -q "$MOUNT_PATH"; then
  log "Smonto mount precedente..."
  fusermount -u "$MOUNT_PATH" || true
fi

# Verifica che rclone veda il remote
if rclone ls "$REMOTE" >/dev/null 2>&1; then
  log "✅ Connessione a $REMOTE verificata."
else
  log "❌ ERRORE: rclone non riesce a listare il remote $REMOTE"
  log "Controlla che le credenziali siano corrette o la connessione a Internet disponibile."
fi

# Avvia il mount
log "Eseguo il comando rclone mount..."
exec rclone mount "$REMOTE" "$MOUNT_PATH" \
  --allow-other \
  --dir-cache-time 1m \
  --vfs-cache-mode full \
  --vfs-cache-max-age 5m \
  --vfs-cache-max-size 512M \
  --cache-dir "$RCLONE_CACHE_DIR" \
  --poll-interval 30s \
  --drive-chunk-size 64M \
  --transfers 4 \
  --checkers 8 \
  --log-level DEBUG \
  --log-file /config/rclone/mount.log
