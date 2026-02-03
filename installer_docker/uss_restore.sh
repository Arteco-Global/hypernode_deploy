#!/bin/bash

set -euo pipefail

INSTALL_DIR="$(pwd -P)"
DEFAULT_ENV_FILE="${INSTALL_DIR}/.hypernode-install-env.log"
ENV_FILE="$DEFAULT_ENV_FILE"
DEPLOY_BRANCH="main"
DEPLOY_BRANCH_PROVIDED="false"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
RESTORE_DIR="$(cd "$INSTALL_DIR/.." && pwd -P)/hypernode_deploy"
NATIVE_UPDATE_PATH="${RESTORE_DIR}/native_update.sh"

usage() {
    cat <<'EOF'
Usage: uss_restore.sh [options]

Options:
  --env-file <path>       Path to env file (default: ./.hypernode-install-env.log)
  --deploy-branch <name>  Deploy branch for native_update.sh (default: main)
  -h, --help              Show this help
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --deploy-branch)
            DEPLOY_BRANCH="$2"
            DEPLOY_BRANCH_PROVIDED="true"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Env file not found: $ENV_FILE"
    exit 1
fi

ENV_FILE="$(cd "$(dirname "$ENV_FILE")" && pwd -P)/$(basename "$ENV_FILE")"

if [[ "$DEPLOY_BRANCH_PROVIDED" != "true" ]]; then
    while true; do
        read -r -p "⚠️  --deploy-branch option not provided: should I use the default (main)? [y/n] " reply
        case "$reply" in
            y|Y)
                break
                ;;
            n|N)
                echo "❌ Aborted. Please provide --deploy-branch."
                exit 1
                ;;
            *)
                echo "Please answer y or n."
                ;;
        esac
    done
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
fi

mkdir -p "$RESTORE_DIR"

if [[ "$ENV_FILE" != "$DEFAULT_ENV_FILE" ]]; then
    cp "$ENV_FILE" "$DEFAULT_ENV_FILE"
fi

cp "$DEFAULT_ENV_FILE" "${RESTORE_DIR}/.hypernode-install-env.log"

NATIVE_UPDATE_URL="${ABSOLUTE_PATH_BASE}/${DEPLOY_BRANCH}/installer_docker/native_update.sh"
curl -sSL "$NATIVE_UPDATE_URL" -o "$NATIVE_UPDATE_PATH"
chmod +x "$NATIVE_UPDATE_PATH"

pushd "$RESTORE_DIR" >/dev/null
if [[ "$DEPLOY_BRANCH_PROVIDED" == "true" ]]; then
    ./native_update.sh --deploy-branch "$DEPLOY_BRANCH"
else
    ./native_update.sh
fi
popd >/dev/null
