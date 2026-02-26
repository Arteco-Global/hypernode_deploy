# Set Docker Tag (Env Log)

Questo documento descrive l'uso di `set_docker_tag.sh`, utile quando devi aggiornare
rapidamente il valore `DOCKER_TAG` nei file env log Hypernode (es. passaggio test -> preprod).

## Cosa fa lo script

`installer_docker/set_docker_tag.sh`:

1. Chiede in modo interattivo il nuovo tag Docker.
2. Cerca i file env log Hypernode in:
   - root del deploy (`hypernode_deploy`)
   - `/etc/.hypernode`
3. Aggiorna solo le righe `DOCKER_TAG=...`.
4. Stampa un report completo con:
   - file aggiornato
   - numero linea
   - valore precedente -> nuovo valore

## File coinvolti

Pattern gestiti:

- `.hypernode-install-env.log`
- `.hypernode-install-*-env.log`
- varianti senza punto iniziale (`hypernode-install-...`)
- eventuali copie `.original`

## Uso

```bash
installer_docker/set_docker_tag.sh
```

Help:

```bash
installer_docker/set_docker_tag.sh --help
```

## Download manuale sulla macchina

Percorso consigliato sulla macchina host:

`/home/arteco/hypernode_deploy/installer_docker/set_docker_tag.sh`

```bash
BRANCH=main
BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/${BRANCH}/installer_docker"

wget -q -O installer_docker/set_docker_tag.sh "${BASE}/set_docker_tag.sh"
chmod +x installer_docker/set_docker_tag.sh
```

## Note operative

- Lo script modifica solo i file `.log`, non i compose e non gli script di deploy.
- Se un file non è scrivibile direttamente, prova a scriverlo con `sudo`.
- Se non trova file compatibili, termina senza errori con messaggio informativo.
