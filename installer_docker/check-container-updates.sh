#!/usr/bin/env bash
set -euo pipefail

# Percorso del JSON generato da dump-container-versions.sh
JSON_FILE=${JSON_FILE:-"./container_versions.json"}

# Credenziali Docker (per esempio; in produzione usare variabili d'ambiente o secret manager)
DOCKER_USERNAME=${DOCKER_USERNAME:-artecoglobalcompany}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-dckr_oat_1q1A2y6TGAmi3BjpcYnpBgKbx3voQd_k}

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

mapfile -t SERVICES < <(jq -r 'keys[]' "$JSON_FILE")

for service in "${SERVICES[@]}"; do
  image=$(jq -r --arg s "$service" '.[$s].image' "$JSON_FILE")
  digest_local=$(jq -r --arg s "$service" '.[$s].digest' "$JSON_FILE" | awk -F'@' '{print $2}')

  if [[ "$image" != artecoglobalcompany/usee_* ]]; then
    continue
  fi

  manifest_json=$(docker manifest inspect --verbose "$image" 2>/dev/null || true)
  if [[ -z "$manifest_json" ]]; then
    echo "⚠️  Impossibile recuperare il manifest remoto per $service ($image)." >&2
    continue
  fi

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
    continue
  fi

  if [[ "$remote_digest" == "$digest_local" ]]; then
    echo "✅  $service ($image) è già aggiornato."
  else
    echo "⬆️  $service ($image) ha un digest remoto differente."
    echo "    Local:  $digest_local"
    echo "    Remote: $remote_digest"
  fi
done
