# HEALTHCHECK (USS)

Script: `installer_docker/uss_healthcheck.sh`

## Cosa fa
- Verifica che Docker sia disponibile e in esecuzione; legge i compose server/database (remoti o locali) per ricavare i container e ne stampa stato/health.
- Cerca la cartella `hypernode_deploy` nel sistema e controlla la presenza dei file attesi (log, config, script update).
- Legge `SERIAL` da `.hypernode-update-check.conf`, controlla la risoluzione DNS di `SERIAL.lan.omniaweb.cloud` verso l'IP locale e `serial.my.omniaweb.cloud` verso l'IP pubblico.
- Chiama `${LICENSING_URL}/sites` con credenziali/serial del config, verifica HTTP 200 ed estrae `site_port`/`site_lan_port` per il serial in uso.
- Con le porte recuperate, interroga:
  - `https://<serial>.lan.omniaweb.cloud:<site_lan_port>/api/v1/` (LAN)
  - `https://<serial>.my.omniaweb.cloud:<site_port>/api/v1/` (WAN)
  Verifica raggiungibilità, controlla il certificato HTTPS (validità e scadenza) e che `server.serial` nella risposta coincida con il serial del config. Se WAN non risponde, segnala che non è esposto e prosegue.
- Esegue `run-hypernode-update-check.sh --use-config --force-send` per inviare il payload (se disponibile).

## Come lanciarlo (supporto)
1) Accedi alla macchina via SSH (es. `ssh user@<ip>`).  
2) Esegui il comando one-shot:
   ```bash
   wget -O /tmp/uss_healthcheck.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/uss_healthcheck.sh && chmod +x /tmp/uss_healthcheck.sh && sudo /tmp/uss_healthcheck.sh
   ```
   - Richiede `wget` (o puoi sostituire con `curl -fsSL URL -o /tmp/uss_healthcheck.sh`).
   - Usa `sudo` per avere accesso al socket Docker.

## Cosa aspettarsi in output
- Output strutturato in sezioni numerate (Docker, Script necessari, Network con IP/DNS/Ports/Reachability/Certificate, Updates).
- Messaggi `✅`/`⚠️`/`❌`.
- Stato/health dei container dai compose.
- Presenza dei file attesi in `hypernode_deploy`.
- DNS LAN/Pubblico vs IP locali/pubblici.
- Esito licensing `/sites` (HTTP 200 atteso) con `site_port`/`site_lan_port` per il serial in uso.
- Verifica certificato HTTPS e scadenza su LAN/WAN (WAN solo se raggiungibile).
- Esito reachability API (LAN/WAN) e confronto `server.serial`.
- Risultato dell'esecuzione di `run-hypernode-update-check.sh`.

## Note e prerequisiti
- Servono: Docker installato e in esecuzione; `wget` (o `curl`), `sudo`; strumenti DNS (`getent`/`dig`/`nslookup`/`host`) opzionali ma utili.
- Lo script cancella i compose temporanei che scarica in `/tmp`.
- Se Docker non è attivo o l'utente non ha permessi sul socket, verrà mostrato un errore subito.
