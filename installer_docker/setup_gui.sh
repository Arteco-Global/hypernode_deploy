#!/bin/bash

zenity --question \
  --title="uSS installer" \
  --text="Do you want to proceed with the installation?" \
  --ok-label="Install" \
  --cancel-label="Close"

# Check exit status
if [ $? -eq 0 ]; then
  zenity --info --text="Installation started!"
  # Put your install command here, for example:
  curl -sSL -o installer.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/installer.sh
  chmod +x installer.sh
  sudo bash ./installer.sh -fi

else
  zenity --info --text="Installation cancelled."
fi
