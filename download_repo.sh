#!/bin/bash

# Creazione della cartella 'hypernode' se non esiste
mkdir -p hypernode

# Spostarsi dentro la cartella 'hypernode'
cd hypernode

usr=mdalprato
psw=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

# Clonazione delle tre repository con autenticazione diretta
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_deploy.git
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode-server.git
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_server_gui.git

echo "Cloning procedure compleated"

# Chiedere all'utente se vuole installare Hypernode
read -p "Do you want to install Hypernode (yes/no): " INSTALLL

# Leggere il valore della variabile INSTALLL
echo "You selected: $INSTALLL"

# Eseguire un'azione basata sulla risposta
if [[ "$INSTALLL" == "yes" ]]; then
  echo "Installing Hypernode..."
  cd hypernode/hypernode_deploy
  source install_hypernode.sh

  # Qui puoi inserire il codice per installare Hypernode
else
  echo "Installation skipped."
fi