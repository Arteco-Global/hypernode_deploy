#!/usr/bin/env bash
set -u

# ----------------------------
# Configurazione
# ----------------------------
CHECK_INTERVAL_SEC=15
STALE_MS=120000
ACTIVE_WINDOW_MIN=10
LOG_SINCE="8m"
LOG_DUMP_COOLDOWN_SEC=120

DB_CONTAINER="uss_database"
DB_NAME="recording-db"
RECORDING_CONTAINER="recording"
GATEWAY_CONTAINER="gateway"
PROFILE_REGEX="^DefaultProfile-"

# ----------------------------
# Stato interno
# ----------------------------
last_fingerprint=""
last_dump_epoch=0

echo "[watch-recording-stale] start $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "[watch-recording-stale] interval=${CHECK_INTERVAL_SEC}s staleMs=${STALE_MS} activeWindow=${ACTIVE_WINDOW_MIN}m logSince=${LOG_SINCE}"

while true; do
  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  now_epoch="$(date +%s)"

  mongo_out="$(sudo docker exec "${DB_CONTAINER}" mongosh --quiet "${DB_NAME}" --eval "
const now = new Date();
const activeSince = new Date(now.getTime() - (${ACTIVE_WINDOW_MIN} * 60 * 1000));
const stale = db.storedRecordingsChunkInfo.aggregate([
  { \$match: { startTime: { \$gte: activeSince }, profileToken: { \$regex: '${PROFILE_REGEX}' } } },
  { \$group: { _id: { chId: '\$chId', profileToken: '\$profileToken' }, lastEnd: { \$max: '\$endTime' } } },
  { \$project: { _id: 0, chId: '\$_id.chId', profileToken: '\$_id.profileToken', lastEnd: 1, deltaMs: { \$subtract: [now, '\$lastEnd'] } } },
  { \$match: { deltaMs: { \$gt: ${STALE_MS} } } },
  { \$sort: { deltaMs: -1 } }
]).toArray();
print('stale_count=' + stale.length);
stale.forEach(s => print(s.chId + ' ' + s.profileToken + ' deltaMs=' + s.deltaMs + ' lastEnd=' + s.lastEnd.toISOString()));
")"

  stale_count="$(printf "%s\n" "${mongo_out}" | awk -F= '/^stale_count=/{print $2; exit}')"
  if [ -z "${stale_count}" ]; then
    stale_count=0
  fi

  echo "[${now_utc}] stale_count=${stale_count}"

  if [ "${stale_count}" -gt 0 ]; then
    printf "%s\n" "${mongo_out}" | awk '/^[0-9a-f]{24} /{print}'

    fingerprint="$(printf "%s\n" "${mongo_out}" | awk '/^[0-9a-f]{24} /{print $1"/"$2}' | sort | tr '\n' ',' | sed 's/,$//')"
    ids_regex="$(printf "%s\n" "${mongo_out}" | awk '/^[0-9a-f]{24} /{print $1}' | sort -u | paste -sd'|' -)"

    should_dump=0
    if [ "${fingerprint}" != "${last_fingerprint}" ]; then
      should_dump=1
    fi
    if [ $((now_epoch - last_dump_epoch)) -ge "${LOG_DUMP_COOLDOWN_SEC}" ]; then
      should_dump=1
    fi

    if [ "${should_dump}" -eq 1 ]; then
      echo "----- ${now_utc} stale-event logs (since ${LOG_SINCE}) -----"
      echo "----- recording -----"
      if [ -n "${ids_regex}" ]; then
        sudo docker logs --since="${LOG_SINCE}" "${RECORDING_CONTAINER}" 2>&1 | grep -E "${ids_regex}|Skip ffmpeg healthcheck|Healthcheck saw not working stream|Healthcheck has restarted stream|Connection closed on /live|Connection opened on /live" || true
      else
        sudo docker logs --since="${LOG_SINCE}" "${RECORDING_CONTAINER}" 2>&1 | grep -E "Skip ffmpeg healthcheck|Healthcheck saw not working stream|Healthcheck has restarted stream|Connection closed on /live|Connection opened on /live" || true
      fi
      echo "----- gateway -----"
      if [ -n "${ids_regex}" ]; then
        sudo docker logs --since="${LOG_SINCE}" "${GATEWAY_CONTAINER}" 2>&1 | grep -E "${ids_regex}|Debug random drop|Debug drop socket" || true
      else
        sudo docker logs --since="${LOG_SINCE}" "${GATEWAY_CONTAINER}" 2>&1 | grep -E "Debug random drop|Debug drop socket" || true
      fi
      echo "----- end stale-event logs -----"
      last_fingerprint="${fingerprint}"
      last_dump_epoch="${now_epoch}"
    fi
  else
    last_fingerprint=""
  fi

  sleep "${CHECK_INTERVAL_SEC}"
done
