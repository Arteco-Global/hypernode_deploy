# Update Procedure

Questo documento riassume tutte le modalità di update disponibili e la logica di gestione dei file `.log` di env.

## Panoramica rapida

Ci sono due scenari principali:

1. **Update intera suite (Gateway Mode)**  
   Usa `native_update.sh` oppure `installer.sh` in modalità update per la suite completa.

2. **Update servizi accessori (Runner Mode)**  
   Usa `native_service_update.sh` per ricostruire il servizio + database partendo dal compose specifico.

## File env e log: dove sono e come si chiamano

Durante install/update vengono salvate le variabili in un file `.log`:

- **Suite**: `.hypernode-install-env.log`
- **Servizi accessori**: `.hypernode-install-<PROCESS_NAME>-env.log`
  - esempio: `.hypernode-install-additional-aux31-env.log`

Il file viene salvato:

- in `.` (directory corrente)
- e replicato in `/etc/.hypernode/`

Quando possibile, viene salvata anche una copia originale:

- `/etc/.hypernode/<nome_file>.original`

## Recupero env quando il file non esiste

Per la **suite**, `native_update.sh`:

- Se l’env manca, prova a scaricare ed eseguire `recreate_env_file.sh`.
- Se tutto va bene, crea un file `_restored_hypernode-install-env.log`
  e lo rinomina in `.hypernode-install-env.log`.

Per i **servizi accessori**, `native_service_update.sh`:

- richiede sempre `--env-file` per evitare update sul servizio sbagliato.

## Update intera suite

### Opzione A: `native_update.sh`

```bash
sudo installer_docker/native_update.sh --env-file .hypernode-install-env.log
```

Caratteristiche principali:

- scarica i compose dal repo GitHub (`installer_docker/composes`)
- ricostruisce database e servizi della suite
- sincronizza l’env in `/etc/.hypernode/`
- se manca l’env, prova a ricostruirlo

### Opzione B: `installer.sh` (modalità update suite)

```
INSTALL_OPTION = 8
```

In questa modalità l’installer fa un update completo della suite.

## Update servizi accessori

Usare sempre **`native_service_update.sh`** (con `--env-file` obbligatorio).

```bash
sudo installer_docker/native_service_update.sh \
  --env-file .hypernode-install-additional-aux31-env.log
```

Caratteristiche principali:

- ricostruisce **database + servizio** dal compose specifico
- usa le variabili già valorizzate nell’env file
- non usa il compose della suite (`server`) per evitare conflitti

Se `INSTALL_OPTION` non è presente o non è coerente:

```bash
sudo installer_docker/native_service_update.sh \
  --env-file .hypernode-install-additional-aux31-env.log \
  --service camera
```

Servizi supportati:

- `camera`
- `auth`
- `event`
- `storage`
- `snapshot`
- `recording`
- `metadata`

## Variabili richieste (servizi accessori)

Queste variabili **devono** essere valorizzate nell’env:

Generali:

- `DOCKER_TAG`
- `PROCESS_NAME`
- `DB_NAME`
- `DB_PORT`
- `RMQ`
- `GRI`

Volumi obbligatori (se il servizio li usa):

- `RECORDING_PATH` per `recording`
- `SNAPSHOT_PATH` per `snapshot`
- `STORAGE_PATH` per `storage`

Se questi path sono vuoti, Docker Compose fallisce con errori simili a:

```
invalid spec: :/recording_files: empty section between colons
```

## Note operative

- I compose vengono scaricati dal branch `main` (override con `--deploy-branch`).
- Entrambi gli script sincronizzano l’env in `/etc/.hypernode/`.
- Se l’update riguarda la suite, **non** usare `native_service_update.sh`.
- Se l’update riguarda un servizio accessorio, **non** usare `native_update.sh`
  (usa il compose della suite e può fallire se mancano path/variabili).

## Esempi rapidi

Suite:

```bash
sudo installer_docker/native_update.sh --env-file .hypernode-install-env.log
```

Servizio accessorio:

```bash
sudo installer_docker/native_service_update.sh \
  --env-file .hypernode-install-additional-aux31-env.log
```

## Download manuale degli script di update

Se devi scaricare gli script a mano su una macchina host, puoi usare:

```bash
BRANCH=main
BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/${BRANCH}/installer_docker"

wget -q -O installer_docker/native_update.sh "${BASE}/native_update.sh"
wget -q -O installer_docker/native_service_update.sh "${BASE}/native_service_update.sh"
chmod +x installer_docker/native_update.sh installer_docker/native_service_update.sh
```
