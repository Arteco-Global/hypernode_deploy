#!/bin/bash

# Spostati nella directory 'docker' (dove si trova questo script)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

docker rm -f nginxForLocalPurpose
sudo docker build -t nginx-local-purpose -f nginx.debug.dockerfile .
docker run -d --name nginxForLocalPurpose --network bridge -p 80:80 -p 443:443  nginx-local-purpose
