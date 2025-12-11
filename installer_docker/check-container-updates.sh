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
HOST_OS=$(docker info --format '{{.OSType}}' 2>/dev/null || echo "linux")
HOST_ARCH_RAW=$(docker info --format '{{.Architecture}}' 2>/dev/null || echo "amd64")
case "$HOST_ARCH_RAW" in
  x86_64) HOST_ARCH="amd64" ;;
  aarch64) HOST_ARCH="arm64" ;;
  armhf) HOST_ARCH="arm/v7" ;;
  *) HOST_ARCH="$HOST_ARCH_RAW" ;;
esac
HOST_PLATFORM="${HOST_OS}/${HOST_ARCH}"

mapfile -t SERVICES < <(jq -r 'keys[]' "$JSON_FILE")

for service in "${SERVICES[@]}"; do
  image=$(jq -r --arg s "$service" '.[$s].image' "$JSON_FILE")
  digest_local=$(jq -r --arg s "$service" '.[$s].digest' "$JSON_FILE" | awk -F'@' '{print $2}')
  config_digest_local=$(jq -r --arg s "$service" '.[$s].config_digest // "unknown"' "$JSON_FILE")

  service_json=$(jq -c --arg s "$service" 'if has($s) then .[$s] else null end' "$JSON_FILE")
  if [[ "$service_json" == "null" ]]; then
    continue
  fi

  service_json=$(jq -c --arg s "$service" 'if has($s) then .[$s] else null end' "$JSON_FILE")
  if [[ "$service_json" == "null" ]]; then
    continue
  fi

  if [[ "$image" != artecoglobalcompany/usee_* ]]; then
    continue
  fi

  check_error=""
  remote_digest=""
  remote_platform_digest=""

  if docker buildx version >/dev/null 2>&1; then
    remote_digest=$(docker buildx imagetools inspect "$image" 2>/dev/null | awk '/^Digest:/ {print $2; exit}' || true)
    if remote_platform_digest=$(docker buildx imagetools inspect "$image" --raw 2>/dev/null \
      | jq -r --arg plat "$HOST_PLATFORM" '
          if .manifests then
            (.manifests[]
              | select(((.platform.os+"/"+.platform.architecture)==$plat) or ((.Platform.os+"/"+.Platform.architecture)==$plat))
              | (.digest // .Descriptor.digest // .descriptor.digest)) // empty
          else empty end' \
      | head -n1); then
      remote_platform_digest=${remote_platform_digest:-}
    else
      remote_platform_digest=""
    fi
  fi

  if [[ -z "$remote_digest" || -z "$remote_platform_digest" ]]; then
    manifest_json=$(docker manifest inspect --verbose "$image" 2>/dev/null || true)
    if [[ -z "$manifest_json" ]]; then
      echo "⚠️  Impossibile recuperare il manifest remoto per $service ($image)." >&2
      check_error="manifest_unavailable"
    else
      if [[ -z "$remote_digest" ]]; then
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

      if [[ -z "$remote_platform_digest" ]]; then
        remote_platform_digest=$(jq -r --arg plat "$HOST_PLATFORM" '
          (.. | objects
            | select(
                (has("platform") and (.platform.os+"/"+.platform.architecture==$plat))
                or (has("Platform") and (.Platform.os+"/"+.Platform.architecture==$plat))
              )
            | (.digest // .Descriptor.digest // .descriptor.digest))' \
          <<<"$manifest_json" | head -n1)

        # Se resta vuoto e c'è un solo manifest, usa il primo digest come fallback piattaforma
        if [[ -z "$remote_platform_digest" ]]; then
          remote_platform_digest=$(jq -r '
            if type == "array" then
              (.[0].digest // .[0].Descriptor.digest // empty)
            elif has("manifests") and (.manifests|length==1) then
              (.manifests[0].digest // .manifests[0].Descriptor.digest // empty)
            else empty end
          ' <<<"$manifest_json")
        fi
      fi
    fi
  fi

  uptodate="false"

  if [[ -z "$check_error" ]]; then
    # Considera allineato se il digest locale coincide col digest di piattaforma
    # oppure con l'index (alcune installazioni salvano l'index digest).
    if [[ -n "$remote_platform_digest" ]]; then
      if [[ "$digest_local" != "unknown" && "$digest_local" == "$remote_platform_digest" ]]; then
        uptodate="true"
      elif [[ "$config_digest_local" != "unknown" && "$config_digest_local" == "$remote_platform_digest" ]]; then
        uptodate="true"
      fi
    fi

    if [[ "$uptodate" != "true" && -n "$remote_digest" ]]; then
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
    if [[ -n "$remote_digest" || -n "$remote_platform_digest" ]]; then
      echo "⬆️  $service ($image) ha un digest remoto differente."
      echo "    Local:  $digest_local"
      if [[ "$config_digest_local" != "unknown" ]]; then
        echo "    Local config: $config_digest_local"
      fi
      if [[ -n "$remote_platform_digest" ]]; then
        echo "    Remote (platform $HOST_PLATFORM): $remote_platform_digest"
      fi
      if [[ -n "$remote_digest" ]]; then
        echo "    Remote (index): $remote_digest"
      fi
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
