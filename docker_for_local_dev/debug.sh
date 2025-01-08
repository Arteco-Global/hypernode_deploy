#!/bin/bash
# Run this script to start the local development environment !
echo "Starting the local development environment !"

### Moving in the right directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

### Installing mongoDb
docker rm -f database-debug
docker rm -f messagebroker-debug
docker rm -f webserver-debug
docker rm -f configurator-debug

### Installing Database 
docker run -d --name database-debug -p 27017:27017 mongo

### Installing RabbitMQ 
sudo docker build -t messagebroker-local-purpose -f ./messagebroker/messageBroker.Dockerfile ./messagebroker
docker run -d --name messagebroker-debug -p 5671:5671 -p 5672:5672 -p 15672:15672 messagebroker-local-purpose

### Installing WebServer
sudo docker build -t nginx-local-purpose -f ./nginx_debug/nginx.debug.dockerfile ./nginx_debug
docker run -d --name webserver-debug -p 443:443 -p 80:80 nginx-local-purpose

### Installing configurator
sudo docker build -t configurator-local-purpose -f ../../hypernode_server_gui/configurator.Dockerfile ../../hypernode_server_gui
docker run -d --name configurator-debug -p 81:80 -p 444:443 configurator-local-purpose
