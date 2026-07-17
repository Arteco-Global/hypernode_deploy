# agent-k

`agent-k` e' un watchdog esterno pensato per essere distribuito accanto a `hypernode-server`, ma separato dalla suite.

Questa cartella del repository `hypernode_deploy` contiene i file pubblici minimi per il deploy:

- `compose.yml`
- `config.example.yml`
- questo `README.md`

Il comportamento operativo e le istruzioni sotto sono allineati al repository principale di `agent-k`.

## Scopo

L'obiettivo del MVP e' scoprire automaticamente i container Hypernode-adjacent e applicare remediation automatica quando:

- l'immagine Docker matcha un prefisso monitorato, ad esempio `artecoglobalcompany/`;
- un container supera la soglia RAM configurata;
- un singolo container non restituisce metriche Docker per piu' cicli consecutivi;
- il restart e' ancora consentito da cooldown e rate limit globali;
- se un servizio viene riavviato, i suoi dipendenti Hypernode vengono riavviati in cascata secondo il compose ufficiale;
- se la RAM host resta troppo alta per troppo tempo, entra opzionalmente in una global intervention mode e riavvia uno alla volta i servizi che stanno consumando molto piu' della loro media storica.

## Storico e report

`agent-k` salva due tipi di dati in un database SQLite locale:

- `service_samples`: un record per ogni servizio valutato in ogni ciclo;
- `restart_events`: un record per ogni restart realmente eseguito, inclusi quelli in cascata e gli eventi della global intervention mode.

La retention elimina automaticamente:

- i sample piu' vecchi di `storage.sample_retention_days`;
- gli eventi di restart piu' vecchi di `storage.restart_retention_days`.

Nel `compose.yml` la directory host di lavoro viene montata interamente su `/agent-k-home`, quindi sia `config.yml` sia `data/agent-k.sqlite3` sopravvivono alla ricreazione del container con `docker compose up -d --force-recreate`.

## Deploy rapido

```bash
mkdir -p ~/agent-k
cd ~/agent-k
wget -O compose.yml https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/agent-k/compose.yml
wget -O config.yml https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/agent-k/config.example.yml
mkdir -p data
```

Poi modifica `config.yml` secondo l'installazione e avvia:

```bash
docker compose pull
docker compose run --rm agent-k --config /agent-k-home/config.yml --dry-run --once
docker compose up -d --force-recreate
docker compose logs -f
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
```

Per fermarlo:

```bash
docker compose down
```

## Update della configurazione durante gli update remoti

Negli script di update di `hypernode_deploy`, il file `config.yml` di `agent-k` viene trattato cosi':

- in installazione iniziale, se non esiste, viene creato dal sample di default;
- in update, il sample nuovo viene fuso con il `config.yml` esistente;
- i valori custom gia' presenti vengono preservati;
- gli eventuali nuovi parametri introdotti dal sample vengono aggiunti automaticamente;
- viene salvato anche un backup del file precedente come `config.yml.bak`.

## Comandi utili

```bash
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
docker compose exec agent-k agent-k plot recording --show mem --since 24h
docker compose exec agent-k agent-k plot recording --show cpu --since 24h
```

Sono accettate finestre come `30m`, `12h`, `7d`.

Nei report e nello storico restart vengono distinti:

- restart da soglia del singolo servizio;
- restart da global threshold;
- restart da metrics failure;
- restart di dipendenza;
- eventi di `global entered`, `global recovered` e `global waiting`.

## Global Intervention Mode

La sezione `global_memory_intervention` e' facoltativa. Quando e' attiva:

- `agent-k` osserva la RAM host totale;
- su Linux legge `/proc/meminfo`;
- su Docker Desktop, se `/proc/meminfo` non e' disponibile sull'host locale del processo, prova a leggerlo dentro uno dei container in esecuzione, quindi usa la RAM della VM Docker;
- nei primi minuti costruisce una baseline "normale" della macchina;
- se la RAM host resta sopra `enter_percent` per `enter_duration_seconds`, entra in intervention mode;
- durante l'intervention mode cerca i servizi il cui `current_memory_percent - average_memory_percent` supera `allowed_delta_percent`;
- riavvia un solo servizio per step, aspetta `step_duration_seconds` e poi rivaluta la situazione;
- esce quando la RAM host torna sotto una soglia di recovery derivata dalla baseline e dal margine di sicurezza configurato.

## Elenco dipendenze servizi noti

L'ordine di boot sotto e' derivato dal compose server attuale di Hypernode. `agent-k` usa questo stesso modello di dipendenze per costruire la cascata dei restart.

### Ordine di boot

1. `messagebroker`
2. `watchdog` dopo `messagebroker (service_healthy)`
3. `gateway` dopo `watchdog (service_started)`
4. `configurator` dopo `gateway (service_healthy)`
5. `export` dopo `configurator (service_started)`
6. `webserver` dopo `export (service_started)`
7. In parallelo dopo `webserver (service_healthy)`:
   `camera`, `auth`, `recording`, `snapshot`, `event`, `coretrust`, `metadata`
8. In parallelo quando sono veri entrambi `messagebroker (service_healthy)` e `webserver (service_healthy)`:
   `portbroker`

### Dipendenze note per servizio

- `messagebroker`: nessuna dipendenza
- `watchdog`: `messagebroker (service_healthy)`
- `gateway`: `watchdog (service_started)`
- `configurator`: `gateway (service_healthy)`
- `export`: `configurator (service_started)`
- `webserver`: `export (service_started)`
- `camera`: `webserver (service_healthy)`
- `auth`: `webserver (service_healthy)`
- `recording`: `webserver (service_healthy)`
- `snapshot`: `webserver (service_healthy)`
- `event`: `webserver (service_healthy)`
- `coretrust`: `webserver (service_healthy)`
- `metadata`: `webserver (service_healthy)`
- `portbroker`: `messagebroker (service_healthy)`, `webserver (service_healthy)`
