# agent-k

`agent-k` e' un watchdog esterno pensato per essere distribuito accanto a `hypernode-server`, ma separato dalla suite.

L'obiettivo del MVP e' scoprire automaticamente i container Hypernode-adjacent e applicare remediation automatica quando:

- l'immagine Docker matcha un prefisso monitorato, ad esempio `artecoglobalcompany/`;
- un container supera la soglia RAM configurata;
- un singolo container non restituisce metriche Docker per piu' cicli consecutivi;
- il restart e' ancora consentito da cooldown e rate limit globali.
- se un servizio viene riavviato, i suoi dipendenti Hypernode vengono riavviati in cascata secondo il compose ufficiale.

## Scelte architetturali

- Runtime: Python 3.12
- Deployment: container Docker separato
- Controllo servizi: Docker Engine API
- Configurazione: YAML
- Storico operativo: SQLite locale
- Osservabilita': log tabellari leggibili in shell

L'approccio Docker-first evita dipendenze da `systemd`, dal process manager host e dalle differenze tra Ubuntu, Windows e macOS. Su VM Ubuntu il comportamento resta coerente: `agent-k` osserva i container dell'host Docker che gira nella VM.

## Cosa fa il MVP

- scopre automaticamente i container da monitorare tramite prefisso dell'immagine;
- raccoglie metriche container da Docker;
- scarica il compose server ufficiale di Hypernode all'avvio per ricostruire le dipendenze tra servizi;
- applica una policy RAM globale a tutti i container trovati;
- consente override specifici per servizio definiti nella config locale dell'installazione;
- traccia i fallimenti consecutivi nella raccolta metriche per singolo container;
- salva su SQLite ogni sample raccolto e ogni restart eseguito;
- riavvia il container se supera la soglia RAM;
- riavvia il container se le metriche restano indisponibili oltre la soglia configurata;
- dopo il restart di un servizio, riavvia in cascata i servizi che dipendono da lui, aspettando `service_started` o `service_healthy` secondo `depends_on`;
- espone report CLI per riepiloghi e restart recenti;
- applica cooldown e limiti ai restart per evitare flapping.

## Cosa non fa ancora

- metriche applicative avanzate come code backlog o ultimo job completato;
- health check applicativi per distinguere idle legittimo da blocco operativo;
- notifiche esterne;
- UI o dashboard.

## Struttura

```text
agent_k/
  config.py
  logging.py
  main.py
  models.py
  policies.py
  reporting.py
  runtime.py
  docker_api.py
  storage.py
config/
  agent-k.example.yml
compose.yml
```

## Configurazione

Esempio in `config/agent-k.example.yml`.

La configurazione definisce:

- i prefissi immagine da monitorare;
- la soglia RAM globale;
- il numero di cicli consecutivi di failure metriche che fa scattare un restart;
- cooldown e massimo numero di restart in una finestra temporale;
- il percorso del database SQLite locale e la retention dei sample storici;
- override opzionali per singolo servizio, definiti per installazione.

Gli override sono facoltativi. Se un servizio non ha una voce dedicata, continua a usare i default globali.

Le chiavi degli override matchano il nome del container in due modi:

- match esatto, ad esempio `recording` applica l'override al container `recording`
- match famiglia additional, quindi `recording` applica anche l'override a container come `recording_additional-mediarecorder`

Non viene piu' fatto fallback sul nome derivato dall'immagine.

## Storico e report

`agent-k` salva due tipi di dati in un database SQLite locale:

- `service_samples`: un record per ogni servizio valutato in ogni ciclo;
- `restart_events`: un record per ogni restart realmente eseguito, inclusi quelli in cascata.

La retention semplice del MVP elimina automaticamente:

- i sample piu' vecchi di `storage.sample_retention_days`;
- gli eventi di restart piu' vecchi di `storage.restart_retention_days`.

Nel `compose.yml` la cartella host `./data` e' montata su `/app/data`, quindi il file SQLite sopravvive alla ricreazione del container con `docker compose up -d --force-recreate`.

Per consultare lo storico:

```bash
agent-k report --since 24h
agent-k restarts --since 24h
agent-k plot recording --since 24h
agent-k plot recording --show mem --since 24h
agent-k plot recording --show cpu --since 24h
```

Sono accettate finestre come `30m`, `12h`, `7d`.

`report` e `restarts` provano a riusare automaticamente i path dell'ultimo `agent-k run` riuscito, in particolare:

- il file di configurazione usato al run;
- il path del database SQLite derivato da quella configurazione.

Se serve, puoi comunque passare `--config` esplicitamente.

## Regole operative del MVP

- Se la discovery globale dei container fallisce, `agent-k` non riavvia nulla in quel ciclo.
- Se un singolo container sparisce tra discovery e raccolta metriche, `agent-k` logga il caso e passa oltre.
- Se la raccolta metriche fallisce per un singolo container per piu' cicli consecutivi, `agent-k` prova a riavviarlo.
- Se un servizio viene riavviato, `agent-k` aspetta che soddisfi la condizione richiesta dai suoi dipendenti nel compose Hypernode e poi riavvia i dipendenti in cascata.
- Se un restart avviene davvero, i contatori interni di RAM e failure metriche vengono azzerati per quel container.
- In `--dry-run` vengono valutati i trigger ma non viene eseguito alcun restart.

## Avvio locale

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .
python -m agent_k.main --config config/agent-k.example.yml --dry-run --once
python -m agent_k.main report --since 24h
python -m agent_k.main restarts --since 24h
python -m agent_k.main plot recording --since 24h
```

## Docker

Il container deve poter leggere il Docker socket dell'host:

```bash
docker build -t agent-k .
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/config/agent-k.example.yml:/app/config.yml:ro \
  agent-k --config /app/config.yml
```

Su Docker Desktop per macOS e Windows il socket esposto dal motore Docker resta il punto di integrazione corretto.

## Docker Compose

Per il deployment su server conviene usare `compose.yml`.

### Deploy rapido da repository pubblici

Sul server puoi scaricare direttamente il compose pubblico da `hypernode_deploy`:

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
docker compose run --rm agent-k --config /app/config.yml --dry-run --once
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

### File minimi da copiare sul server

- `compose.yml`
- un file `config.yml` derivato da `config/agent-k.example.yml`

### Esempio `config.yml`

```yaml
poll_interval_seconds: 15

storage:
  path: ./data/agent-k.sqlite3
  sample_retention_days: 30
  restart_retention_days: 180

discovery:
  image_prefixes:
    - artecoglobalcompany/
  include_non_running: false

memory:
  max_percent: 85
  breach_cycles: 1

restart:
  cooldown_seconds: 300
  max_restarts: 3
  window_seconds: 3600
  metrics_failure_cycles: 3

service_overrides:
  recording:
    memory:
      max_percent: 50
      breach_cycles: 1
```

### Avvio

Modalita' osservativa:

```bash
docker compose run --rm agent-k --config /app/config.yml --dry-run --once
docker compose up -d
docker compose logs -f
docker compose exec agent-k agent-k report --since 24h
docker compose exec agent-k agent-k restarts --since 24h
docker compose exec agent-k agent-k plot recording --since 24h
```

Il `compose.yml` di default avvia `agent-k` in modalita' attiva. Se vuoi fare prima un test non distruttivo, usa il comando `run` mostrato sopra con `--dry-run`.

### Immagine personalizzata

Di default il compose usa `artecoglobalcompany/agent-k:latest`. Per cambiare immagine senza modificare il file:

```bash
export AGENT_K_IMAGE=tuo-username/agent-k:latest
docker compose up -d
```
