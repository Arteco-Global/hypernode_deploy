# FAQ - uSS Server

## Cosa succede se disabilito la licenza di un server mentre esso è in funzione?

Se la licenza di un server **uSS** viene disabilitata mentre il server è in funzione:

- Al successivo controllo della licenza (eseguito circa una volta all'ora) oppure al riavvio del server, la licenza verrà invalidata.
- **Il server non verrà arrestato**: continuerà a registrare e a trasmettere i flussi video tramite **uSee**.
- Non sarà però più possibile gestire il server tramite **Configurator**, poiché verrà sempre richiesto di completare nuovamente la procedura di licenza.
- Una volta scaduto il **lease DNS**, il server non sarà più raggiungibile tramite il relativo URL:
  ```
  https://VXXXXX.my.lan.omniaweb.cloud
  ```
- Non è possibile stabilire in anticipo quando scadrà il lease DNS, poiché la durata dipende dal provider e dalla configurazione della rete.

---

## Cosa succede se imposto l'indirizzo IP locale su "Auto" invece che su "Manuale"?

Se l'indirizzo IP locale viene impostato su **Auto**:

- Il sistema tenterà di determinare automaticamente l'indirizzo IP locale utilizzando il **primo indirizzo IP** trovato tra le interfacce di rete disponibili (potrebbe pertanto utilizzare una rete non raggiungibile dall'utente).
- Questa modalità è supportata **solo su Linux**.

> **Nota**
>
> Sui server **Windows** e **macOS** il rilevamento automatico dell'indirizzo IP **non è supportato**, poiché questi sistemi operativi non consentono di ottenere le informazioni necessarie della macchina host.

---

## Come faccio a raggiungere un server uSS dopo aver cambiato il suo indirizzo IP locale?

Se l'indirizzo IP del server **uSS** viene modificato (ad esempio cambiando sottorete o assegnando un nuovo indirizzo):

1. Collegarsi al Configurator utilizzando il nuovo indirizzo IP:
   ```
   https://NUOVO_INDIRIZZO_IP
   ```
2. Accettare l'avviso relativo al certificato HTTPS non valido.
3. Accedere al Configurator.
4. Aggiornare il parametro **Indirizzo IP locale** sostituendo il vecchio indirizzo con il nuovo:
   ```
   NUOVO_INDIRIZZO_IP
   ```
5. Attendere alcuni minuti affinché il nuovo record DNS venga propagato.

Una volta completata la propagazione del DNS, il server tornerà ad essere raggiungibile tramite il suo URL:

```
https://VXXXXX.my.lan.omniaweb.cloud
```

---

## Cosa succede alla licenza se un server va offline?

Se un server **uSS** perde la connessione a Internet:

- Il servizio che verifica la validità della licenza rileva l'assenza di connettività e **posticipa automaticamente il controllo della licenza**.
- Di conseguenza, **la licenza non viene invalidata** e il server continua a funzionare regolarmente.

Tuttavia, durante il periodo di assenza della connessione Internet, **la raggiungibilità del server tramite il nome DNS potrebbe non essere garantita**.

Questo può accadere se, mentre il server è offline, cambia uno dei seguenti indirizzi:

- l'indirizzo **IP locale** del server;
- l'indirizzo **IP pubblico** della rete;
- oppure entrambi.

In questi casi, il record DNS:

```
https://VXXXXX.my.lan.omniaweb.cloud
```

potrebbe non essere più allineato con gli indirizzi correnti del server.

Una volta ripristinata la connessione a Internet:

- il server aggiornerà automaticamente il proprio record DNS;
- dopo alcuni minuti sarà nuovamente raggiungibile tramite il relativo URL.

> **Nota**
>
> Anche nel caso in cui il record DNS non sia temporaneamente aggiornato, il server rimane sempre raggiungibile dalla rete locale tramite il suo indirizzo IP:
>
> ```
> https://INDIRIZZO_IP_LAN
> ```