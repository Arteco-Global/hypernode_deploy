#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR"
SYSTEM_ENV_DIR="/etc/.hypernode"

TOTAL_CHANGES=0
CHANGED_FILES=()
TARGET_FILES=()
OVERRIDE_KEYS=()
OVERRIDE_VALUES=()

usage() {
    cat <<'EOF'
Usage: edit_env_file.sh KEY=VALUE [KEY=VALUE ...]

Aggiorna variabili env nei file env log Hypernode:
  - .hypernode-install-env.log
  - .hypernode-install-*-env.log
  - eventuali repliche in /etc/.hypernode
  - eventuali .original

Esempio:
  ./edit_env_file.sh DOCKER_TAG=latest ARTECO_GLOBAL_PASSWORD=pippo
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

parse_overrides() {
    local arg
    local key
    local value
    local i
    local idx

    if [[ "$#" -eq 0 ]]; then
        echo "Missing parameters."
        usage
        exit 1
    fi

    for arg in "$@"; do
        if [[ "$arg" != *=* ]]; then
            echo "Invalid parameter '$arg'. Expected KEY=VALUE."
            usage
            exit 1
        fi

        key="${arg%%=*}"
        value="${arg#*=}"

        if [[ -z "$key" ]]; then
            echo "Invalid parameter '$arg'. Key cannot be empty."
            usage
            exit 1
        fi

        if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "Invalid key '$key'."
            usage
            exit 1
        fi

        i=-1
        for idx in "${!OVERRIDE_KEYS[@]}"; do
            if [[ "${OVERRIDE_KEYS[$idx]}" == "$key" ]]; then
                i="$idx"
                break
            fi
        done

        if [[ "$i" -lt 0 ]]; then
            OVERRIDE_KEYS+=("$key")
            OVERRIDE_VALUES+=("$value")
        else
            OVERRIDE_VALUES[$i]="$value"
        fi
    done
}

get_override_value() {
    local key="$1"
    local idx

    for idx in "${!OVERRIDE_KEYS[@]}"; do
        if [[ "${OVERRIDE_KEYS[$idx]}" == "$key" ]]; then
            printf '%s' "${OVERRIDE_VALUES[$idx]}"
            return 0
        fi
    done
    return 1
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
    local key

    tmp_file="$(mktemp)"
    report_file="$(mktemp)"
    rel="$(to_rel_path "$file")"

    : > "$tmp_file"
    : > "$report_file"

    line_no=0
    while IFS= read -r old_value || [[ -n "$old_value" ]]; do
        line_no=$((line_no + 1))
        new_value="$old_value"

        for key in "${OVERRIDE_KEYS[@]:-}"; do
            if [[ "$new_value" =~ ^[[:space:]]*$key= ]]; then
                new_value="$key=$(get_override_value "$key")"
                break
            fi
        done

        if [[ "$old_value" != "$new_value" ]]; then
            printf '%s\t%s\t%s\n' "$line_no" "$old_value" "$new_value" >> "$report_file"
        fi

        printf '%s\n' "$new_value" >> "$tmp_file"
    done < "$file"

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

parse_overrides "$@"
detect_deploy_dir

echo ""
echo "▶️  Aggiornamento env nei log in corso"
for key in "${OVERRIDE_KEYS[@]}"; do
    echo "   - $key=$(get_override_value "$key")"
done

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
    echo "ℹ️  Nessuna modifica necessaria."
    exit 0
fi

echo "🏁 Aggiornamento completato."
echo "File aggiornati: ${#CHANGED_FILES[@]}"
echo "Sostituzioni effettuate: $TOTAL_CHANGES"
