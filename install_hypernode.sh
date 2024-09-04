#!/bin/bash
# Messaggio di benvenuto
echo "Welcome to Hypernode installation process"

# Chiedi all'utente di inserire la porta NON sicura
read -p "HTTP server port: " SERVER_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "HTTPS server port: " SSL_PORT

# Attendi un invio
read -p "Press Enter to continue with the installation..."

# Imposta le variabili d'ambiente
export SERVER_PORT=${SERVER_PORT:-80}
export SSL_PORT=${SSL_PORT:-443}

# Esegui docker compose up -d
docker compose up -d --build