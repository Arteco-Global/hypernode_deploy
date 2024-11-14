#!/bin/bash

# Creazione della cartella 'hypernode' se non esiste
mkdir -p hypernode

# Spostarsi dentro la cartella 'hypernode'
cd hypernode

#scadono tra 60 giorni
usr=mdalprato
psw=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

# Clonazione delle tre repository con autenticazione diretta
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_deploy.git
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode-server.git
git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_server_gui.git

echo "Cloning procedure compleated"

pwd

source ./hypernode_deploy/wizard.sh