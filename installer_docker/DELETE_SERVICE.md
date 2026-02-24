# Delete Additional Services

Questo documento descrive come eliminare in blocco i **servizi aggiuntivi** Hypernode
presenti su host usando `delete_service.sh`.

## Cosa fa lo script

Lo script:

1. Legge `docker ps` e individua i container dei servizi aggiuntivi (`*_additional-*`).
2. Determina per ogni istanza:
   - container servizio (es: `camera_additional-aux31`)
   - container database (es: `database-for-additional-aux31`)
3. Recupera il file env log associato:
   - `./.hypernode-install-<istanza>-env.log`
   - fallback: `/etc/.hypernode/.hypernode-install-<istanza>-env.log`
4. Dal log legge i path dati eventuali:
   - `STORAGE_PATH`
   - `SNAPSHOT_PATH`
   - `RECORDING_PATH`
5. Cancella i path trovati con `rm -rf` (anche se non vuoti).
6. Rimuove i container (servizio + database).
7. Rimuove i volumi Docker associati ai container.
8. Elimina il file env log in tutte le repliche note:
   - file principale
   - copia in working directory
   - copia in `/etc/.hypernode/`
   - eventuali file `.original`

## Requisiti

- Docker installato e accessibile.
- Permessi adeguati (`sudo` se necessario).
- Presenza dei file env log per le istanze in esecuzione.

Se manca un env log per un servizio rilevato, lo script termina con errore senza procedere.

## Uso

```bash
sudo installer_docker/delete_service.sh
```

Per eliminare un singolo servizio aggiuntivo:

```bash
sudo installer_docker/delete_service.sh --service camera_additional-pippo
```

Per esecuzione non interattiva (skip conferma):

```bash
sudo installer_docker/delete_service.sh --yes
```

Help:

```bash
installer_docker/delete_service.sh --help
```

## Note operative

- Lo script agisce solo sui servizi aggiuntivi rilevati in **esecuzione** (`docker ps`).
- Prima di procedere chiede conferma interattiva (`Sei sicuro...? [s/N]`), salvo uso di `--yes`.
- Per sicurezza non rimuove path pericolosi come `/`, `.`, `..`.
- Per la suite principale usare le procedure dedicate (`native_update.sh`, `installer.sh`).
