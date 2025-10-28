#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_FILE="$SCRIPT_DIR/container_versions.json"
OUTPUT_FILE=${OUTPUT_FILE:-"$DEFAULT_OUTPUT_FILE"}

mkdir -p "$(dirname "$OUTPUT_FILE")"
TMP_FILE=$(mktemp)

if [ "$#" -gt 0 ]; then
  mapfile -t CONTAINERS < <(printf '%s\n' "$@")
else
  mapfile -t CONTAINERS < <(docker ps --format '{{.Names}}')
fi

{
  echo "{"
  first=1
  for name in "${CONTAINERS[@]}"; do
    if ! docker inspect "$name" >/dev/null 2>&1; then
      echo "⚠️  Container '$name' non trovato, salto." >&2
      continue
    fi

    image=$(docker inspect --format '{{.Config.Image}}' "$name")
    image_id=$(docker inspect --format '{{.Image}}' "$name")

    if [[ "$image" != artecoglobalcompany/usee_* ]]; then
      continue
    fi

    digest=$(docker image inspect --format '{{join .RepoDigests ", "}}' "$image_id" 2>/dev/null || true)
    version=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$image_id" 2>/dev/null || true)
    created=$(docker image inspect --format '{{.Created}}' "$image_id")

    digest=${digest:-unknown}
    version=${version:-unknown}
    tag="unknown"
    if [[ "$image" == *:* ]]; then
      candidate=${image##*:}
      if [[ "$candidate" != *"/"* ]]; then
        tag=$candidate
      fi
    fi

    (( first )) || echo ","
    first=0
    printf '  "%s": {\n' "$name"
    printf '    "image": "%s",\n' "$image"
    printf '    "digest": "%s",\n' "$digest"
    printf '    "tag": "%s",\n' "$tag"
    printf '    "version": "%s",\n' "$version"
    printf '    "created": "%s"\n' "$created"
    printf '  }'
  done
  echo
  echo "}"
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
echo "JSON salvato in $OUTPUT_FILE"
