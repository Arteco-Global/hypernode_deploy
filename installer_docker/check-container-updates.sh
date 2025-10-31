#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE=${JSON_FILE:-"$SCRIPT_DIR/container_versions.json"}
REPORT_FILE=${REPORT_FILE:-"$SCRIPT_DIR/container_update_report.json"}

DOCKER_USERNAME=${DOCKER_USERNAME:-}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-}

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

LOGIN_PERFORMED="false"
if [[ -n "$DOCKER_USERNAME" && -n "$DOCKER_PASSWORD" ]]; then
  echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin >/dev/null
  LOGIN_PERFORMED="true"
else
  echo "ℹ️  Credenziali Docker non fornite: eseguo il check senza login." >&2
fi
trap 'if [[ "$LOGIN_PERFORMED" == "true" ]]; then docker logout >/dev/null 2>&1 || true; fi' EXIT

export DOCKER_CLI_EXPERIMENTAL=enabled
SERVICES_JSON='[]'

mapfile -t SERVICES < <(jq -r 'keys[]' "$JSON_FILE")

for service in "${SERVICES[@]}"; do
  image=$(jq -r --arg s "$service" '.[$s].image' "$JSON_FILE")
  digest_local=$(jq -r --arg s "$service" '.[$s].digest' "$JSON_FILE" | awk -F'@' '{print $2}')
  config_digest_local=$(jq -r --arg s "$service" '.[$s].config_digest // "unknown"' "$JSON_FILE")

  service_json=$(jq -c --arg s "$service" 'if has($s) then .[$s] else null end' "$JSON_FILE")
  if [[ "$service_json" == "null" ]]; then
    continue
  fi

  if [[ "$image" != artecoglobalcompany/usee_* ]]; then
    continue
  fi

  check_error=""
  remote_digest=""

  if docker buildx version >/dev/null 2>&1; then
    remote_digest=$(docker buildx imagetools inspect "$image" 2>/dev/null | awk '/^Digest:/ {print $2; exit}' || true)
  fi

  if [[ -z "$remote_digest" ]]; then
    manifest_json=$(docker manifest inspect --verbose "$image" 2>/dev/null || true)
    if [[ -z "$manifest_json" ]]; then
      echo "⚠️  Impossibile recuperare il manifest remoto per $service ($image)." >&2
      check_error="manifest_unavailable"
    else
      remote_digest=$(jq -r '
        if type == "array" then
          (.[0].Descriptor.digest // .[0].digest // empty)
        else
          (.Descriptor.digest // .digest // empty)
        end
      ' <<<"$manifest_json")

      if [[ -z "$remote_digest" ]]; then
        echo "⚠️  Digest remoto non trovato per $service ($image)." >&2
        check_error="digest_unavailable"
      fi
    fi
  fi

  uptodate="false"

  if [[ -z "$check_error" ]]; then
    if [[ -n "$remote_digest" ]]; then
      if [[ "$digest_local" != "unknown" && "$digest_local" == "$remote_digest" ]]; then
        uptodate="true"
      elif [[ "$config_digest_local" != "unknown" && "$config_digest_local" == "$remote_digest" ]]; then
        uptodate="true"
      fi
    fi
  fi

  if [[ "$uptodate" == "true" ]]; then
    echo "✅  $service ($image) è già aggiornato."
  else
    if [[ -n "$remote_digest" && "$digest_local" != "$remote_digest" ]]; then
      echo "⬆️  $service ($image) ha un digest remoto differente."
      echo "    Local:  $digest_local"
      if [[ "$config_digest_local" != "unknown" ]]; then
        echo "    Local config: $config_digest_local"
      fi
      echo "    Remote: $remote_digest"
    elif [[ -n "$check_error" ]]; then
      echo "⚠️  $service ($image): $check_error"
    fi
  fi

  SERVICES_JSON=$(jq --argjson svc "$service_json" \
                     --arg name "$service" \
                     --arg uptodate "$uptodate" \
                     --arg check_error "$check_error" \
                     --arg remote_digest "${remote_digest:-}" \
                     '. + [ $svc
                         + { name: $name,
                             uptodate: ($uptodate == "true")
                           }
                         + (if $remote_digest == "" then {} else {remote_digest: $remote_digest} end)
                         + (if $check_error == "" then {} else {check_error: $check_error} end)
                       ]' <<<"$SERVICES_JSON")
done

umask 077
tmp_file=$(mktemp)
jq -n --argjson services "$SERVICES_JSON" '{services: $services}' > "$tmp_file"
mv "$tmp_file" "$REPORT_FILE"
