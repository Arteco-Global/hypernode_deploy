#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"
SYSTEM_ENV_DIR="/etc/.hypernode"

NEW_TAG=""
TOTAL_CHANGES=0
CHANGED_FILES=()
TARGET_FILES=()

usage() {
    cat <<'EOF'
Usage: set_docker_tag.sh

Aggiorna DOCKER_TAG solo nei file env log Hypernode:
  - .hypernode-install-env.log
  - .hypernode-install-*-env.log
  - eventuali repliche in /etc/.hypernode
  - eventuali .original

Lo script chiede interattivamente il nuovo tag e stampa
tutti i file/linee aggiornati.
EOF
}

detect_deploy_dir() {
    if [[ "$(basename "$SCRIPT_DIR")" == "installer_docker" ]]; then
        DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
    else
        DEPLOY_DIR="$SCRIPT_DIR"
    fi
}

to_rel_path() {
    local abs="$1"
    if [[ "$abs" == "$DEPLOY_DIR/"* ]]; then
        printf '%s\n' "${abs#$DEPLOY_DIR/}"
    else
        printf '%s\n' "$abs"
    fi
}

prompt_tag() {
    local value=""
    while true; do
        read -r -p "Inserisci il nuovo Docker tag: " value
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        if [[ -z "$value" ]]; then
            echo "❌ Tag vuoto, riprova."
            continue
        fi

        if [[ "$value" =~ [[:space:]] ]]; then
            echo "❌ Il tag non può contenere spazi."
            continue
        fi

        if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            echo "❌ Tag non valido. Usa solo lettere, numeri, '.', '_' o '-'."
            continue
        fi

        NEW_TAG="$value"
        return 0
    done
}

add_target_file() {
    local file="$1"
    local existing

    [[ -f "$file" ]] || return 0

    for existing in "${TARGET_FILES[@]:-}"; do
        if [[ "$existing" == "$file" ]]; then
            return 0
        fi
    done
    TARGET_FILES+=("$file")
}

collect_env_logs_from_dir() {
    local dir="$1"
    local file

    [[ -d "$dir" ]] || return 0

    while IFS= read -r file; do
        add_target_file "$file"
    done < <(
        find "$dir" -maxdepth 1 -type f \
            \( -name '.hypernode-install-env.log' \
            -o -name '.hypernode-install-*-env.log' \
            -o -name '.hypernode-install-env.log.original' \
            -o -name '.hypernode-install-*-env.log.original' \
            -o -name 'hypernode-install-env.log' \
            -o -name 'hypernode-install-*-env.log' \
            -o -name 'hypernode-install-env.log.original' \
            -o -name 'hypernode-install-*-env.log.original' \) \
            | sort
    )
}

write_updated_file() {
    local tmp_file="$1"
    local dest_file="$2"

    if cp "$tmp_file" "$dest_file" 2>/dev/null; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo cp "$tmp_file" "$dest_file" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

update_env_log_file() {
    local file="$1"
    local tmp_file
    local report_file
    local rel
    local line_no
    local old_value
    local new_value
    local change_count

    tmp_file="$(mktemp)"
    report_file="$(mktemp)"
    rel="$(to_rel_path "$file")"

    awk -v tag="$NEW_TAG" -v report_file="$report_file" '
        {
            line = $0

            if (line ~ /^[[:space:]]*DOCKER_TAG=/) {
                old = line
                line = "DOCKER_TAG=" tag
                if (old != line) {
                    printf "%d\t%s\t%s\n", NR, old, line >> report_file
                }
            }

            print line
        }
    ' "$file" > "$tmp_file"

    if cmp -s "$file" "$tmp_file"; then
        rm -f "$tmp_file" "$report_file"
        return 0
    fi

    if ! write_updated_file "$tmp_file" "$file"; then
        echo "⚠️  Impossibile scrivere: $rel"
        rm -f "$tmp_file" "$report_file"
        return 0
    fi

    echo "✅ $rel"
    while IFS=$'\t' read -r line_no old_value new_value; do
        [[ -z "$line_no" ]] && continue
        echo "   - line $line_no: $old_value -> $new_value"
    done < "$report_file"

    change_count="$(wc -l < "$report_file" | tr -d ' ')"
    TOTAL_CHANGES=$((TOTAL_CHANGES + change_count))
    CHANGED_FILES+=("$rel")

    rm -f "$tmp_file" "$report_file"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "$#" -gt 0 ]]; then
    echo "Unknown parameter(s): $*"
    usage
    exit 1
fi

prompt_tag
detect_deploy_dir

echo ""
echo "▶️  Aggiornamento DOCKER_TAG nei log in corso: $NEW_TAG"

collect_env_logs_from_dir "$DEPLOY_DIR"
collect_env_logs_from_dir "$SYSTEM_ENV_DIR"

if [[ "${#TARGET_FILES[@]}" -eq 0 ]]; then
    echo "ℹ️  Nessun env log trovato in '$DEPLOY_DIR' o '$SYSTEM_ENV_DIR'."
    exit 0
fi

for file in "${TARGET_FILES[@]}"; do
    update_env_log_file "$file"
done

echo ""
if [[ "${#CHANGED_FILES[@]}" -eq 0 ]]; then
    echo "ℹ️  Nessuna modifica necessaria. I log erano già allineati al tag '$NEW_TAG'."
    exit 0
fi

echo "🏁 Aggiornamento completato."
echo "File aggiornati: ${#CHANGED_FILES[@]}"
echo "Sostituzioni effettuate: $TOTAL_CHANGES"
