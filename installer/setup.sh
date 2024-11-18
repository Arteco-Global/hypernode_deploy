#!/bin/bash

# Creazione della cartella 'hypernode' se non esiste
mkdir -p hypernode

# Spostarsi dentro la cartella 'hypernode'
cd hypernode

read -p "Download code[y/n]: " choice

# Imposta la variabile RABBITMQ_HOST in base alla scelta
if [ "$choice" == "y" ] || [ "$choice" == "Y" ]; then
    #scadono tra 60 giorni
    usr=mdalprato
    psw=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

    # Clonazione delle tre repository con autenticazione diretta
    git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_deploy.git
    git clone https://$usr:$psw@github.com/Arteco-Global/hypernode_server_gui.git
    git clone https://$usr:$psw@github.com/Arteco-Global/hypernode-server.git
    # Vai nel repository appena clonato
    cd hypernode-server

    # Passa al ramo release_candidate
    git checkout release_candidate

    cd ..

    echo "Cloning procedure compleated"

elif [ "$choice" == "n" ] || [ "$choice" == "N" ]; then
     echo "Skipping cloning procedure"
else
    echo "Wrong choice mate."
    exit 1
fi

pwd

source ./hypernode_deploy/wizard.sh