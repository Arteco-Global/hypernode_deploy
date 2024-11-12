#!/bin/bash
# Messaggio di benvenuto
echo "Welcome to Hypernode installation process"

# Chiedi all'utente di inserire la porta NON sicura
read -p "HTTP server port (default 80): " SERVER_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "HTTPS server port (default 443): " SSL_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "Configurator port (default 8080): " CONF_PORT

# Chiedi all'utente di inserire la porta sicura
read -p "Rabbit url (edit only if remote): " RMQ

# Attendi un invio
read -p "Press Enter to continue with the installation..."

echo "Certificate file is NOT automatically generated. Please provide a valid certificate file in the /certs folder !!!!" 

# Imposta le variabili d'ambiente
export SERVER_PORT=${SERVER_PORT:-80}
export SSL_PORT=${SSL_PORT:-443}
export CONF_PORT=${CONF_PORT:-8080}
export RMQ=${RMQ:-amqp://hypernode:hypernode@messageBroker:5672}

echo "Dockerizing stuff ...."

docker compose up -d --build

echo "Done"
