#!/usr/bin/env bash
# install-docker-ubuntu.sh
# Installs Docker Engine + Compose v2 (plugin) on Ubuntu.
# Also creates a "docker-compose" -> "docker compose" wrapper for compatibility.
set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; BLU=$'\e[34m'; RST=$'\e[0m'
log() { echo "${BLU}[*]${RST} $*"; }
ok()  { echo "${GRN}[✓]${RST} $*"; }
warn(){ echo "${YLW}[!]${RST} $*"; }
die() { echo "${RED}[x]${RST} $*"; exit 1; }

# "Real" user who invoked sudo (or current user if already root)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

[[ -f /etc/os-release ]] || die "Unrecognized system (missing /etc/os-release)."
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || warn "Non-Ubuntu distribution (ID=${ID:-?}). Proceeding anyway…"

log "Updating apt and prerequisites…"
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add official Docker repo
log "Configuring official Docker repository…"
sudo install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
fi

CODENAME="${VERSION_CODENAME:-$(. /etc/os-release; echo "$VERSION_CODENAME")}"
ARCH_DEB="$(dpkg --print-architecture)"
echo "deb [arch=${ARCH_DEB} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

log "Installing Docker Engine + Buildx + Compose v2 (plugin)…"
set +e
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
APT_RC=$?
set -e

if [[ $APT_RC -ne 0 ]]; then
  warn "Installation via APT failed/limited. Proceeding with user-space Fallback for Compose v2."
fi

# Make sure Docker service is active (if installed from repo)
if systemctl list-unit-files | grep -q docker.service; then
  log "Enabling and starting Docker daemon…"
  sudo systemctl enable --now docker || warn "Unable to start Docker now (continuing anyway)."
fi

# Add user to docker group (no sudo needed to use docker)
if getent group docker >/dev/null 2>&1; then
  log "Adding ${TARGET_USER} to docker group…"
  sudo usermod -aG docker "$TARGET_USER" || warn "Could not add ${TARGET_USER} to docker group."
else
  log "Creating docker group and adding ${TARGET_USER}…"
  sudo groupadd -f docker
  sudo usermod -aG docker "$TARGET_USER" || warn "Could not add ${TARGET_USER} to docker group."
fi

# Fallback: install Compose v2 in user-space (~/.docker/cli-plugins) if plugin is missing
need_user_compose=false
if ! command -v docker >/dev/null 2>&1; then
  warn "'docker' command not found in current PATH; will check user-space Compose anyway."
fi
if ! docker compose version >/dev/null 2>&1; then
  need_user_compose=true
fi

if $need_user_compose; then
  log "Installing Docker Compose v2 for user (${TARGET_USER})…"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) B=linux-x86_64 ;;
    aarch64) B=linux-aarch64 ;;
    armv7l) B=linux-armv7 ;;
    *) die "Unsupported architecture: ${ARCH}" ;;
  esac
  PLUG_DIR="${TARGET_HOME}/.docker/cli-plugins"
  sudo -u "$TARGET_USER" mkdir -p "$PLUG_DIR"
  VER="v2.29.2"
  sudo -u "$TARGET_USER" curl -fsSL \
    "https://github.com/docker/compose/releases/download/${VER}/docker-compose-${B}" \
    -o "${PLUG_DIR}/docker-compose"
  sudo -u "$TARGET_USER" chmod +x "${PLUG_DIR}/docker-compose"
  ok "Compose v2 installed in ${PLUG_DIR}/docker-compose"
fi

# Compat wrapper: docker-compose -> docker compose
log "Creating compatible 'docker-compose' wrapper to use Compose v2…"
LOCAL_BIN="${TARGET_HOME}/.local/bin"
sudo -u "$TARGET_USER" mkdir -p "$LOCAL_BIN"
cat <<'WRAP' | sudo -u "$TARGET_USER" tee "${LOCAL_BIN}/docker-compose" >/dev/null
#!/usr/bin/env bash
# Compat wrapper: redirects docker-compose to docker compose
exec docker compose "$@"
WRAP
sudo -u "$TARGET_USER" chmod +x "${LOCAL_BIN}/docker-compose"
ok "Created ${LOCAL_BIN}/docker-compose"

# Ensure ~/.local/bin is in PATH for the user
BASHRC="${TARGET_HOME}/.bashrc"
if ! sudo -u "$TARGET_USER" grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' | sudo -u "$TARGET_USER" tee -a "$BASHRC" >/dev/null
  ok "Added ~/.local/bin to PATH in ${BASHRC}"
fi

# Final test
echo
log "Checks:"
if command -v docker >/dev/null 2>&1; then
  docker --version || warn "docker --version returned error (maybe need to re-login for permissions)."
else
  warn "'docker' command not in PATH. Close and reopen session, or run: 'newgrp docker'."
fi

if docker compose version >/dev/null 2>&1; then
  ok "docker compose works: $(docker compose version | head -n1)"
else
  warn "docker compose not yet available in current PATH (reopen session or add PATH)."
fi

if "${LOCAL_BIN}/docker-compose" version >/dev/null 2>&1; then
  ok "docker-compose (wrapper) works: $(${LOCAL_BIN}/docker-compose version | head -n1)"
else
  warn "docker-compose (wrapper) not in current PATH; will be found after logout/login."
fi

echo
ok "Installation completed."
warn "You may need to ${YLW}close and reopen your session${RST} (or run 'newgrp docker') to use Docker without sudo."
