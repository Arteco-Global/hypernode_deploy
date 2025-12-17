# HEALTHCHECK (USS)

Script: `installer_docker/uss_healthcheck.sh`

## Cosa fa (modalità attuale)
- Usa `.hypernode-update-check.conf` per chiamare `${LICENSING_URL}/sites`, verifica HTTP 200 ed estrae `site_port`/`site_lan_port` per il serial in uso.
- Con le porte recuperate, interroga `https://<serial>.lan.omniaweb.cloud:<site_lan_port>/api/v1/`, verifica raggiungibilità, controlla il certificato HTTPS (validità e scadenza) e che `server.serial` nella risposta coincida con il serial del config.
- Gli altri controlli (Docker, compose, container health, file check, DNS/IP, run-update-check) restano nel codice ma sono commentati: scommentarli quando servono di nuovo.

## Come lanciarlo (supporto)
1) Accedi alla macchina via SSH (es. `ssh user@<ip>`).  
2) Esegui il comando one-shot:
   ```bash
   wget -O /tmp/uss_healthcheck.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/uss_healthcheck.sh && chmod +x /tmp/uss_healthcheck.sh && sudo /tmp/uss_healthcheck.sh
   ```
   - Richiede `wget` (o puoi sostituire con `curl -fsSL URL -o /tmp/uss_healthcheck.sh`).
   - Usa `sudo` per avere accesso al socket Docker.

## Cosa aspettarsi in output
- Messaggi `✅`/`⚠️`/`❌`.
- Esito licensing `/sites` (HTTP 200 atteso) con `site_port`/`site_lan_port` per il serial in uso.
- Risultato verifica certificato HTTPS e scadenza su `<serial>.lan.omniaweb.cloud:<site_lan_port>`.
- Esito reachability API e confronto `server.serial`.
- Gli altri output (container, file, DNS/IP, run-update-check) torneranno quando le sezioni saranno scommentate.

## Note e prerequisiti
- Servono: Docker installato e in esecuzione; `wget` (o `curl`), `sudo`; strumenti DNS (`getent`/`dig`/`nslookup`/`host`) opzionali ma utili.
- Lo script cancella i compose temporanei che scarica in `/tmp`.
- Se Docker non è attivo o l'utente non ha permessi sul socket, verrà mostrato un errore subito.
