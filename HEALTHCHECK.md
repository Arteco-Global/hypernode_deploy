# HEALTHCHECK (USS)

Script: `installer_docker/uss_healthcheck.sh`

## Cosa fa
- Verifica che Docker sia disponibile e in esecuzione; se trova `.hypernode-install-env.log` lo usa come sorgente primaria per risolvere i nomi templated dei compose e per recuperare parametri installativi utili al check.
- Legge i compose server/database (remoti o locali) per ricavare i container reali e ne stampa stato/health.
- Rileva il container del database dal runtime Docker e/o dall'env install, invece di assumere un nome fisso, e prova a ricavare la porta host effettiva del DB.
- Cerca la cartella `hypernode_deploy` nel sistema e controlla la presenza di `installer.sh` nel layout reale della target.
- Usa `SERIAL_NUMBER` da `.hypernode-install-env.log` per i controlli DNS.
- Chiama direttamente `${LICENSE_PROVIDER_URL}` usando come credenziali `ARTECO_GLOBAL_EMAIL` e `ARTECO_GLOBAL_PASSWORD` dall'env install.
- Con le porte recuperate, interroga:
  - `https://<serial>.lan.omniaweb.cloud:<site_lan_port>/api/v1/` (LAN)
  - `https://<serial>.my.omniaweb.cloud:<site_port>/api/v1/` (WAN)
  Verifica raggiungibilità, controlla il certificato HTTPS (validità e scadenza) e che `server.serial` nella risposta coincida con il serial del config. Se WAN non risponde, segnala che non è esposto e prosegue.
## Come lanciarlo (supporto)
1) Accedi alla macchina via SSH (es. `ssh user@<ip>`).  
2) Esegui il comando one-shot:
   ```bash
   wget -O /tmp/uss_healthcheck.sh https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/uss_healthcheck.sh && chmod +x /tmp/uss_healthcheck.sh && sudo /tmp/uss_healthcheck.sh
   ```
   - Richiede `wget` (o puoi sostituire con `curl -fsSL URL -o /tmp/uss_healthcheck.sh`).
   - Usa `sudo` per avere accesso al socket Docker.
   - Se vuoi usare un branch diverso (es. `staging`), aggiungi prima di inviare: `--deploy-branch staging` (esempio: `sudo /tmp/uss_healthcheck.sh --deploy-branch staging`).

## Cosa aspettarsi in output
- Output strutturato in sezioni numerate (Docker, Script necessari, Network con IP/DNS/Ports/Reachability/Certificate).
- Messaggi `✅`/`⚠️`/`❌`.
- Sorgente dell'env install rilevata, se presente.
- Stato/health dei container dai compose.
- Porta DB rilevata dal container reale o, in fallback, dall'env install.
- Presenza dei file attesi in `hypernode_deploy`.
- DNS LAN/Pubblico vs IP locali/pubblici.
- Esito endpoint licensing (HTTP 200 atteso) con `site_port`/`site_lan_port` per il serial in uso.
- Verifica certificato HTTPS e scadenza su LAN/WAN (WAN solo se raggiungibile).
- Esito reachability API (LAN/WAN) e confronto `server.serial`.

## Note e prerequisiti
- Servono: Docker installato e in esecuzione; `wget` (o `curl`), `sudo`; strumenti DNS (`getent`/`dig`/`nslookup`/`host`) opzionali ma utili.
- Lo script cancella i compose temporanei che scarica in `/tmp`.
- Se Docker non è attivo o l'utente non ha permessi sul socket, verrà mostrato un errore subito.
