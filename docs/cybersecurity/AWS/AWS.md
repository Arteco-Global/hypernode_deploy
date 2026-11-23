# 1. AWS

## 1.1. Autenticazione e licensing

Aggiornamento: 19 novembre 2026.

### Finalità e struttura

Il sistema di licensing Arteco utilizza servizi Amazon Web Services (AWS) e supporta l'autenticazione centralizzata Single Sign-On (SSO) per l'accesso a uSee.

Il servizio verifica le credenziali dell'utente, controlla l'abilitazione applicativa e recupera i siti, i server e le informazioni di licenza associati all'utente. L'autenticazione comprende il confronto della password con l'hash memorizzato e l'aggiornamento della data dell'ultimo login.

Le funzioni Lambda accedono direttamente al database per le operazioni di autenticazione e licensing. L’endpoint HTTPS pubblico del servizio SSO è esposto sull’hostname `www.arteco-global.com`, al percorso `/en/wp-json/sso-provider/login`.

La struttura comprende i seguenti servizi:

| Servizio | Funzione |
|---|---|
| AWS Lambda | Esecuzione della logica di autenticazione e autorizzazione. |
| Amazon RDS for MySQL | Archiviazione dei dati utenti, delle associazioni ai siti e delle informazioni di licensing, con motore MySQL Community. |
| AWS Secrets Manager | Gestione dei parametri e delle credenziali tecniche di connessione al database. |
| Elastic Load Balancing - Application Load Balancer (ALB) | Ingresso delle richieste e invocazione della funzione Lambda. |
| Amazon API Gateway | Esposizione dell'API collegata alla funzione Lambda. |
| Amazon VPC e security group | Configurazione della rete della Lambda e delle regole di accesso di rete. |
| AWS Key Management Service (KMS) | Gestione della chiave utilizzata per la cifratura dell'archiviazione del database. |

### Flusso applicativo

1. I punti di ingresso ALB e API Gateway sono integrati con la funzione Lambda che gestisce il servizio SSO.
2. La funzione recupera da AWS Secrets Manager i parametri e le credenziali di connessione al database.
3. La funzione accede direttamente al database RDS e verifica l'identità e l'abilitazione dell'utente.
4. Il servizio recupera le associazioni a siti e server e le relative informazioni di licenza.
5. Il chiamante riceve l'esito dell'autenticazione e, in caso di successo, i dati applicativi associati all'utente.

### Regioni e localizzazione dei dati

La funzione Lambda SSO e le istanze database sono localizzate nella regione **Europe (Frankfurt), `eu-central-1`, Germania**, nell'Unione europea.

| Risorsa | Localizzazione |
|---|---|
| Funzione Lambda SSO | Regione `eu-central-1`, con sottoreti configurate nelle Availability Zone `eu-central-1a`, `eu-central-1b` ed `eu-central-1c`. |
| Database `wordpress-mysql-20250515-1` | Regione `eu-central-1`, Availability Zone `eu-central-1c`. |
| Database di staging `wordpress-mysql-staging` | Regione `eu-central-1`, Availability Zone `eu-central-1c`. |
| Chiave KMS `aws/rds` dell'istanza `wordpress-mysql-20250515-1` | Regione `eu-central-1`. |

I dati gestiti comprendono identificativi e profili utente, indirizzi e-mail, hash delle password, ruoli e abilitazioni, associazioni tra utenti e siti, parametri e credenziali di accesso ai server, identificativi e stato delle licenze, scadenze e dotazioni dei canali autorizzati.

### Rete e collegamento al database

La connessione applicativa segue il percorso diretto **Lambda → Amazon RDS for MySQL**.

La Lambda è configurata nella VPC `wordpress-vpc`, con le sottoreti `wordpress-vpc-private-eu-central-1a`, `wordpress-vpc-private-eu-central-1b` e `wordpress-vpc-private-eu-central-1c`.

Alla funzione sono associati i security group `lambda-rds-1`, `lambda-rds-2`, `default` e `rds-lambda-1`.

### Cifratura a riposo e gestione delle credenziali

Per l'istanza `wordpress-mysql-20250515-1`, la **cifratura dell'archiviazione primaria è abilitata**, con chiave AWS KMS `aws/rds`. L'istanza utilizza MySQL `8.0.46-rds.20260624` e dispone della protezione da eliminazione abilitata.

Le credenziali tecniche di connessione al database sono gestite tramite AWS Secrets Manager. Il servizio SSO verifica la password dell'utente mediante il relativo hash e controlla l'abilitazione applicativa prima di restituire i dati dei siti associati.

## 1.2. Gestione del certificato HTTPS dei server uSS

Aggiornamento: 19 novembre 2026.

### Finalità e componenti

Il sistema gestisce il rinnovo e la distribuzione del certificato HTTPS esposto dai server uSS. Il certificato viene utilizzato per tutte le connessioni del client uSee verso uSS, incluse le comunicazioni HTTPS e WebSocket sicure (WSS), e supporta l'autenticazione del server e la protezione TLS dei dati in transito.

La gestione comprende due funzioni AWS Lambda: una dedicata al rinnovo presso la Certification Authority e una dedicata alla distribuzione del materiale TLS al server uSS.

| Componente | Funzione |
|---|---|
| Lambda di rinnovo | Generazione della chiave privata e della richiesta di certificato, gestione della validazione del dominio e pubblicazione del pacchetto aggiornato. |
| Let's Encrypt | Certification Authority utilizzata tramite il protocollo ACME per l'emissione dei certificati. |
| Cloudflare DNS | Gestione dei record TXT utilizzati per la verifica del controllo dei domini. |
| Amazon S3 | Archiviazione del pacchetto contenente il certificato e la relativa chiave privata. |
| Lambda di distribuzione | Autenticazione e autorizzazione della richiesta di download e recupero del pacchetto da S3. |
| Amazon API Gateway | Esposizione dell'API utilizzata dal server uSS per richiedere il pacchetto. |
| AWS Secrets Manager | Gestione delle credenziali e dei parametri per Cloudflare, S3 e il database di autenticazione. |
| Database MySQL di autenticazione e licensing | Verifica dell'utente, delle abilitazioni e dell'associazione del seriale uSS ai siti dell'utente. |

### Rinnovo e archiviazione

1. La Lambda di rinnovo recupera i parametri del dominio, il token per le API Cloudflare e la configurazione S3 da AWS Secrets Manager.
2. Genera una nuova chiave privata e una richiesta di firma del certificato (CSR), comprendente il nome principale e gli eventuali nomi alternativi configurati.
3. Avvia la procedura ACME con Let's Encrypt, utilizzando la challenge **DNS-01** per dimostrare il controllo dei domini.
4. Crea tramite API Cloudflare i record TXT `_acme-challenge` richiesti dalla validazione e ne gestisce la rimozione al termine della challenge.
5. Riunisce il certificato emesso e la relativa chiave privata in un pacchetto PEM compresso con gzip e lo carica nel bucket S3 configurato.

Il rinnovo comprende quindi la generazione di una nuova chiave privata associata al certificato. Il pacchetto conservato su S3 costituisce il materiale TLS destinato alla distribuzione ai server.

### Distribuzione al server uSS

Il server uSS richiede il pacchetto attraverso l'API di distribuzione via HTTPS, presentando le credenziali dell'utente e il proprio numero seriale.

La Lambda di distribuzione esegue i seguenti controlli prima di recuperare il pacchetto da S3:

1. Verifica la presenza delle credenziali e ricerca l'utente tramite nome utente o indirizzo e-mail.
2. Confronta la password ricevuta con l'hash memorizzato per l'utente.
3. Verifica l'abilitazione dell'utente al servizio uSee.
4. Recupera i siti associati all'utente e verifica che il seriale richiesto appartenga a uno dei server di tali siti.
5. Recupera da S3 il pacchetto configurato e lo restituisce al server richiedente.

Il server uSS scarica il materiale TLS per il proprio servizio HTTPS. Le successive connessioni uSee-uSS utilizzano il certificato esposto dal server.

### Protezioni applicative

| Ambito | Protezione implementata |
|---|---|
| Emissione del certificato | Validazione del controllo dei domini tramite challenge ACME DNS-01 e firma da parte della Certification Authority. |
| Credenziali tecniche | Recupero da AWS Secrets Manager delle configurazioni e delle credenziali necessarie alle due Lambda. |
| Accesso a S3 | Operazioni di caricamento e lettura tramite AWS SDK con credenziali AWS autenticate. |
| Download verso uSS | Trasporto HTTPS e controllo applicativo di credenziali, abilitazione utente e associazione del seriale a un sito autorizzato. |
| Gestione della risposta | Intestazioni `Cache-Control: no-store, no-cache, must-revalidate` e `Pragma: no-cache` per indicare ai destinatari di non conservare la risposta in cache; `X-Content-Type-Options: nosniff` per impedirne l'interpretazione come un tipo di contenuto diverso da quello dichiarato. |
| Connessioni uSee-uSS | Utilizzo del certificato sul server uSS per i canali HTTPS e WSS protetti da TLS. |

### Archiviazione del pacchetto TLS

Il bucket `arteco-global-client-sslcert-bucket` utilizza la **cifratura predefinita lato server con chiavi gestite da Amazon S3 (SSE-S3)** per i nuovi oggetti. La configurazione blocca l'utilizzo della cifratura con chiavi fornite dal cliente (SSE-C).

Il pacchetto corrente è archiviato con il nome `my.omniaweb.cloud.pem.gz`, nella classe di storage S3 Standard.

### Connessione HTTPS del configurator uSS

Il configurator uSS utilizza il medesimo certificato HTTPS del server. La connessione HTTPS al configurator negozia **TLS 1.3**, con **AES-256-GCM** per la cifratura e **X25519MLKEM768** per lo scambio di chiavi. Il certificato del server è riconosciuto come valido e attendibile dal browser.

### Dati gestiti e collocazione

Il processo tratta certificato, chiave privata, nomi dei domini, record DNS di validazione, credenziali tecniche, credenziali dell'utente, seriale del server e associazioni utente-sito-server.

Il materiale TLS è conservato nel bucket Amazon S3 `arteco-global-client-sslcert-bucket`, nella regione **Europe (Frankfurt), `eu-central-1`, Germania**, e viene distribuito ai server uSS, dove è utilizzato per le connessioni con il client uSee. L'endpoint API Gateway utilizzato per il download è nella regione **Europe (Frankfurt), `eu-central-1`, Germania**.

## 1.3. Gestione automatica dei nomi DNS dei server uSS

Aggiornamento: 19 novembre 2026.

### Finalità e componenti

Il servizio DNS dinamico associa a ogni installazione uSS due nomi utilizzati da uSee per raggiungere il server:

| Nome DNS | Destinazione |
|---|---|
| `[seriale].my.omniaweb.cloud` | Indirizzo IPv4 pubblico (WAN) dell'installazione. |
| `[seriale].lan.omniaweb.cloud` | Indirizzo IPv4 locale (LAN) del server. |

Il servizio CoreTrust di uSS rileva gli indirizzi e richiede la registrazione o l'aggiornamento dei nomi. Una funzione AWS Lambda gestisce le operazioni sui record attraverso le API Cloudflare.

| Componente | Ruolo |
|---|---|
| CoreTrust sul server uSS | Rilevamento degli indirizzi, invio delle richieste e gestione dell'esito degli aggiornamenti. |
| AWS Lambda | Elaborazione delle richieste e creazione o aggiornamento dei record DNS. |
| Amazon API Gateway | Esposizione dell'API di aggiornamento. |
| AWS Secrets Manager | Gestione del token Cloudflare e dei parametri di accesso al database. |
| Database MySQL di licensing | Associazione tra licenze e seriali e registrazione della porta di connessione del server. |
| API Cloudflare | Creazione e aggiornamento dei record nella zona DNS configurata. |
| ipify | Rilevamento dell'indirizzo IPv4 pubblico quando è selezionata la modalità automatica. |

### Attivazione e condizioni di aggiornamento

CoreTrust avvia il controllo DNS all'avvio del servizio e lo ripete all'intervallo configurato. La modalità automatica utilizza un intervallo di **300 secondi**; gli intervalli numerici inferiori a 300 secondi vengono ricondotti a tale valore.

Gli indirizzi possono essere impostati manualmente oppure rilevati automaticamente. In modalità automatica, CoreTrust utilizza il primo indirizzo locale restituito dal rilevamento delle interfacce e interroga ipify via HTTPS per conoscere l'indirizzo pubblico.

Per LAN e WAN, CoreTrust invia una richiesta quando l'indirizzo rilevato o configurato differisce dall'ultimo aggiornato con successo durante l'esecuzione del servizio. Prima dell'invio controlla la disponibilità delle credenziali SSO, del seriale, della porta HTTPS e del materiale PEM del server. La porta predefinita è 443.

Il completamento dell'installazione attiva inoltre un aggiornamento LAN che include lo stato di configurazione, la data di attivazione e il valore di licenza generato per il server. Il ciclo periodico gestisce anche l'indirizzo WAN.

### Creazione e aggiornamento dei record

La Lambda recupera da Secrets Manager il token di accesso Cloudflare, la zona DNS e i parametri del database. Per ciascun nome ricerca il record esistente e procede alla creazione o all'aggiornamento del record di tipo **A**, associandolo all'indirizzo IPv4 richiesto.

Le richieste alle API Cloudflare impostano un TTL di **60 secondi** e la modalità **DNS-only**, con proxy disattivato. Il DNS fornisce quindi l'indirizzo per il collegamento diretto di uSee al server uSS; le connessioni applicative utilizzano HTTPS e WSS sul server.

La porta di connessione viene registrata nel database applicativo insieme al seriale. Dopo una risposta positiva, CoreTrust memorizza l'indirizzo aggiornato e comunica l'esito all'interfaccia applicativa. Gli errori producono notifiche e consentono un nuovo tentativo nei cicli successivi.

### Trasporto e gestione dei segreti

Le richieste di aggiornamento originate da CoreTrust utilizzano HTTPS e trasmettono i parametri nel corpo di una richiesta POST. Le operazioni della Lambda verso le API Cloudflare utilizzano il token di autenticazione del servizio; le chiamate di ricerca e aggiornamento impiegano HTTPS con autenticazione Bearer.

Il token Cloudflare e le credenziali del database vengono recuperati tramite AWS Secrets Manager. La Lambda accetta le interfacce `my` e `lan` e controlla la presenza del nome host e dell'indirizzo richiesti prima di elaborare l'aggiornamento.

### Dati trattati

Il processo tratta il seriale dell'installazione, i nomi DNS, gli indirizzi IPv4 LAN e WAN, la porta di connessione e i dati di autenticazione e licensing necessari alla gestione della richiesta. I record A associano i nomi dei server agli indirizzi nella zona DNS Cloudflare. Il rilevamento automatico dell'indirizzo pubblico comporta una richiesta dal server uSS al servizio ipify.

## 1.4. uSee

### 1.4.1. uSee - servizi esterni

Aggiornamento: 19 novembre 2026.

### <u>MongoDB Atlas: servizio e localizzazione</u>

Il backend di uSee utilizza un database MongoDB gestito attraverso la piattaforma **MongoDB Atlas**, ospitato su infrastruttura **Amazon Web Services**. Il cluster `OmniaWebCluster` è localizzato nella regione **Europe (Milan), `eu-south-1`, Italia**, nell'Unione europea.

MongoDB Atlas fornisce il servizio di gestione del database; AWS fornisce l'infrastruttura cloud su cui è ospitato il cluster.

#### Configurazione del cluster MongoDB

| Caratteristica | Configurazione |
|---|---|
| Nome del cluster | `OmniaWebCluster` |
| Motore | MongoDB 8.0.37 |
| Tier | M10 (General) |
| Struttura | Replica set composto da tre nodi: un primario e due secondari. |
| Regione dei tre nodi | AWS Milano, `eu-south-1`. |
| RAM del tier | 2 GB |
| Capacità di storage configurata | 10 GB |
| Espansione dello storage | Automatica. |
| Cifratura dello storage | Abilitata. |
| Backup | Cloud Backup attivo. |

La struttura a replica set mantiene i dati replicati fra i tre nodi del cluster. La cifratura dello storage protegge i dati a riposo, mentre il servizio Cloud Backup conserva snapshot secondo la pianificazione definita.

#### Pianificazione e conservazione dei backup MongoDB

| Tipologia | Frequenza | Conservazione |
|---|---|---|
| Snapshot infragiornalieri | Ogni 6 ore. | 2 giorni. |
| Snapshot giornalieri | Ogni giorno. | 7 giorni. |
| Snapshot settimanali | Ogni sabato. | 4 settimane. |
| Snapshot mensili | Ultimo giorno del mese. | 12 mesi. |

L'orario di riferimento della pianificazione è **13:20 UTC**, corrispondente alle 14:20 in Italia durante l'ora solare e alle 15:20 durante l'ora legale.

### <u>Redis: informazioni live e Pub/Sub</u>

Il backend uSee utilizza **Redis Cloud**, servizio gestito attraverso la console Redis, per le informazioni in tempo reale sugli utenti connessi. Redis gestisce informazioni live tramite **Publish/Subscribe (Pub/Sub)**: i dati sono **volatili e mantenuti in memoria**, con persistenza e backup remoto disattivati. **TLS è disattivato**. Il meccanismo Pub/Sub permette la pubblicazione e la ricezione degli aggiornamenti tramite canali sottoscritti dai componenti applicativi.

Il database `usee-chat-prod` è ospitato su infrastruttura **AWS nella regione US East (N. Virginia), `us-east-1`, Stati Uniti**. Le informazioni live gestite da questo servizio vengono quindi elaborate nella regione Virginia settentrionale.

| Caratteristica | Configurazione |
|---|---|
| Nome del database | `usee-chat-prod` |
| Servizio gestito | Redis Cloud |
| Infrastruttura | AWS, `us-east-1`, Virginia settentrionale, Stati Uniti. |
| Tipo e versione | Redis Stack 7.4 |
| Protocollo configurato | RESP3 |
| Alta disponibilità | Attiva. |
| Persistenza dei dati | Modalità in memoria, con persistenza disattivata (`None`). |
| Policy di espulsione dei dati | `volatile-lru` |
| Backup remoto | Disattivato. |
| TLS del servizio Redis | Disattivato. |
| Utente predefinito | Disattivato. |
| Lista di indirizzi CIDR consentiti | Disattivata. |

Le localizzazioni dei due servizi dati del backend sono **Milano, Italia, per MongoDB Atlas** e **Virginia settentrionale, Stati Uniti, per Redis Cloud**.

### 1.4.2. uSee - deploy

Aggiornamento: 19 novembre 2026.

#### Infrastruttura e localizzazione

Il frontend e il backend di uSee sono eseguiti come applicazioni containerizzate su **Red Hat OpenShift Container Platform 4.17.12**, ospitata su istanze **Amazon EC2** nella regione **Europe (Ireland), `eu-west-1`, Irlanda**, nell'Unione europea.

Il cluster comprende cinque istanze di tipo `m6i.xlarge`:

| Ruolo | Numero di istanze | Availability Zone |
|---|---|---|
| Nodi di controllo (master) | 3 | Un nodo in ciascuna zona: `eu-west-1a`, `eu-west-1b`, `eu-west-1c`. |
| Nodi applicativi (worker) | 2 | Un nodo in `eu-west-1a` e uno in `eu-west-1b`. |

L'applicazione è organizzata nel progetto `usee-production`, con due Deployment distinti, ciascuno configurato con **due repliche**:

| Componente | Repliche configurate | Servizio interno |
|---|---|---|
| Frontend | 2 | TCP 3000 |
| Backend | 2 | TCP 5000 |

Entrambi i componenti utilizzano controlli di avvio, vitalità e disponibilità (startup, liveness e readiness probe), che consentono alla piattaforma di monitorare i container e la loro disponibilità a ricevere traffico. Per ogni container sono configurate richieste di 256 MiB di memoria e 250 millicore CPU, con limiti di 512 MiB e 500 millicore CPU.

Le immagini applicative sono distribuite tramite Docker Hub con un tag di rilascio configurabile. Il backend si collega ai servizi esterni MongoDB Atlas e Redis Cloud e al provider SSO. Le route OpenShift indirizzano le richieste applicative verso il servizio frontend e sono gestite separatamente dai Deployment.

#### Accesso applicativo e sicurezza HTTPS

Il punto di ingresso pubblico di riferimento per gli utenti uSee è **`vms.usee.cloud`**, raggiungibile tramite HTTPS. Il certificato identifica `vms.usee.cloud` sia nel Subject sia nei Subject Alternative Names (SAN).

La connessione HTTPS al portale utilizza i seguenti parametri negoziati:

| Parametro | Valore |
|---|---|
| Versione del protocollo | TLS 1.3 |
| Scambio di chiavi | X25519 |
| Cifratura | AES-128-GCM |
| Firma del server nella connessione TLS | RSA-PSS con SHA-256 |

Il certificato è riconosciuto dal browser come attendibile e dispone di attestazioni Certificate Transparency verificate.

Il portale fornisce l'accesso all'applicazione cloud uSee. Le connessioni HTTPS/WSS del client verso i server uSS utilizzano i rispettivi indirizzi dei server. Per i video WebRTC, il collegamento avviene direttamente in P2P oppure, quando questo non è possibile, tramite i relay TURN descritti nel paragrafo 1.4.3.

#### Distribuzione geografica dei componenti uSee

| Componente | Servizio | Regione |
|---|---|---|
| Frontend e backend applicativo | OpenShift su Amazon EC2 | Irlanda, `eu-west-1`. |
| Database applicativo | MongoDB Atlas su AWS | Milano, `eu-south-1`. |
| Informazioni live e Pub/Sub | Redis Cloud su AWS | Virginia settentrionale, USA, `us-east-1`. |

### 1.4.3. uSee - relay TURN per i video WebRTC

Aggiornamento: 19 novembre 2026.

#### Funzione e percorso del video

Il servizio TURN supporta le sessioni video WebRTC fra il client uSee e il server uSS nelle installazioni in cui NAT restrittivi, firewall o altre condizioni di rete impediscono il collegamento diretto peer-to-peer.

**I video transitano attraverso i server TURN solo quando il collegamento P2P non è possibile.** Quando la comunicazione diretta è disponibile, il flusso video WebRTC viene scambiato direttamente tra uSee e uSS.

#### Istanze e localizzazione

Il servizio è distribuito mediante repliche su istanze **Amazon EC2 di tipo `t3a.small`** in tre regioni:

| Pool TURN | Regione AWS | Paese |
|---|---|---|
| Ireland | Europe (Ireland), `eu-west-1` | Irlanda |
| Capetown | Africa (Cape Town), `af-south-1` | Sudafrica |
| Ohio | US East (Ohio), `us-east-2` | Stati Uniti |

L'istanza TURN in Irlanda è collocata nell'Availability Zone `eu-west-1a`.

#### Selezione del relay

Cloudflare Load Balancing gestisce la selezione dei pool con policy **Proximity steering**, basata sulla prossimità geografica. Il pool Ireland è configurato come fallback quando tutti i pool risultano non disponibili secondo i controlli di salute.

Quando una sessione utilizza il relay, il traffico video transita nella regione del server TURN selezionato, in Irlanda, Sudafrica o Stati Uniti. Le istanze EC2 svolgono il ruolo di relay del traffico WebRTC.
