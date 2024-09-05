#!/bin/bash
# Messaggio di benvenuto
echo "Welcome to Hypernode installation process"

# Chiedi all'utente di inserire la porta NON sicura
read -p "HTTP server port: " SERVER_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "HTTPS server port: " SSL_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "Rabbit url: " RMQ

# Chiedi all'utente se è un aggiornamento
read -p "Rebuil all the images? [Y/N]: " IS_UPDATE

# Attendi un invio
read -p "Press Enter to continue with the installation..."

# Imposta le variabili d'ambiente
export SERVER_PORT=${SERVER_PORT:-80}
export SSL_PORT=${SSL_PORT:-443}
export RMQ=${RMQ:-amqp://hypernode:hypernode@rabbitmqHypernode:5672}

# Controlla se è un aggiornamento
if [[ $IS_UPDATE == "Y" || $IS_UPDATE == "y" ]]; then
    # Esegui docker compose up -d --build
    docker compose up -d --build
else
    # Esegui docker compose up -d senza --build
    docker compose up -d
fi