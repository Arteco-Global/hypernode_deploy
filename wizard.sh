#!/bin/sh
# Check if the script is running as root (uid 0)
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Re-running with sudo..."
  exit
fi

# Menu delle opzioni
echo "What do you want to install:"
echo "1. Stand alone server"
echo "2. Additional Camera Service"
echo "4. Esci"

# Lettura della scelta dell'utente
read -p "Enter the option: " option

# Esecuzione dell'azione in base alla option
case $option in
  1)
    echo "Stand alone server"
    bash ./install_hypernode.sh
    ;;
  2)
    echo "Additional Camera Service"
    bash ./singleService/camera/install_camera.sh
    ;;
  3)
    echo "Additional Storage Service"
    echo "NOT IMPLEMENTED YET"
    ;;
  4)
    echo "Exiting."
    exit 0
    ;;
  *)
    echo "Wrong choice mate."
    ;;
esac