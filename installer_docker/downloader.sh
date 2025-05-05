#!/bin/sh

# Crea la cartella di lavoro
mkdir -p hypernode
cd hypernode || { echo "Errore nell'entrare nella cartella hypernode"; exit 1; }

# Scarica il file ZIP con autenticazione
wget "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/main/installer_docker/hypernode_installer.zip" \
  --header="Authorization: token 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" \
  -O hypernode_installer.zip

# Controlla se il download è andato a buon fine
if [ $? -ne 0 ]; then
  echo "Errore nel download del file ZIP"
  exit 1
fi

# Estrae il contenuto dello ZIP
unzip -o hypernode_installer.zip

# Controlla se il file installer.sh esiste
if [ ! -f installer.sh ]; then
  echo "installer.sh non trovato dopo l'estrazione"
  exit 1
fi

# Rende lo script eseguibile
chmod +x installer.sh

# Esegue lo script con la porta specificata
sh installer.sh -fi -p 443
