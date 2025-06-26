# #!/bin/bash

# zenity --question \
#   --title="uSS installer" \
#   --text="Do you want to proceed with the installation?" \
#   --ok-label="Install" \
#   --cancel-label="Close"

# # Check exit status
# if [ $? -eq 0 ]; then
#   zenity --info --text="Installation started!"
#   # Put your install command here, for example:
#   curl -sSL -o installer.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/installer.sh
#   chmod +x installer.sh
#   sudo bash ./installer.sh -fi

# else
#   zenity --info --text="Installation cancelled."
# fi

#!/bin/bash

# Colori non servono in GUI, li rimuoviamo
#!/bin/bash

OPTIONS=(
  "1|Install Suite"
  "2|Install Live streamer"
  "3|Install ID Verifier"
  "4|Install Event Manager"
  "5|Install Storage service"
  "6|Install Thumbnail Engine"
  "7|Update Live streamer"
  "8|Update ID Verifier"
  "9|Update Event Manager"
  "10|Update Storage service"
  "11|Update Thumbnail Engine"
  "99|Clean everything (remove all containers and db)"
  "0|EXIT"
)

OPTIONS_DESC=()
for opt in "${OPTIONS[@]}"; do
  OPTIONS_DESC+=("$(echo $opt | cut -d'|' -f2)")
done

while true; do
  CHOICE=$(zenity --width=600 --height=300 --list \
    --title="uSee Service suite | Installation" \
    --text="Select an option:" \
    --column="Options" "${OPTIONS_DESC[@]}" \
    --ok-label="Next" --cancel-label="Close")

  if [ $? -ne 0 ]; then
    exit 0
  fi

  # Trova la chiave corrispondente
  for opt in "${OPTIONS[@]}"; do
    key=$(echo $opt | cut -d'|' -f1)
    desc=$(echo $opt | cut -d'|' -f2)
    if [[ "$desc" == "$CHOICE" ]]; then
      SELECTED=$key
      break
    fi
  done

  # Se esce su Exit, esci
  if [[ "$SELECTED" == "0" ]]; then
    zenity --info --text="Exiting..."
    exit 0
  fi

  # Se pulizia, chiedi conferma e installa senza porta
  if [[ "$SELECTED" == "99" ]]; then
    zenity --question --text="Are you sure you want to clean everything? This will remove all containers and databases."
    if [ $? -eq 0 ]; then
      zenity --info --text="Cleaning..."
      # inserisci qui comandi di pulizia
    fi
    continue
  fi

  # Mostra input porta
  PORT=$(zenity --entry --title="uSee Service suite | Installation" \
    --text="Enter the port to use:" \
    --entry-text="443")

  # Se cancella, torna indietro
  if [ $? -ne 0 ]; then
    continue
  fi

  # Qui fai install/aggiornamento con $SELECTED e $PORT
  zenity --info --text="You selected option $SELECTED: $CHOICE\nUsing port: $PORT"


  # TODO: inserisci qui la logica effettiva di installazione/aggiornamento

done
