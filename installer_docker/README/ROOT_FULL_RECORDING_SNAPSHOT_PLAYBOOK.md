# Playbook: root piena perché recording e snapshot scrivono sul filesystem host sbagliato

Questo playbook descrive come intervenire su un host Ubuntu quando i servizi `recording` e/o `snapshot` stanno scrivendo sulla root (`/`) invece che sul disco dati previsto, causando il riempimento del filesystem di sistema.

L'obiettivo è:

- non perdere registrazioni o snapshot già acquisiti
- spostare i dati sul filesystem corretto
- ripristinare la persistenza del mount dopo reboot

## Contesto Hypernode

Nel progetto Hypernode, i compose montano path host configurabili tramite env:

- `RECORDING_PATH` -> mount dentro il container su `/recording_files`
- `SNAPSHOT_PATH` -> mount dentro il container su `/snapshot_files`

Riferimenti nel repository:

- `installer_docker/composes/recording/docker-compose.yaml`
- `installer_docker/composes/snapshot/docker-compose.yaml`
- `installer_docker/README/UPDATE_PROCEDURE.md`
- `installer_docker/native_update.sh`

Gli script di update si aspettano che questi valori puntino a directory host reali, tipicamente su un filesystem montato, ad esempio:

- `/mnt/data/recording`
- `/mnt/data/snapshot`

Se invece tali path risultano directory locali sulla root, i container continuano a scrivere lì e il disco di sistema può saturarsi rapidamente.

## Quando usare questo playbook

Usare questa procedura quando si osserva uno scenario come questo:

- il server ha un disco root piccolo, tipicamente NVMe o SSD di sistema
- esiste un secondo disco dati destinato a recording e snapshot
- dopo un reboot o una riconfigurazione, i path host di `RECORDING_PATH` e/o `SNAPSHOT_PATH` puntano a directory sulla root
- nel giro di poco tempo il filesystem `/` si riempie
- il cliente non vuole perdere i dati già registrati

Scenario tipico:

- in fase di installazione il disco dati era stato predisposto correttamente
- il mount permanente non è stato configurato correttamente in `/etc/fstab`, oppure non è più effettivo
- dopo il reboot il sistema continua a funzionare, ma i dati finiscono sulla root

Importante:

- questo è uno scenario frequente, ma non va assunto come unica causa senza verifica
- il sintomo da trattare è che i path host configurati per recording/snapshot stanno scrivendo sul filesystem sbagliato

## Principio operativo

Se i dati stanno finendo sulla root, la priorità non è liberare spazio cancellando file, ma:

1. identificare il disco dati corretto
2. montarlo correttamente
3. copiare i dati senza perdita
4. ripristinare la configurazione persistente
5. solo alla fine eliminare il backup temporaneo

Non cancellare mai i dati dalla root prima di avere:

- completato la copia
- verificato i mount
- riavviato i container
- confermato che i servizi leggono dal nuovo filesystem

## Prerequisiti

Prima di procedere verificare tutti questi punti:

- si conosce quale disco deve ospitare i dati
- il disco individuato non contiene dati da preservare, oppure è già il disco dati corretto ma non montato
- si dispone di accesso `sudo`
- è possibile fermare temporaneamente i container `recording` e `snapshot`
- lo spazio sul disco dati è sufficiente

## 1. Diagnosi

Verificare saturazione root:

```bash
df -h /
```

Verificare l'occupazione delle directory host attualmente configurate.

Se l'ambiente è noto, leggere il file env della macchina Hypernode:

```bash
grep -E '^(RECORDING_PATH|SNAPSHOT_PATH)=' /etc/.hypernode/.hypernode-install-env.log
```

Se, ad esempio, i path risultano `/recording` e `/snapshot`, controllare dimensioni e filesystem:

```bash
sudo du -sh /recording /snapshot
findmnt /recording
findmnt /snapshot
df -h /recording /snapshot
```

Se l'env usa altri path host, sostituirli nei comandi.

Verificare dischi, partizioni e filesystem disponibili:

```bash
lsblk
sudo fdisk -l
sudo parted -l
sudo blkid
```

Verificare mount persistenti:

```bash
grep -nE 'recording|snapshot|mnt|data' /etc/fstab
sudo cat /etc/fstab
```

Il problema è confermato se:

- il path host configurato per `RECORDING_PATH` e/o `SNAPSHOT_PATH` risiede sul filesystem `/`
- il disco dati previsto non è montato oppure non è persistito correttamente

## 2. Valutare il caso reale

Prima di intervenire capire in quale dei due casi si rientra.

### Caso A: il disco dati esiste ma non è partizionato o non ha filesystem

Sintomi tipici:

- il disco secondario è visibile in `lsblk`
- non ci sono partizioni utili
- non c'è un filesystem montabile

In questo caso occorre creare partizione e filesystem prima della migrazione.

### Caso B: il disco dati è già pronto ma non è montato correttamente

Sintomi tipici:

- il disco o la partizione esistono già
- il filesystem è già presente
- il problema è il mount mancante o non persistito

In questo caso non bisogna formattare nulla: bisogna montare correttamente il filesystem esistente e poi migrare i dati.

## 3. Preparare il mount del disco dati

I comandi seguenti usano come esempio:

- disco: `/dev/sda`
- partizione: `/dev/sda1`
- mount point: `/mnt/hypernode-data`

Adattare i device reali al server su cui si interviene.

### Caso A: creare partizione e filesystem

```text
ATTENZIONE
Eseguire questi passaggi solo se si è verificato che il disco target è quello corretto
e che non contiene dati da mantenere.
```

Creare la partizione:

```bash
sudo parted -s /dev/sda mkpart primary ext4 0% 100%
sudo partprobe /dev/sda
lsblk /dev/sda
```

```text
ATTENZIONE
`mkfs.ext4` distrugge eventuali dati presenti sulla partizione target.
Non eseguire questo comando se la partizione contiene già dati da preservare.
```

Creare il filesystem:

```bash
sudo mkfs.ext4 -L hypernode-data /dev/sda1
sudo blkid /dev/sda1
```

### Caso B: montare un filesystem già esistente

Se la partizione esiste già, identificare UUID e tipo filesystem:

```bash
sudo blkid /dev/sda1
```

### Mount temporaneo

Montare temporaneamente il filesystem:

```bash
sudo mkdir -p /mnt/hypernode-data
sudo mount /dev/sda1 /mnt/hypernode-data
```

Preparare le directory dati:

```bash
sudo mkdir -p /mnt/hypernode-data/recording
sudo mkdir -p /mnt/hypernode-data/snapshot
```

## 4. Migrazione senza perdita dati

### Prima copia a caldo

Eseguire una prima copia mentre i container sono ancora attivi:

```bash
sudo rsync -aHAX --info=progress2 /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAX --info=progress2 /snapshot/ /mnt/hypernode-data/snapshot/
```

Se l'host usa path diversi da `/recording` e `/snapshot`, sostituirli con i valori reali di `RECORDING_PATH` e `SNAPSHOT_PATH`.

### Fermare solo i container coinvolti

Su installazioni con `PROCESS_NAME`, i container possono chiamarsi ad esempio `recording_<process>` e `snapshot_<process>`.
Identificare i nomi reali prima di fermarli:

```bash
sudo docker ps --format '{{.Names}}' | grep -E '^recording(_|$)|^snapshot(_|$)'
```

Poi fermare i container interessati:

```bash
sudo docker stop recording snapshot
```

Se i nomi sono suffissati, usare quelli effettivi.

### Sincronizzazione finale

Eseguire una seconda sincronizzazione incrementale con `--delete`:

```bash
sudo rsync -aHAX --delete --info=progress2 /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAX --delete --info=progress2 /snapshot/ /mnt/hypernode-data/snapshot/
```

## 5. Verifica della copia

Confrontare le dimensioni:

```bash
sudo du -sh /recording /mnt/hypernode-data/recording
sudo du -sh /snapshot /mnt/hypernode-data/snapshot
```

Verificare con dry-run:

```bash
sudo rsync -aHAXn --delete /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAXn --delete /snapshot/ /mnt/hypernode-data/snapshot/
```

Idealmente il dry-run non deve mostrare differenze.

## 6. Switch dei path host

```text
ATTENZIONE
Non eseguire questo passaggio finché la copia non è stata verificata.
Queste directory diventano il backup temporaneo di sicurezza.
```

Rinominare le directory attuali:

```bash
sudo mv /recording /recording.old
sudo mv /snapshot /snapshot.old
```

Ricreare i mount point vuoti:

```bash
sudo mkdir /recording
sudo mkdir /snapshot
```

Se `RECORDING_PATH` e `SNAPSHOT_PATH` usano path diversi, adattare di conseguenza anche i comandi `mv` e `mkdir`.

## 7. Configurazione permanente

Recuperare UUID:

```bash
sudo blkid -s UUID -o value /dev/sda1
```

```text
ATTENZIONE
Un errore in `/etc/fstab` può causare mount mancati al boot
o problemi di avvio del server. Verificare con attenzione UUID, path e sintassi.
```

Esempio di configurazione con filesystem dati condiviso e bind mount:

```fstab
UUID=<UUID_DI_SDA1> /mnt/hypernode-data ext4 defaults,nofail 0 2
/mnt/hypernode-data/recording /recording none bind 0 0
/mnt/hypernode-data/snapshot /snapshot none bind 0 0
```

Testare senza riavvio:

```bash
sudo umount /mnt/hypernode-data
sudo systemctl daemon-reload
sudo mount -a
```

Se il deployment Hypernode usa `.hypernode-install-env.log`, verificare che `RECORDING_PATH` e `SNAPSHOT_PATH` siano coerenti con i path appena ripristinati:

```bash
grep -E '^(RECORDING_PATH|SNAPSHOT_PATH)=' /etc/.hypernode/.hypernode-install-env.log
```

Se necessario, aggiornare il file env prima di futuri update del nodo.

## 8. Verifica dei mount e riavvio servizi

Verificare che tutto punti al filesystem corretto:

```bash
findmnt /mnt/hypernode-data
findmnt /recording
findmnt /snapshot
df -h /recording /snapshot
```

Riavviare i container:

```bash
sudo docker start recording snapshot
sudo docker ps --filter name=recording --filter name=snapshot
```

Verifica opzionale:

```bash
sudo docker logs --tail 50 recording
sudo docker logs --tail 50 snapshot
```

Su installazioni con nomi container suffissati, usare i nomi reali.

## 9. Cleanup finale

Eseguire questo passaggio solo dopo avere verificato che:

- i container sono tornati operativi
- i path host corretti sono effettivamente mountati
- i dati sono leggibili dai servizi

```text
ATTENZIONE
I comandi seguenti eliminano definitivamente il backup temporaneo.
Non eseguirli finché la verifica non è conclusa.
```

```bash
sudo rm -rf /recording.old
sudo rm -rf /snapshot.old
```

Adattare i path se l'installazione usa directory host differenti.

## 10. Verifica finale

```bash
df -h /
df -h /recording /snapshot
sudo du -sh /recording /snapshot
```

Nota importante:

- `df -h /recording /snapshot` mostra l'occupazione del filesystem che contiene quei path
- se entrambi stanno sullo stesso disco dati, `df` mostrerà gli stessi valori per entrambi
- questo non significa che recording e snapshot occupino singolarmente lo stesso spazio

Per capire quanto occupano davvero le directory usare:

```bash
sudo du -sh /recording /snapshot
```

## Esempio reale verificato

In un intervento reale è stata applicata con successo questa variante:

- root su `/dev/nvme0n1p2`, circa `228 GiB`
- disco secondario `/dev/sda`, circa `1.8 TiB`
- singola partizione ext4 su tutto il disco
- mount in `/mnt/hypernode-data`
- bind mount verso `/recording` e `/snapshot`

Stato finale osservato:

```text
/dev/nvme0n1p2  228G   59G  157G  28% /
/dev/sda1       1.8T  157G  1.6T   9% /recording
/dev/sda1       1.8T  157G  1.6T   9% /snapshot
```

---

# Playbook: root filesystem full because recording and snapshot are writing to the wrong host filesystem

This playbook explains how to recover an Ubuntu host when the `recording` and/or `snapshot` services are writing to the root filesystem (`/`) instead of the intended data disk, causing the system disk to fill up.

The goal is to:

- avoid losing existing recordings or snapshots
- move the data to the correct filesystem
- restore persistent mounts after reboot

## Hypernode context

In Hypernode, the compose files mount configurable host paths through env variables:

- `RECORDING_PATH` -> mounted inside the container as `/recording_files`
- `SNAPSHOT_PATH` -> mounted inside the container as `/snapshot_files`

Repository references:

- `installer_docker/composes/recording/docker-compose.yaml`
- `installer_docker/composes/snapshot/docker-compose.yaml`
- `installer_docker/README/UPDATE_PROCEDURE.md`
- `installer_docker/native_update.sh`

The update scripts expect these variables to point to real host directories, typically on a mounted filesystem, for example:

- `/mnt/data/recording`
- `/mnt/data/snapshot`

If those paths are instead local directories on the root filesystem, the containers keep writing there and the system disk can fill up quickly.

## When to use this playbook

Use this procedure when you see a scenario like this:

- the server has a small root disk, typically a system SSD or NVMe device
- there is a second disk intended for recording and snapshot data
- after a reboot or reconfiguration, the host paths used by `RECORDING_PATH` and/or `SNAPSHOT_PATH` are now directories on the root filesystem
- the `/` filesystem fills up shortly afterwards
- the customer does not want to lose existing data

Typical scenario:

- during installation, the data disk had been prepared correctly
- the persistent mount in `/etc/fstab` was not configured correctly, or is no longer effective
- after reboot, the node still runs, but data is being written to the root filesystem

Important:

- this is a common scenario, but it must not be assumed as the only cause without verification
- the symptom to fix is that the host paths used by recording/snapshot are writing to the wrong filesystem

## Operating principle

If data is being written to the root filesystem, the priority is not to free space by deleting files. The priority is:

1. identify the correct data disk
2. mount it correctly
3. copy the data without loss
4. restore persistent configuration
5. only at the end remove the temporary backup

Never delete data from the root filesystem before you have:

- completed the copy
- verified the mounts
- restarted the containers
- confirmed that the services are reading from the new filesystem

## Prerequisites

Before proceeding, confirm all of the following:

- you know which disk is supposed to store the data
- the target disk does not contain data that must be preserved, or it is already the correct data disk but currently not mounted
- you have `sudo` access
- you can temporarily stop the `recording` and `snapshot` containers
- the data disk has enough free space

## 1. Diagnosis

Check whether the root filesystem is full:

```bash
df -h /
```

Check the size of the currently configured host directories.

If the environment is known, inspect the Hypernode env file:

```bash
grep -E '^(RECORDING_PATH|SNAPSHOT_PATH)=' /etc/.hypernode/.hypernode-install-env.log
```

If, for example, the paths are `/recording` and `/snapshot`, inspect size and filesystem:

```bash
sudo du -sh /recording /snapshot
findmnt /recording
findmnt /snapshot
df -h /recording /snapshot
```

If the env file uses different host paths, replace them in the commands above.

Check disks, partitions, and filesystems:

```bash
lsblk
sudo fdisk -l
sudo parted -l
sudo blkid
```

Check persistent mounts:

```bash
grep -nE 'recording|snapshot|mnt|data' /etc/fstab
sudo cat /etc/fstab
```

The issue is confirmed if:

- the host path configured for `RECORDING_PATH` and/or `SNAPSHOT_PATH` is located on `/`
- the intended data disk is not mounted, or is not persisted correctly

## 2. Evaluate the actual case

Before acting, determine which of the following cases applies.

### Case A: the data disk exists but has no usable partition or filesystem

Typical symptoms:

- the secondary disk is visible in `lsblk`
- there are no useful partitions
- there is no mountable filesystem

In this case, you must create the partition and filesystem before migrating the data.

### Case B: the data disk is already prepared but not mounted correctly

Typical symptoms:

- the disk or partition already exists
- the filesystem already exists
- the problem is a missing or non-persistent mount

In this case, do not format anything. Mount the existing filesystem correctly and then migrate the data.

## 3. Prepare the data disk mount

The commands below use this example layout:

- disk: `/dev/sda`
- partition: `/dev/sda1`
- mount point: `/mnt/hypernode-data`

Replace the device names with the real ones on the target server.

### Case A: create partition and filesystem

```text
WARNING
Run these steps only after verifying that the target disk is the correct one
and that it does not contain data that must be preserved.
```

Create the partition:

```bash
sudo parted -s /dev/sda mkpart primary ext4 0% 100%
sudo partprobe /dev/sda
lsblk /dev/sda
```

```text
WARNING
`mkfs.ext4` destroys any existing data on the target partition.
Do not run this command if the partition already contains data that must be preserved.
```

Create the filesystem:

```bash
sudo mkfs.ext4 -L hypernode-data /dev/sda1
sudo blkid /dev/sda1
```

### Case B: mount an existing filesystem

If the partition already exists, identify its UUID and filesystem type:

```bash
sudo blkid /dev/sda1
```

### Temporary mount

Temporarily mount the filesystem:

```bash
sudo mkdir -p /mnt/hypernode-data
sudo mount /dev/sda1 /mnt/hypernode-data
```

Create the target data directories:

```bash
sudo mkdir -p /mnt/hypernode-data/recording
sudo mkdir -p /mnt/hypernode-data/snapshot
```

## 4. Migrate data without loss

### First hot copy

Run a first copy while the containers are still running:

```bash
sudo rsync -aHAX --info=progress2 /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAX --info=progress2 /snapshot/ /mnt/hypernode-data/snapshot/
```

If the host uses different paths than `/recording` and `/snapshot`, replace them with the actual values of `RECORDING_PATH` and `SNAPSHOT_PATH`.

### Stop only the affected containers

On installations using `PROCESS_NAME`, the containers may be named for example `recording_<process>` and `snapshot_<process>`.
Identify the real names first:

```bash
sudo docker ps --format '{{.Names}}' | grep -E '^recording(_|$)|^snapshot(_|$)'
```

Then stop the relevant containers:

```bash
sudo docker stop recording snapshot
```

If the names are suffixed, use the actual container names.

### Final synchronization

Run a second incremental sync with `--delete`:

```bash
sudo rsync -aHAX --delete --info=progress2 /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAX --delete --info=progress2 /snapshot/ /mnt/hypernode-data/snapshot/
```

## 5. Verify the copy

Compare the directory sizes:

```bash
sudo du -sh /recording /mnt/hypernode-data/recording
sudo du -sh /snapshot /mnt/hypernode-data/snapshot
```

Verify using a dry run:

```bash
sudo rsync -aHAXn --delete /recording/ /mnt/hypernode-data/recording/
sudo rsync -aHAXn --delete /snapshot/ /mnt/hypernode-data/snapshot/
```

Ideally, the dry run should show no differences.

## 6. Switch the host paths

```text
WARNING
Do not perform this step until the copy has been verified.
These directories become the temporary safety backup.
```

Rename the current directories:

```bash
sudo mv /recording /recording.old
sudo mv /snapshot /snapshot.old
```

Recreate empty mount points:

```bash
sudo mkdir /recording
sudo mkdir /snapshot
```

If `RECORDING_PATH` and `SNAPSHOT_PATH` use different directories, adapt the `mv` and `mkdir` commands accordingly.

## 7. Make the configuration persistent

Retrieve the UUID:

```bash
sudo blkid -s UUID -o value /dev/sda1
```

```text
WARNING
An error in `/etc/fstab` can cause mounts to fail at boot
or create startup issues for the server. Double-check UUID, paths, and syntax.
```

Example configuration using one shared data filesystem plus bind mounts:

```fstab
UUID=<UUID_DI_SDA1> /mnt/hypernode-data ext4 defaults,nofail 0 2
/mnt/hypernode-data/recording /recording none bind 0 0
/mnt/hypernode-data/snapshot /snapshot none bind 0 0
```

Test it without rebooting:

```bash
sudo umount /mnt/hypernode-data
sudo systemctl daemon-reload
sudo mount -a
```

If the Hypernode deployment uses `.hypernode-install-env.log`, verify that `RECORDING_PATH` and `SNAPSHOT_PATH` are consistent with the restored paths:

```bash
grep -E '^(RECORDING_PATH|SNAPSHOT_PATH)=' /etc/.hypernode/.hypernode-install-env.log
```

If needed, update the env file before future node updates.

## 8. Verify mounts and restart services

Verify that everything points to the correct filesystem:

```bash
findmnt /mnt/hypernode-data
findmnt /recording
findmnt /snapshot
df -h /recording /snapshot
```

Restart the containers:

```bash
sudo docker start recording snapshot
sudo docker ps --filter name=recording --filter name=snapshot
```

Optional log verification:

```bash
sudo docker logs --tail 50 recording
sudo docker logs --tail 50 snapshot
```

On installations with suffixed container names, use the actual names.

## 9. Final cleanup

Run this step only after verifying that:

- the containers are running again
- the correct host paths are effectively mounted
- the services can read the data

```text
WARNING
The following commands permanently remove the temporary backup.
Do not run them until verification is complete.
```

```bash
sudo rm -rf /recording.old
sudo rm -rf /snapshot.old
```

Adapt the paths if the installation uses different host directories.

## 10. Final verification

```bash
df -h /
df -h /recording /snapshot
sudo du -sh /recording /snapshot
```

Important note:

- `df -h /recording /snapshot` shows the usage of the filesystem containing those paths
- if both paths are on the same data disk, `df` will show the same values for both
- this does not mean that recording and snapshot individually consume the same space

To measure the actual size of the directories, use:

```bash
sudo du -sh /recording /snapshot
```

## Real verified example

In one real recovery, this variant was applied successfully:

- root on `/dev/nvme0n1p2`, about `228 GiB`
- secondary disk `/dev/sda`, about `1.8 TiB`
- one single ext4 partition across the entire disk
- mounted on `/mnt/hypernode-data`
- bind-mounted to `/recording` and `/snapshot`

Observed final state:

```text
/dev/nvme0n1p2  228G   59G  157G  28% /
/dev/sda1       1.8T  157G  1.6T   9% /recording
/dev/sda1       1.8T  157G  1.6T   9% /snapshot
```
