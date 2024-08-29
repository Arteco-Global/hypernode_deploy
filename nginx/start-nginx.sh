#!/bin/bash
# Accetta in ingresso il comando start o stop
if [ "$1" == "start" ]; then
    # Ottiene il percorso assoluto della directory in cui si trova lo script
    SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
    # Stampa il percorso per debug
    echo "Using nginx config at: $SCRIPT_DIR/nginx.conf"
    # Avvia nginx con configurazione personalizzata, usando il percorso assoluto
    sudo nginx -c "$SCRIPT_DIR/nginx.conf"
elif [ "$1" == "stop" ]; then
    # Ferma nginx
    echo "Stopping nginx..."

    sudo nginx -s stop
else
    echo "Invalid command. Please use 'start' or 'stop'."
fi
