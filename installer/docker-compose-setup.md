
# Guida installare Hypernode su un computer vergine

## 1. Installa Docker

### Su macOS:
1. **Scarica Docker Desktop per macOS** dal sito ufficiale: [Docker Desktop for Mac](https://www.docker.com/products/docker-desktop).
2. **Installa Docker** aprendo il file `.dmg` scaricato e trascinando l'icona di Docker nella cartella delle applicazioni.
3. **Avvia Docker** dall'applicazione. Durante il primo avvio, potrebbe chiederti di inserire la password di amministratore per configurare Docker.

### Su Windows:
1. **Scarica Docker Desktop per Windows** dal sito ufficiale: [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop).
2. **Installa Docker** eseguendo il file `.exe` scaricato. Durante l'installazione, potrebbe essere necessario abilitare la virtualizzazione BIOS.
3. **Avvia Docker** dopo l'installazione.

### Su Ubuntu (solo ubuntu è stato testato):
1. **Aggiorna i pacchetti**:
   ```bash
   sudo apt-get update
   ```

2. **Installa i pacchetti richiesti**:
   ```bash
   sudo apt-get install apt-transport-https ca-certificates curl software-properties-common
   ```

3. **Aggiungi la chiave GPG di Docker**:
   ```bash
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
   ```

3. **Aggiungi add-apt-repository**:
   ```bash
   sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
   ```

3. **Aggiungi le policy**:
   ```bash
   apt-cache policy docker-ce
   ```

4. **Aggiungi le policy**:
   ```bash
      sudo apt install docker-ce
   ```


4. **Verificare che docker sia installato**:
   ```bash
      sudo systemctl status docker
   ```
   Questo comando dovebbe tornare come ultima riga 'Started Docker Application Container Engine'

   
## 2. Opzione 1 -Copia i file sorgente (installazione offline)

Estrarre il file hypernode.zip fornito con questo file in una cartella sel sistema operativo.
La struttura dovrà essere la seguente:

   hypernode
      | - hypernode_server_gui
      | - hypernode_deploy
      | - hypernode-server

a questo punto è necessario entrare nella cartella 'hypernode_deploy'.

 **Lanciare l'installer complessivo**:
   ```bash
      sudo sh setup.sh
   ```
Seguire l'installazzione del server passo passo indicando le porte necessarie per l'avvio e l'eventuale url del messagebroker.

## 2. Opzione 2 - usare lo script di download automatica (installazzione online)

 **Lanciare il downloader **:
   ```bash
      sudo sh download_repo.sh
   ```
Seguire l'installazzione del server passo passo indicando le porte necessarie per l'avvio e l'eventuale url del messagebroker.


## 5. Verifica che l'interfaccia funzioni correttamente
Accedi ai servizi esposti tramite il browser utilizzando come porta quella indicata come porta per il configurator, di default la porta è la 8080.
   ```
   http://localhost:8080
   ```

## 5. Verifica che il server funzioni correttamente
Accedi ai servizi esposti tramite il browser utilizzando come porta quella indicata come porta per il server (HTTP), di default la porta è la 80.
   ```
   http://localhost:80
   ```
Se correttamente funzionante si dovrebbe vedere il testo '!!!!! HYPERNODE HOME PAGE DEBUG MODE !!!!!'

## 5. Aggiungere un camera service aggiuntivo
Accedi ai servizi esposti tramite il browser utilizzando come porta quella indicata come porta per il server (HTTP), di default la porta è la 80.
 **Lanciare l'installer complessivo**:
   ```bash
      sudo sh setup.sh
   ```
E scegliere l'opzione corrispondente per la scelta di un camera service aggiuntivo.
NB: se il gateway è installato in un computer remoto è necessario inserire il suo ip/url, altrimenti selezionare la voce "locale".