# USS Restore - How To

Questa guida spiega come usare `uss_restore.sh` per ripristinare/aggiornare una installazione Hypernode, usando i parametri salvati nel file `.hypernode-install-env.log`.

## Cosa fa lo script
- Cerca un file `.hypernode-install-env.log` e lo usa per configurare il restore.
- Se non trova il file, raccoglie i valori in modo interattivo e crea il file.
- Effettua il login Docker se necessario.
- Crea `../hypernode_deploy` (cartella sorella rispetto alla directory corrente), la rende scrivibile da tutti.
- Copia `.hypernode-install-env.log` in `../hypernode_deploy` e, se presente l'installazione grafica, anche in `/opt/uSee-Service-Suite-Launcher/ussinstaller`.
- Scarica `native_update.sh`, lo esegue, poi lo elimina.
- Stampa due URL finali del configurator.

## Download rapido (wget) + permessi + esecuzione
Esegui questi comandi dalla directory in cui vuoi lanciare il restore:

```bash
wget -O uss_restore.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/uss_restore.sh
chmod +x uss_restore.sh
./uss_restore.sh
```

Se vuoi specificare un branch di deploy:

```bash
./uss_restore.sh --deploy-branch main
```

## Opzioni disponibili
```
--env-file <path>       Path to env file (default: ./.hypernode-install-env.log)
--deploy-branch <name>  Deploy branch for native_update.sh (default: main)
-h, --help              Show this help
```

## Come viene trovato il file `.hypernode-install-env.log`
Se **non** passi `--env-file`, lo script prova in questo ordine:
1. `./.hypernode-install-env.log` (directory corrente)
2. `../hypernode_deploy/.hypernode-install-env.log`
3. `/etc/.hypernode/.hypernode-install-env.log`
4. Ricerca sul filesystem di una cartella `hypernode_deploy` e relativo file `.hypernode-install-env.log`

Se lo trova in uno dei punti 2/3/4, lo copia in `./.hypernode-install-env.log` e lo usa da lì.

Se **non lo trova**, chiede i valori in modo interattivo e crea `./.hypernode-install-env.log`.

## Aggiornamento file in `/etc/.hypernode`

Sia `native_update.sh` che `uss_restore.sh` sincronizzano il file di env di sistema:

- al **primo giro** viene salvata una copia originale in
  `/etc/.hypernode/.hypernode-install-env.log.original`
- ad **ogni esecuzione** viene aggiornato
  `/etc/.hypernode/.hypernode-install-env.log`

## Variabili richieste (con default)
Quando il file manca, lo script chiede questi valori:
- `SSL_PORT` (default `10446`)
- `DOCKER_TAG` (default `staging`)
- `SERIAL_NUMBER` (obbligatoria)
- `SERVER_TIMEZONE` (default `Europe/Rome`)
- `SERVER_NAME` (obbligatoria)
- `ARTECO_GLOBAL_EMAIL` (obbligatoria)
- `ARTECO_GLOBAL_PASSWORD` (obbligatoria, input nascosto)
- `SERVER_IP_ADDRESS` (obbligatoria)
- `CERTIFICATE_PROVIDER_URL` (default `https://****.execute-api.eu-central-1.amazonaws.com/Cert/renew_hypernode`)
- `DNS_PROVIDER_URL` (default `https://****.execute-api.eu-central-1.amazonaws.com/dyndns/update_hypernode`)
- `LICENSE_PROVIDER_URL` (default `https://****.execute-api.eu-central-1.amazonaws.com/en/wp-json/sso-provider/login`)
- `RECORDING_PATH` (default `/recording`)
- `RECORDING_DISK_SPACE` (obbligatoria)
- `SNAPSHOT_PATH` (default `/snapshot`)
- `SNAPSHOT_DISK_SPACE` (obbligatoria)
- `DB_PORT` (default `27017`)
- `DB_NAME` (default `USS_SERVER`)
- `RMQ` (default `amqp://****:****@messagebroker:5672`)

I valori vengono salvati con escaping sicuro per evitare problemi con caratteri speciali (es. `!`).

## Login Docker
- Se Docker è già loggato, lo script continua.
- Se **non** è loggato:
  - usa `DOCKER_USERNAME` / `DOCKER_PASSWORD` se presenti nel file env
  - altrimenti chiede in modo interattivo:
    - username (default `artecoglobalcompany`)
    - access token (senza default)

Se lo script gira in modalità non interattiva e serve input (branch o login), termina con errore.

## Output finale
Alla fine stampa:
- `Configurator URL (if finalized): https://[SERIAL_NUMBER].lan.omniaweb.cloud:[SSL_PORT]`
- `Configurator URL (before finalizing): https://[SERVER_IP_ADDRESS]:[SSL_PORT]`
