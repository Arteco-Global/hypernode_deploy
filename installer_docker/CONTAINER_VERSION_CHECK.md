# Monitoraggio versioni dei container Hypernode

Questo documento descrive come funzionano gli script che estraggono la versione reale dei container Hypernode, verificano la presenza di nuove immagini nel registry e pianificano controlli periodici.

## Panoramica

Gli script coinvolti sono:

- `dump-container-versions.sh` – interroga Docker per ogni container uSee in esecuzione e genera `container_versions.json` con `image`, `digest`, `tag`, `version` (se disponibile) e timestamp di build.
- `check-container-updates.sh` – legge il JSON e confronta i digest locali con quelli pubblicati su Docker Hub usando `docker manifest inspect`.
- `run-hypernode-update-check.sh` – orchestration script. Esegue i precedenti, installa dipendenze (`jq` se assente), gestisce la pianificazione con cron, salva credenziali, intervallo e uno storico in modo sicuro.

## Prerequisiti

- Docker già installato e configurato sul server.
- Credenziali Docker valide per il registry Arteco (`DOCKER_USERNAME` e `DOCKER_PASSWORD`).
- Accesso `sudo` (per installare `jq` se manca).

## Prima esecuzione (setup)

1. Copia i tre script nella directory `~/installer_docker/` e rendili eseguibili:
   ```bash
   chmod +x dump-container-versions.sh check-container-updates.sh run-hypernode-update-check.sh
   ```
2. Lancia `run-hypernode-update-check.sh` fornendo credenziali, parametri licensing e intervallo:
   ```bash
   ./run-hypernode-update-check.sh \
     --docker-username=artecoglobalcompany \
     --docker-password=TOKEN \
     --user-login=utente@example.com \
     --user-password=PASSWORD \
     --serial=SERIALE_HARDWARE \
     --licensing-url=https://licensing.example.com \
     --interval=30m
   ```
   - L’intervallo accetta numeri con suffisso `s`, `m`, `h`, `d` (default minuti se omesso). Esempi: `45m`, `2h`, `1d`.
   - L’esecuzione iniziale:
     - genera `container_versions.json`,
     - installa `jq` se necessario,
     - salva le informazioni in `.hypernode-update-check.conf`,
     - registra l’ultima esecuzione in `.hypernode-update-check.state`,
     - aggiunge una voce cron che riesegue lo script ogni minuto con `--use-config`.

## Esecuzioni pianificate

- Cron richiama lo script ogni minuto:
  ```bash
  /bin/bash -lc '"/home/arteco/installer_docker/run-hypernode-update-check.sh" --use-config'
  ```
- Ad ogni invocazione lo script:
  - carica credenziali, parametri licensing e intervallo dal file di configurazione,
  - verifica da `.hypernode-update-check.state` da quanto tempo è passato,
  - se non è trascorso l’intervallo richiesto, esce e logga “Esecuzione saltata…“,
  - altrimenti ripete dump e check, aggiorna il timestamp, invia il payload JSON all’endpoint `LICENSING_URL/update` e registra l’attività nel log.

## Rilanci manuali

- Per forzare un controllo usando i valori salvati:
  ```bash
  ./run-hypernode-update-check.sh --use-config
  ```
  (continua comunque a rispettare l’intervallo).
- Per modificare l’intervallo, rilancia lo script fornendo un nuovo `--interval`; la configurazione e la voce cron verranno aggiornate.

## Disattivazione e pulizia

Eseguire:
```bash
./run-hypernode-update-check.sh --remove-schedule
```
- Rimuove la voce cron, cancella `.hypernode-update-check.conf` e `.hypernode-update-check.state`, e logga l’operazione.
- Puoi verificare l’assenza del job con `crontab -l | grep hypernode-update-check`.

## Log e file generati

| File | Descrizione |
| ---- | ----------- |
| `container_versions.json` | Snapshot corrente delle immagini uSee in esecuzione. |
| `container_update_report.json` | Risultati del confronto remoto, con `uptodate` per ogni servizio. |
| `.hypernode-update-check.conf` | Credenziali, parametri licensing e intervallo salvati (permessi 600). |
| `.hypernode-update-check.state` | Timestamp Unix dell’ultima esecuzione riuscita. |
| `hypernode-update-check.log` | Storico dettagliato delle esecuzioni, degli invii e delle azioni cron. |

## Payload inviato

Il payload JSON spedito a `LICENSING_URL/update` ha la forma:

```json
{
  "user_login": "utente@example.com",
  "user_password": "PASSWORD",
  "serial": "SERIALE_HARDWARE",
  "server": {
    "services": [
      {
        "name": "gateway",
        "image": "artecoglobalcompany/usee_suite_manager:latest",
        "digest": "artecoglobalcompany/usee_suite_manager@sha256:...",
        "tag": "latest",
        "version": "unknown",
        "created": "2025-10-08T15:18:55.494809839Z",
        "uptodate": true
      }
    ]
  }
}
```

Il campo `uptodate` è `true` se il digest remoto coincide con quello in esecuzione, `false` in caso contrario o se il digest non è recuperabile. Eventuali errori di fetch vengono salvati nel campo opzionale `check_error` dentro ogni servizio e registrati nel log.

Il log può essere consultato con:
```bash
tail -f hypernode-update-check.log
```

## Troubleshooting rapido

- **`jq` mancante**: lo script tenta l’installazione automatica tramite `apt-get`. Se fallisce, installalo manualmente e rilancia.
- **Penginazione non parte**: verifica il file di configurazione e controlla `crontab -l`. In caso di dubbi, rimuovi e reinstalla la schedulazione.
- **Log vuoto**: assicurati che `hypernode-update-check.log` sia scrivibile (lo script lo crea con permessi 600) e che lo script venga eseguito con l’utente previsto (es. `arteco`).

Con questa configurazione otterrai un monitoraggio continuo dei digest delle immagini Hypernode e potrai individuare rapidamente la disponibilità di nuove build sul registry Arteco.
