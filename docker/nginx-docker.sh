#!/bin/bash

# Spostati nella directory 'docker' (dove si trova questo script)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Rimuovi il contenitore esistente se presente
docker rm -f nginxForLocalPurpose

# Costruisci l'immagine usando il Dockerfile un livello sopra
sudo docker build -t nginx-local-purpose -f ../nginx.debug.dockerfile ..

# Avvia il contenitore
docker run -d --name nginxForLocalPurpose --network bridge -p 80:80 -p 443:443 nginx-local-purpose