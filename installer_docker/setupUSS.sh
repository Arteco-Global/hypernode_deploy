#!/bin/bash
# This script downloads and runs the installer script for Hypernode Deploy from a remote repository.
curl -sSL -o installer.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/installer.sh
chmod +x installer.sh
sudo ./installer.sh
