#!/bin/bash

# Chiedi all'utente di inserire la porta NON sicura
read -p "HTTP server port: " SERVER_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "HTTPS server port: " SSL_PORT

# Imposta le variabili d'ambiente
export SERVER_PORT=${SERVER_PORT:-80}
export SSL_PORT=${SSL_PORT:-443}

# Esegui docker compose up -d
docker compose up -d