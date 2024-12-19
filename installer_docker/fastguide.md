
# Guida installare Hypernode su un computer vergine

## 1. Copiare il file su un server via ssh (ubunut)

 **Lanciare lo script di copia dell'installer**:
   ```bash
      sudo sh setup.sh
   ```
Seguire l'operazione di copia del file passo passo.

## 1. Avviare l'installazione

Connettersi al server via ssh al server e eseguire quanto sotto.

 **Lanciare l'installer complessivo**:
   ```bash
      sudo sh installer.sh
   ```

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
      sudo sh installer.sh
   ```
E scegliere l'opzione corrispondente per la scelta di un camera service aggiuntivo.
NB: se il gateway è installato in un computer remoto è necessario inserire il suo ip/url, altrimenti selezionare la voce "locale".

## 5. Per vederlo su USee

esegui "sudo nano /etc/hosts"

modifica il file aggiungendo sul tuo computer 

    #hypernode setup

    127.0.0.1 V12230451.lan.omniaweb.cloud
    127.0.0.1 V12230451.my.omniaweb.cloud

    #end hypernode setup

Fine

