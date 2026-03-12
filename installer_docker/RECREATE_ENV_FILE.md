# Recreate Env File

Questo script ricrea un file `_restored_hypernode-install-env.log` partendo
dallo stato reale dei container in esecuzione. Serve quando il file originale
`.hypernode-install-env.log` è mancante o è stato sovrascritto da una
installazione di servizi aggiuntivi.

## Cosa fa

- Legge il compose della suite (server).
- Identifica i container attivi definiti nel compose.
- Esegue `docker inspect` e ricava le variabili principali.
- Scrive un file `_restored_hypernode-install-env.log` compatibile con
  `native_update.sh` e `uss_restore.sh`.

## Uso rapido

```bash
sudo installer_docker/recreate_env_file.sh
```

Il file viene creato nella directory corrente:

```
./_restored_hypernode-install-env.log
```

## Opzioni

```bash
sudo installer_docker/recreate_env_file.sh \
  --compose installer_docker/composes/server/docker-compose.yaml \
  --output /etc/.hypernode/_restored_hypernode-install-env.log
```

Parametri:

- `--compose`: path o URL del compose (default: GitHub raw su branch `main`)
- `--output`: path di output (default: `./_restored_hypernode-install-env.log`)

## Note

- Se alcuni container non sono in esecuzione, i valori relativi restano vuoti.
- `SSL_PORT` viene letto dal mapping di `portbroker:443`.
- `DOCKER_TAG` viene letto dall'immagine `messagebroker` (fallback `gateway`).
- `DB_PORT` viene dedotto da `DATABASE_URI` del gateway/coretrust.
- `SERVER_SECRET` (se presente) viene ricavata dall'env del container `gateway`.
- La variabile `MACHINE` viene aggiunta successivamente da `native_update.sh`
  o `uss_restore.sh` (che creano/leggono `machine.json`).
- Lo script non modifica i container: è in sola lettura.
