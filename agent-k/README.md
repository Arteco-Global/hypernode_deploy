# agent-k

## ITA

`agent-k` e' un watchdog esterno pensato per essere distribuito accanto a `hypernode-server`, ma separato dalla suite.

Questa cartella del repository `hypernode_deploy` contiene i file pubblici minimi per il deploy:

- `compose.yml`
- `config.example.yml`
- questo `README.md`

Il comportamento operativo e le istruzioni sotto sono allineati al repository principale di `agent-k`.

### Scopo

L'obiettivo del MVP e' scoprire automaticamente i container Hypernode-adjacent e applicare remediation automatica quando:

- l'immagine Docker matcha un prefisso monitorato, ad esempio `artecoglobalcompany/`;
- un container supera la soglia RAM configurata;
- un singolo container non restituisce metriche Docker per piu' cicli consecutivi;
- il restart e' ancora consentito da cooldown e rate limit globali;
- se un servizio viene riavviato, i suoi dipendenti Hypernode vengono riavviati in cascata secondo il compose ufficiale;
- se la RAM host resta troppo alta per troppo tempo, entra opzionalmente in una global intervention mode e riavvia uno alla volta i servizi che stanno consumando molto piu' della loro media storica.

### Storico e report

`agent-k` salva due tipi di dati in un database SQLite locale:

- `service_samples`: un record per ogni servizio valutato in ogni ciclo;
- `restart_events`: un record per ogni restart realmente eseguito, inclusi quelli in cascata e gli eventi della global intervention mode.

La retention elimina automaticamente:

- i sample piu' vecchi di `storage.sample_retention_days`;
- gli eventi di restart piu' vecchi di `storage.restart_retention_days`.

Nel `compose.yml` la directory host di lavoro viene montata interamente su `/agent-k-home`, quindi sia `config.yml` sia `data/agent-k.sqlite3` sopravvivono alla ricreazione del container con `docker compose up -d --force-recreate`.

### Deploy rapido

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
docker compose exec agent-k agent-k candidate-report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
docker compose exec agent-k agent-k relearn
```

Per fermarlo:

```bash
docker compose down
```

### Update della configurazione durante gli update remoti

Negli script di update di `hypernode_deploy`, il file `config.yml` di `agent-k` viene trattato cosi':

- in installazione iniziale, se non esiste, viene creato dal sample di default;
- in update, il sample nuovo viene fuso con il `config.yml` esistente;
- i valori custom gia' presenti vengono preservati;
- gli eventuali nuovi parametri introdotti dal sample vengono aggiunti automaticamente;
- viene salvato anche un backup del file precedente come `config.yml.bak`.

### Comandi utili

```bash
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k candidate-report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
docker compose exec agent-k agent-k plot recording --show mem --since 24h
docker compose exec agent-k agent-k plot recording --show cpu --since 24h
docker compose exec agent-k agent-k relearn
```

Sono accettate finestre come `30m`, `12h`, `7d`.

`relearn` salva una richiesta nello state file condiviso di `agent-k`: il processo gia' in esecuzione la recepisce al ciclo successivo e riparte da zero con la fase di learning della baseline globale.

Nei report e nello storico restart vengono distinti:

- restart da soglia del singolo servizio;
- restart da global threshold;
- restart da metrics failure;
- restart di dipendenza;
- eventi di `global entered`, `global recovered`, `global waiting` e `baseline reset`.

### Global Intervention Mode

La sezione `global_memory_intervention` e' facoltativa. Quando e' attiva:

- `agent-k` osserva la RAM host totale;
- su Linux legge `/proc/meminfo`;
- su Docker Desktop, se `/proc/meminfo` non e' disponibile sull'host locale del processo, prova a leggerlo dentro uno dei container in esecuzione, quindi usa la RAM della VM Docker;
- nei primi minuti costruisce una baseline "normale" della macchina;
- se la RAM host resta sopra `enter_percent` per `enter_duration_seconds`, entra in intervention mode;
- durante l'intervention mode cerca i servizi il cui `current_memory_percent - average_memory_percent` supera `allowed_delta_percent`;
- riavvia un solo servizio per step, aspetta `step_duration_seconds` e poi rivaluta la situazione;
- esce quando la RAM host torna sotto una soglia di recovery derivata dalla baseline e dal margine di sicurezza configurato.

### Elenco dipendenze servizi noti

L'ordine di boot sotto e' derivato dal compose server attuale di Hypernode. `agent-k` usa questo stesso modello di dipendenze per costruire la cascata dei restart.

#### Ordine di boot

1. `messagebroker`
2. `watchdog` dopo `messagebroker (service_healthy)`
3. `gateway` dopo `watchdog (service_started)`
4. `configurator` dopo `gateway (service_healthy)`
5. `export` dopo `configurator (service_started)`
6. `webserver` dopo `export (service_started)`
7. In parallelo dopo `webserver (service_healthy)`: `camera`, `auth`, `recording`, `snapshot`, `event`, `coretrust`, `metadata`
8. In parallelo quando sono veri entrambi `messagebroker (service_healthy)` e `webserver (service_healthy)`: `portbroker`

#### Dipendenze note per servizio

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

## ENG

`agent-k` is an external watchdog designed to be shipped alongside `hypernode-server`, while remaining separate from the suite.

This folder inside the `hypernode_deploy` repository contains the minimum public files required for deployment:

- `compose.yml`
- `config.example.yml`
- this `README.md`

The operational behavior and instructions below are aligned with the main `agent-k` repository.

### Purpose

The MVP automatically discovers Hypernode-adjacent containers and applies automatic remediation when:

- the Docker image matches a monitored prefix, such as `artecoglobalcompany/`;
- a container exceeds its configured RAM threshold;
- a single container fails to provide Docker metrics for multiple consecutive cycles;
- the restart is still allowed by cooldown and global rate-limit rules;
- when a service is restarted, its Hypernode dependents are restarted in cascade according to the official compose;
- host RAM stays too high for too long, optionally enabling a global intervention mode that restarts one service at a time based on deviation from its historical average.

### History and reports

`agent-k` stores two kinds of data in a local SQLite database:

- `service_samples`: one record for each evaluated service in each cycle;
- `restart_events`: one record for every actual restart, including cascade restarts and global intervention events.

The retention policy automatically deletes:

- samples older than `storage.sample_retention_days`;
- restart events older than `storage.restart_retention_days`.

In `compose.yml`, the entire working directory from the host is mounted into `/agent-k-home`, so both `config.yml` and `data/agent-k.sqlite3` survive container recreation with `docker compose up -d --force-recreate`.

### Quick deploy

```bash
mkdir -p ~/agent-k
cd ~/agent-k
wget -O compose.yml https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/agent-k/compose.yml
wget -O config.yml https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/agent-k/config.example.yml
mkdir -p data
```

Then edit `config.yml` for the target installation and start it:

```bash
docker compose pull
docker compose run --rm agent-k --config /agent-k-home/config.yml --dry-run --once
docker compose up -d --force-recreate
docker compose logs -f
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k candidate-report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
docker compose exec agent-k agent-k relearn
```

To stop it:

```bash
docker compose down
```

### Config update behavior during remote updates

In `hypernode_deploy` update scripts, the `agent-k` `config.yml` file is handled as follows:

- on first install, if it does not exist, it is created from the default sample;
- on update, the new sample is merged with the existing `config.yml`;
- existing custom values are preserved;
- any new parameters introduced by the sample are added automatically;
- a backup of the previous file is also written as `config.yml.bak`.

### Useful commands

```bash
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k candidate-report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
docker compose exec agent-k agent-k plot recording --show mem --since 24h
docker compose exec agent-k agent-k plot recording --show cpu --since 24h
docker compose exec agent-k agent-k relearn
```

Windows such as `30m`, `12h`, and `7d` are supported.

`relearn` writes a request into the shared runtime state file: the already-running `agent-k` process consumes it on the next cycle and restarts the global baseline learning phase from scratch.

Reports and restart history distinguish:

- service-threshold restarts;
- global-threshold restarts;
- metrics-failure restarts;
- dependency restarts;
- `global entered`, `global recovered`, `global waiting`, and `baseline reset` events.

### Global Intervention Mode

The `global_memory_intervention` section is optional. When enabled:

- `agent-k` observes total host RAM;
- on Linux it reads `/proc/meminfo`;
- on Docker Desktop, if `/proc/meminfo` is not available on the local host seen by the process, it tries to read it from one of the running containers and therefore uses the Docker VM memory;
- it learns a "normal" machine baseline during the first few minutes;
- if host RAM stays above `enter_percent` for `enter_duration_seconds`, it enters intervention mode;
- during intervention mode it looks for services whose `current_memory_percent - average_memory_percent` exceeds `allowed_delta_percent`;
- it restarts one service per step, waits `step_duration_seconds`, then reevaluates;
- it exits when host RAM falls below a recovery threshold derived from the learned baseline and configured safety margin.

### Known service dependency list

The boot order below is derived from the current Hypernode server compose. `agent-k` uses the same dependency model to build restart cascades.

#### Boot order

1. `messagebroker`
2. `watchdog` after `messagebroker (service_healthy)`
3. `gateway` after `watchdog (service_started)`
4. `configurator` after `gateway (service_healthy)`
5. `export` after `configurator (service_started)`
6. `webserver` after `export (service_started)`
7. In parallel after `webserver (service_healthy)`: `camera`, `auth`, `recording`, `snapshot`, `event`, `coretrust`, `metadata`
8. In parallel when both `messagebroker (service_healthy)` and `webserver (service_healthy)` are true: `portbroker`

#### Known dependencies by service

- `messagebroker`: no dependencies
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
