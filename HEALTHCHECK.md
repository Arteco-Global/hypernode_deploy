# HEALTHCHECK (USS)

Script: `installer_docker/uss_healthcheck.sh`

## Cosa fa
- Verifica che Docker sia disponibile e in esecuzione.
- Scarica i compose server/database (fallback ai locali se presenti) per ricavare i nomi dei container e ne mostra stato/health.
- Cerca la cartella `hypernode_deploy` nel sistema e controlla la presenza dei file attesi (log, config, script update).
- Legge `SERIAL` da `.hypernode-update-check.conf`, controlla la risoluzione DNS di `SERIAL.lan.omniaweb.cloud` verso l'IP locale e `serial.my.omniaweb.cloud` verso l'IP pubblico.
- Esegue `run-hypernode-update-check.sh --use-config --force-send` per inviare il payload.

## Come lanciarlo (supporto)
1) Accedi alla macchina via SSH (es. `ssh user@<ip>`).  
2) Esegui il comando one-shot:
   ```bash
   wget -O /tmp/uss_healthcheck.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/uss_healthcheck.sh && chmod +x /tmp/uss_healthcheck.sh && sudo /tmp/uss_healthcheck.sh
   ```
   - Richiede `wget` (o puoi sostituire con `curl -fsSL URL -o /tmp/uss_healthcheck.sh`).
   - Usa `sudo` per avere accesso al socket Docker.

## Cosa aspettarsi in output
- Messaggi `✅` per successi, `⚠️` per avvisi, `❌` per errori bloccanti.
- Elenco container con stato/health e indicazione running sì/no.
- Percorso della cartella `hypernode_deploy` trovata e presenza dei file attesi (con permessi/dimensioni).
- SERIAL letto e risultati delle risoluzioni DNS LAN/pubblica confrontate con IP locale/pubblico rilevati.
- Risultato dell'esecuzione di `run-hypernode-update-check.sh`.

## Note e prerequisiti
- Servono: Docker installato e in esecuzione; `wget` (o `curl`), `sudo`; strumenti DNS (`getent`/`dig`/`nslookup`/`host`) opzionali ma utili.
- Lo script cancella i compose temporanei che scarica in `/tmp`.
- Se Docker non è attivo o l'utente non ha permessi sul socket, verrà mostrato un errore subito.
