#!/bin/bash
# Messaggio di benvenuto
echo "Welcome to additional auth service installation process"

read -p "Unique name for this installation (must be unque !!!): " PROCESS_NAME

# Chiede all'utente se RabbitMQ deve essere locale o remoto
read -p "Is the main gateway local (l) o (r)remote ? [l/r]: " choice

# Imposta la variabile RABBITMQ_HOST in base alla scelta
if [ "$choice" == "l" ] || [ "$choice" == "L" ]; then
    RABBITMQ_HOST="host.docker.internal"
    echo "Gateway set as local. Host: $RABBITMQ_HOST"
elif [ "$choice" == "r" ] || [ "$choice" == "R" ]; then
    read -p "Insert the ip/url: " remote_host
    RABBITMQ_HOST="$remote_host"
    echo "Gateway set as remote $RABBITMQ_HOST"
else
    echo "Wrong choice mate."
    exit 1
fi

# Costruisci l'URL amqp
AMQP_URL="amqp://hypernode:hypernode@$RABBITMQ_HOST:5672"
# Stampa l'AMQP_URL con la variabile espansa
echo "Gateway message broker will be set at ${AMQP_URL} "


# Attendi un invio
read -p "Press Enter to continue with the installation..."


export SERVER_PORT=${SERVER_PORT:-80}
export SSL_PORT=${SSL_PORT:-443}
export CONF_PORT=${CONF_PORT:-8080}
export RMQ=${AMQP_URL}
export PROCESS_NAME=auth-${PROCESS_NAME}
export DB_NAME=database-for-${PROCESS_NAME}
export DATABASE_URI=mongodb://${DB_NAME}:27017/auth-service

# return

echo "Dockerizing stuff ...."

cd "$(dirname "$0")" && docker compose up -d --build

echo "Done"
