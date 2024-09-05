#!/bin/sh

#!/bin/sh

# Costruisci l'immagine Docker
docker build -t nginx-local-purpose -f nginx.dockerfile .

# Esegui il container Docker
docker run -d --name nginxForLocalPurpose --network bridge -p 80:80 -p 443:443 nginx-local-purpose