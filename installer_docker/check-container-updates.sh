#!/usr/bin/env bash
set -euo pipefail

# Percorso del JSON generato da dump-container-versions.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE=${JSON_FILE:-"$SCRIPT_DIR/container_versions.json"}
REPORT_FILE=${REPORT_FILE:-"$SCRIPT_DIR/container_update_report.json"}

# Credenziali Docker (da passare tramite variabili d'ambiente)
DOCKER_USERNAME=${DOCKER_USERNAME:-}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-}

if [[ -z "$DOCKER_USERNAME" || -z "$DOCKER_PASSWORD" ]]; then
  echo "❌ Variabili DOCKER_USERNAME/DOCKER_PASSWORD non valorizzate." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Comando 'jq' mancante. Installalo per continuare." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker non è disponibile sul sistema." >&2
  exit 1
fi

if [ ! -f "$JSON_FILE" ]; then
  echo "❌ File JSON '$JSON_FILE' inesistente. Genera prima il file con dump-container-versions.sh." >&2
  exit 1
fi

echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin >/dev/null
trap 'docker logout >/dev/null 2>&1 || true' EXIT

export DOCKER_CLI_EXPERIMENTAL=enabled
SERVICES_JSON='[]'

mapfile -t SERVICES < <(jq -r 'keys[]' "$JSON_FILE")

for service in "${SERVICES[@]}"; do
  image=$(jq -r --arg s "$service" '.[$s].image' "$JSON_FILE")
  digest_local=$(jq -r --arg s "$service" '.[$s].digest' "$JSON_FILE" | awk -F'@' '{print $2}')

  service_json=$(jq -c --arg s "$service" 'if has($s) then .[$s] else null end' "$JSON_FILE")
  if [[ "$service_json" == "null" ]]; then
    continue
  fi

  if [[ "$image" != artecoglobalcompany/usee_* ]]; then
    continue
  fi

  check_error=""
  remote_digest=""

  manifest_json=$(docker manifest inspect --verbose "$image" 2>/dev/null || true)
  if [[ -z "$manifest_json" ]]; then
    echo "⚠️  Impossibile recuperare il manifest remoto per $service ($image)." >&2
    check_error="manifest_unavailable"
  else
    remote_digest=$(jq -r '
      def digest_from_object(o):
        o.Descriptor.digest
        // o.manifests[0].digest
        // o.manifest.digest
        // o.config.digest
        // o.digest
        // empty;
      if type == "object" then
        digest_from_object(.)
      elif type == "array" then
        ([ .[] | digest_from_object(.) ] | map(select(. != null and . != "")) | .[0] // empty)
      else
        empty
      end
    ' <<<"$manifest_json")

    if [[ -z "$remote_digest" ]]; then
      echo "⚠️  Digest remoto non trovato per $service ($image)." >&2
      check_error="digest_unavailable"
    fi
  fi

  if [[ -n "$remote_digest" && "$remote_digest" == "$digest_local" ]]; then
    echo "✅  $service ($image) è già aggiornato."
    uptodate="true"
  else
    if [[ -n "$remote_digest" ]]; then
      echo "⬆️  $service ($image) ha un digest remoto differente."
      echo "    Local:  $digest_local"
      echo "    Remote: $remote_digest"
    fi
    uptodate="false"
  fi

  SERVICES_JSON=$(jq --argjson svc "$service_json" \
                     --arg name "$service" \
                     --arg uptodate "$uptodate" \
                     --arg check_error "$check_error" \
                     '. + [ $svc + { name: $name, uptodate: ($uptodate == "true") }
                         + (if $check_error == "" then {} else {check_error: $check_error} end)
                       ]' <<<"$SERVICES_JSON")
done

umask 077
tmp_file=$(mktemp)
jq -n --argjson services "$SERVICES_JSON" '{services: $services}' > "$tmp_file"
mv "$tmp_file" "$REPORT_FILE"
