#!/bin/bash
# Messaggio di benvenuto
echo "Welcome to Hypernode installation process"

# Assegna i valori dalle variabili di input o usa i valori di default
SERVER_PORT=${1:-80} # Primo argomento o valore di default 80
SSL_PORT=${2:-443}   # Secondo argomento o valore di default 443
CONF_PORT=${3:-8080} # Terzo argomento o valore di default 8080
RMQ=${4:-amqp://hypernode:hypernode@messageBroker:5672} # Quarto argomento o valore di default

echo "Using configuration:"
echo "HTTP server port: $SERVER_PORT"
echo "HTTPS server port: $SSL_PORT"
echo "Configurator port: $CONF_PORT"
echo "Message broker URL: $RMQ"

echo "Certificate file is NOT automatically generated. Please provide a valid certificate file in the /certs folder !!!!" 

# Imposta le variabili d'ambiente
export SERVER_PORT
export SSL_PORT
export CONF_PORT
export RMQ

echo "Installation in progress ........"

# Avvia il processo di Docker Compose
docker compose up -d --build

echo "Done"
