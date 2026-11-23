# AWS - Promemoria interno delle verifiche

Aggiornamento: 19 novembre 2026.

Documento di lavoro interno, separato dal capitolo destinato alla condivisione.

## Priorità per la risposta A02

- [ ] Completare l'inventario dei servizi effettivamente coinvolti in autenticazione e licensing, includendo i punti di ingresso e gli eventuali servizi di logging e backup.
- [ ] Confermare le regioni delle risorse in produzione: Lambda SSO e RDS già documentati a Francoforte; completare ALB/API Gateway, Secrets Manager, log, backup ed eventuali copie.
- [ ] Associare a ogni servizio le categorie di dati trattati, distinguendo elaborazione, archiviazione e log.
- [ ] Reperire gli eventuali ID di qualificazione ACN delle offerte effettivamente utilizzate e verificarne stato, perimetro e applicabilità alla configurazione e alla regione adottate. Non usare ARN o ID account come ID ACN e non dedurre la qualificazione della soluzione Arteco dalla sola qualifica del provider.

## 1.1. Autenticazione e licensing

### Connessione Lambda-database: priorità corrente

- [ ] Recuperare il valore effettivo di `require_secure_transport` per `wordpress-mysql-20250515-1`.
- [ ] Recuperare `tls_version`, ossia le versioni TLS consentite dal database.
- [ ] Verificare la cifratura effettiva della sessione aperta dalla Lambda, con `SHOW SESSION STATUS LIKE 'Ssl_cipher';` e `SHOW SESSION STATUS LIKE 'Ssl_version';`, eseguiti sulla stessa connessione applicativa.
- [ ] Verificare la configurazione TLS del client MySQL, inclusa la validazione del certificato e del nome del server. Il pool `mysql2` esaminato non configura esplicitamente `ssl`.

La Lambda utilizza una connessione diretta al database: RDS Proxy non fa parte del percorso. Le versioni consentite dal server non dimostrano quale versione sia negoziata dalla Lambda; una verifica eseguita da un altro client riguarda soltanto la sessione di quel client.

Gruppo di parametri da consultare: `wordpress-mysql-20250515-1-20250516074751919600000001`, regione `eu-central-1`. Il gruppo risulta sincronizzato. La lettura dei parametri è rimasta bloccata dai permessi disponibili; è stata richiesta l'abilitazione di CloudShell e dell'accesso in lettura ai servizi AWS.

### Punti di ingresso SSO

- [ ] Precisare il percorso delle richieste attraverso ALB e API Gateway e i rispettivi endpoint utilizzati.
- [ ] Confermare le regioni delle risorse ALB e API Gateway.
- [ ] Rilevare listener, certificati, punti di terminazione TLS e versioni TLS ammesse per ciascun tratto.
- [ ] Completare il percorso di ingresso precedente ai servizi AWS.

### Rete e ambienti

- [ ] Confermare endpoint del database e associazione degli ambienti alle rispettive istanze.
- [ ] Verificare regole in uscita dalla Lambda, regole in ingresso al DB, tabelle di routing ed eventuale esposizione pubblica del database.
- [ ] Verificare configurazioni Multi-AZ ed eventuali repliche.
- [ ] Identificare le categorie di dati presenti in staging e le relative modalità di protezione.

### Cifratura a riposo, backup e conservazione

- [ ] Verificare cifratura a riposo e chiave KMS dell'istanza di staging.
- [ ] Documentare protezione, regioni, conservazione e copie di backup e snapshot.
- [ ] Documentare localizzazione, accesso e conservazione dei log.
- [ ] Verificare formato e protezione delle credenziali di accesso ai server gestite dal sistema di licensing.

La cifratura dell'archiviazione primaria di `wordpress-mysql-20250515-1` è già confermata, con chiave `aws/rds` a Francoforte.

### Segreti e configurazione distribuita

- [ ] Confermare la regione di Secrets Manager nella configurazione distribuita; la configurazione applicativa esaminata indica `eu-central-1`.
- [ ] Verificare i permessi IAM effettivi di accesso al segreto e la rotazione delle credenziali DB.
- [ ] Confrontare l'implementazione esaminata con quella effettivamente distribuita nella Lambda.
- [ ] Verificare e gestire il logging dei segreti: l'implementazione esaminata contiene istruzioni che registrano l'oggetto restituito da Secrets Manager e la configurazione di connessione, inclusa la password DB. Accertare se tali istruzioni siano distribuite e se i log contengano credenziali; in caso di riscontro, definire rimozione del logging, trattamento dei log e rotazione delle credenziali interessate.

## 1.2. Gestione del certificato HTTPS dei server uSS

### Regioni e configurazione distribuita

- [x] Identificato il bucket del certificato: `arteco-global-client-sslcert-bucket`, regione `eu-central-1` (Francoforte, Germania).
- [ ] Confermare le regioni delle due Lambda e dei segreti. La configurazione dei segreti indica `eu-central-1`.
- [ ] Confermare l'ambiente ACME effettivo: il template di rinnovo imposta `ENVIRONMENT=staging`, mentre l'implementazione seleziona Let's Encrypt production soltanto con valore `production`.
- [ ] Confermare domini e SAN del certificato in uso, eventuali wildcard, autorità emittente, algoritmo, dimensione della chiave e validità.
- [ ] Confermare pianificazione, fuso orario, allarmi ed esito del rinnovo. Il template prevede EventBridge Scheduler con `cron(0 0 1 * ? *)`; verificare lo stato distribuito e la gestione dei fallimenti, che possono essere intercettati senza propagare un errore all'handler.
- [ ] Confrontare le implementazioni esaminate con le versioni effettivamente distribuite.

### Protezione del materiale TLS e S3

- [x] Cifratura predefinita del bucket: SSE-S3; SSE-C bloccata. La voce Bucket Key abilitata non dimostra l'utilizzo di SSE-KMS: il tipo predefinito indicato è SSE-S3.
- [x] Identificato il pacchetto corrente `my.omniaweb.cloud.pem.gz`, classe Standard, ultima modifica 1 novembre 2026. Presente anche l'oggetto separato `Old_Apr25_my.omniaweb.cloud.pem.gz`: non è una prova dell'attivazione del versioning S3.
- [x] Rilevato Block Public Access disattivato nelle quattro impostazioni del bucket e assenza di bucket policy.
- [ ] Verificare Object Ownership, ACL del bucket e del singolo oggetto, access point e Block Public Access a livello account/organizzazione prima di determinare l'accessibilità pubblica effettiva. Il blocco disattivato non equivale di per sé ad accesso pubblico.
- [ ] Verificare la cifratura effettiva nelle proprietà del pacchetto corrente e dell'oggetto storico.
- [ ] Verificare le policy IAM dei soggetti con accesso al materiale TLS e l'obbligo HTTPS: non è presente una bucket policy che neghi il trasporto non sicuro.
- [ ] Valutare l'attivazione di Block Public Access e di una policy che imponga HTTPS, dopo aver verificato gli accessi applicativi necessari. Nessuna modifica infrastrutturale eseguita.
- [ ] Chiarire necessità, accesso e conservazione dell'oggetto storico contenente materiale TLS.
- [ ] Verificare privilegi e rotazione delle credenziali AWS recuperate dal segreto per accedere a S3, distinguendo scrittura del rinnovatore e lettura del provider.
- [ ] Verificare versioning, repliche, retention e accesso alle versioni precedenti del pacchetto, che include la chiave privata. Gzip e Base64 sono codifiche, non cifratura.
- [ ] Chiarire l'ambito di condivisione del certificato e della chiave: il provider legge un unico percorso S3 configurato, indipendente dal seriale autorizzato. Verificare impatto e procedura di revoca/rotazione in caso di compromissione di un server.
- [ ] Verificare privilegi del token Cloudflare, limitazione alle zone interessate, rotazione e affidabilità della pulizia delle challenge DNS.

### Autenticazione, trasporto e log

- [ ] Verificare TLS minimo, cifrari, certificati e percorso completo dell'endpoint HTTPS di download.
- [ ] Verificare la protezione delle credenziali nella richiesta: l'handler riceve username e password nei parametri query di una GET e contiene il logging dei parametri quando è presente `key`. Controllare log Lambda, API e intermediari e valutare lo spostamento delle credenziali fuori dall'URL.
- [ ] Verificare il logging della configurazione MySQL: l'handler registra l'oggetto del segreto, potenzialmente includendo la password DB. Se presente in produzione, gestire rimozione del logging, log pregressi e rotazione.
- [ ] Verificare TLS della connessione provider-MySQL: il pool esaminato non configura esplicitamente `ssl`.
- [ ] Verificare rate limiting e protezione dai tentativi di autenticazione ripetuti sull'API.
- [ ] Precisare le regole di autorizzazione: il controllo implementato verifica credenziali, abilitazione uSee e appartenenza del seriale a un sito dell'utente; non è stato identificato un controllo esplicito della scadenza della licenza né una prova crittografica dell'identità del dispositivo. Il parametro `key` non è validato come fattore di autorizzazione.

### Installazione e utilizzo sul server uSS

- [ ] Verificare frequenza del download, controlli sul certificato ricevuto, validazione TLS del client di download e comportamento in caso di errore.
- [ ] Verificare percorso locale, permessi di accesso e protezione della chiave privata sul server uSS.
- [ ] Verificare installazione atomica del pacchetto e ricaricamento del servizio HTTPS dopo il rinnovo.
- [x] Confermata una connessione HTTPS al configurator uSS con TLS 1.3, AES-256-GCM e X25519MLKEM768, e certificato valido e attendibile. Il configurator utilizza lo stesso certificato HTTPS del server uSS.
- [ ] Rilevare la versione TLS minima e l'insieme delle versioni e dei cifrari ammessi dal server per HTTPS e WSS. La connessione al configurator conferma i parametri negoziati su quel collegamento; verificare separatamente le connessioni operative uSee-uSS e le eventuali terminazioni TLS distinte.

## 1.3. Gestione automatica dei nomi DNS dei server uSS

### Allineamento del percorso applicativo e autorizzazione

- [ ] Identificare l'endpoint e la versione Lambda effettivamente usati da CoreTrust. Il client usa `DNS_PROVIDER_URL`, con fallback `dns.usee.cloud`; una configurazione di installazione punta ad API Gateway in `eu-central-1`, rotta `/dyndns/update_hypernode`. La Lambda esaminata espone invece `/dyndns/update`.
- [ ] Risolvere la differenza di contratto: CoreTrust invia `sso_email`, `sso_password`, `serial` e, alla finalizzazione, `configured`, `activation_date`, `license_hash`; l'handler Lambda esaminato legge invece `license_key`, `license_dump`, interfaccia, hostname, IP e porta. Non attribuire al percorso uSS i controlli di autenticazione di una versione diversa.
- [ ] Verificare autorizzazione effettiva agli aggiornamenti: la Lambda esaminata ricerca il seriale dalla chiave di licenza nel DB e costruisce da tale seriale il nome DNS. Il controllo dello User-Agent non costituisce autenticazione. Non sono presenti controlli espliciti di scadenza della licenza nel percorso esaminato.
- [ ] Confermare gestione dei metadati di finalizzazione dell'installazione sul servizio realmente distribuito.

### TLS e protezione delle richieste

- [ ] Verificare e correggere la validazione del certificato nel client DNS di CoreTrust: `postFormResponse` imposta `rejectUnauthorized: false`. La connessione usa HTTPS ma non verifica il certificato del servizio remoto, con rischio di intercettazione delle credenziali e manipolazione delle richieste.
- [ ] Verificare l'eventuale autenticazione TLS del client: CoreTrust passa `cert` alla richiesta ma questo non dimostra un mTLS operativo né una validazione del client da parte del servizio.
- [ ] Rilevare policy TLS minima e cifrari del percorso uSS-endpoint DNS e degli eventuali intermediari. Non riutilizzare il risultato TLS 1.3 del configurator per questa connessione.
- [ ] Verificare TLS fra Lambda e MySQL: il pool esaminato non configura esplicitamente `ssl`.
- [ ] Verificare validazione di IP, seriale, porta e hostname sul servizio distribuito, protezioni contro richieste abusive e rate limiting.
- [ ] Verificare log di richieste/errori e mascheramento delle credenziali, inclusi eventuali oggetti errore HTTP contenenti il token Cloudflare.

### Infrastruttura, dati e operatività

- [ ] Confermare regioni effettive di Lambda, API Gateway, DB e segreti. La configurazione dei segreti indica `eu-central-1`; non è stata verificata la distribuzione corrente.
- [ ] Verificare scope e rotazione del token Cloudflare e autorizzazioni IAM effettive ai segreti.
- [ ] Confermare TTL effettivo, modalità DNS-only, visibilità dei record LAN nella zona pubblica ed eventuale DNSSEC; trattare i dettagli Cloudflare nel documento dedicato.
- [ ] Documentare ipify come ulteriore provider per il rilevamento WAN automatico, con trattamento dell'indirizzo pubblico e termini di conservazione/localizzazione applicabili.
- [ ] Verificare selezione dell'indirizzo LAN su sistemi con più interfacce, compatibilità IPv4 e configurazioni NAT.
- [ ] Verificare aggiornamento della porta a IP invariato e applicazione delle modifiche all'intervallo: il ciclo confronta gli IP e l'intervallo è impostato all'avvio.
- [ ] Verificare retry, timeout e gestione degli aggiornamenti parziali fra Cloudflare e DB. La finalizzazione forza il solo aggiornamento LAN; il ciclo periodico gestisce la WAN.

## 1.4.1. uSee - servizi esterni

### Informazioni confermate

- [x] Cluster `OmniaWebCluster` su MongoDB Atlas, infrastruttura AWS Milano (`eu-south-1`).
- [x] MongoDB 8.0.37, tier M10 (General), replica set con tre nodi nella regione Milano, un primario e due secondari.
- [x] Configurazione del tier: 2 GB RAM, 10 GB storage con espansione automatica e cifratura abilitata.
- [x] Cloud Backup attivo: snapshot ogni 6 ore conservati 2 giorni, giornalieri 7 giorni, settimanali il sabato per 4 settimane, mensili l'ultimo giorno del mese per 12 mesi. Orario di riferimento 13:20 UTC.

### Verifiche da completare

- [ ] Identificare categorie di dati e database applicativi utilizzati dal backend uSee, retention e procedure di cancellazione.
- [ ] Verificare connessione backend-Atlas: TLS minimo, versione negoziata, validazione del certificato e configurazione del driver.
- [ ] Documentare modalità di autenticazione, utenti e ruoli database, gestione e rotazione delle credenziali.
- [ ] Verificare Network Access: IP autorizzati, eventuali private endpoint o peering e percorso di rete dal backend.
- [ ] Precisare algoritmo e gestione delle chiavi di cifratura a riposo, inclusa eventuale configurazione KMS con chiavi del cliente.
- [ ] Verificare localizzazione e cifratura degli snapshot, eventuali copie in altre regioni ed esportazioni.
- [ ] Verificare distribuzione dei nodi fra Availability Zone, configurazione di failover e relativi requisiti operativi.
- [ ] Verificare eventuale point-in-time recovery, esito dei backup, prove di ripristino e obiettivi RPO/RTO. La pianificazione degli snapshot non dimostra da sola tempi di recupero garantiti.
- [ ] Documentare accesso amministrativo Atlas, MFA/SSO, audit e conservazione dei log.

### Redis Cloud: informazioni confermate e verifiche

- [x] Database `usee-chat-prod`, Redis Stack 7.4, protocollo configurato RESP3, su AWS `us-east-1` (Virginia settentrionale, USA).
- [x] Utilizzo applicativo: informazioni live sugli utenti connessi attraverso Pub/Sub.
- [x] Alta disponibilità attiva; persistenza `None`, backup remoto disattivato, eviction `volatile-lru`.
- [x] TLS disattivato, utente predefinito disattivato e CIDR allow list disattivata. Sono impostazioni note, non controlli ancora da confermare.
- [ ] Verificare endpoint e percorso di rete effettivo dal backend a Redis, esposizione pubblica o privata ed eventuali protezioni di trasporto aggiuntive. Non attribuire TLS alla connessione Redis sulla base della sicurezza HTTPS del portale uSee.
- [ ] Valutare l'abilitazione TLS e la configurazione del client backend, con validazione del certificato, e la restrizione degli accessi di rete.
- [ ] Identificare utenti Redis attivi, ACL, permessi su comandi e canali Pub/Sub e gestione/rotazione delle credenziali. L'utente predefinito disattivato non dimostra assenza di autenticazione né l'efficacia delle altre ACL.
- [ ] Identificare dati esatti presenti nei messaggi Pub/Sub e nelle chiavi, eventuali identificativi personali, TTL, cancellazione e gestione delle disconnessioni.
- [ ] Documentare il trattamento dei dati negli Stati Uniti e le condizioni contrattuali applicabili con il provider, incluse eventuali copie, log e accessi di supporto.
- [ ] Verificare distribuzione delle repliche di alta disponibilità, comportamento in caso di failover e ricostruzione dello stato dopo perdita dei dati in memoria.
- [ ] Verificare gestione delle riconnessioni e dei messaggi persi nel Pub/Sub; non descriverlo come una coda persistente con consegna garantita.
- [ ] Documentare accessi amministrativi, MFA/SSO e conservazione dei log del servizio Redis.

## 1.4.2. uSee - deploy

- [x] OpenShift Container Platform 4.17.12 su AWS `eu-west-1`, cinque istanze `m6i.xlarge`: tre master nelle zone a/b/c e due worker nelle zone a/b.
- [x] Progetto `usee-production`: due Deployment con due repliche configurate ciascuno, frontend su servizio TCP 3000 e backend su TCP 5000; probe startup/liveness/readiness per entrambi e limiti CPU/memoria definiti. Due pod frontend osservati in esecuzione.
- [x] Connessione a `vms.usee.cloud`: TLS 1.3, X25519, AES-128-GCM, firma del server RSA-PSS con SHA-256. Certificato Subject/SAN `vms.usee.cloud`, emittente YR2, validità dal 2 novembre 2026 al 31 gennaio 2027; attestazioni CT verificate.
- [ ] Confermare l'esclusività dell'ingresso pubblico: oltre alla route per `vms.usee.cloud`, risultano route per `omniaweb.cloud` e per il dominio tecnico OpenShift. Verificare raggiungibilità e redirect prima di descrivere il primo come unico hostname esposto.
- [ ] Verificare route effettivamente distribuite, redirect HTTP-HTTPS, punto di terminazione TLS, eventuali load balancer e cifratura dei tratti interni. Il template di produzione non definisce Route; il file route separato prevede edge e Redirect per il dominio tecnico. Verificare specificamente la route di `vms.usee.cloud` prima di attribuirle tale configurazione.
- [ ] Verificare versione TLS minima e insieme dei cifrari ammessi: i parametri negoziati documentano una connessione, non l'intera policy.
- [ ] Confermare repliche effettivamente attive del backend rispetto alle due configurate, distribuzione dei pod fra worker, network policy, security group e accessi amministrativi. L'assenza di DNS IPv4 pubblico nell'elenco EC2 non dimostra da sola l'isolamento dei nodi.
- [ ] Documentare cifratura dei volumi EC2, gestione dei segreti, log, backup della piattaforma e aggiornamenti di sicurezza.
- [ ] Verificare protezione delle variabili di ambiente sensibili: il template passa credenziali DB/Redis, segreto JWT e chiave 2FA mediante parametri sostituiti in `env.value`, senza riferimenti `secretKeyRef`.
- [ ] Verificare gestione delle credenziali di pull: `imagePullSecrets` compare sotto il container anziché sotto la specifica del pod; accertare la configurazione effettiva dei ServiceAccount e dei Deployment. Nessuna modifica al template eseguita.
- [ ] Verificare rinnovo automatico del certificato del portale e allarmi di scadenza.
- [ ] Aggiornare il capitolo dopo la migrazione prevista verso Amazon EKS (Elastic Kubernetes Service); mantenere sintetica la descrizione OpenShift corrente e separare la configurazione futura da quella attiva.

## 1.4.3. uSee - relay TURN per i video WebRTC

- [x] Repliche TURN su EC2 `t3a.small` nelle regioni Irlanda (`eu-west-1`), Cape Town (`af-south-1`) e Ohio (`us-east-2`); istanza Irlanda in `eu-west-1a`.
- [x] Relay video utilizzato quando il collegamento WebRTC diretto P2P non è possibile; selezione dei pool tramite Cloudflare Proximity steering e fallback Ireland.
- [ ] Completare l'inventario delle istanze, degli endpoint e delle Availability Zone per ciascuna regione.
- [ ] Verificare software TURN, autenticazione, credenziali, porte, protocolli e cifratura dei media e del trasporto.
- [ ] Documentare security group, gestione operativa, log, conservazione e implicazioni del transito nelle regioni extra-UE.

Il dettaglio delle verifiche sul bilanciamento, sui monitor e sul percorso relay è mantenuto nel promemoria Cloudflare, sezione 2.4.

## Regole per proseguire la documentazione

- Inserire in `AWS.md` soltanto informazioni confermate, formulate in positivo.
- Tenere in questo file le verifiche aperte e le note operative.
- Omettere dal documento condivisibile modalità di raccolta delle informazioni, riferimenti agli scambi preparatori, link e nomi dei repository.
- Produrre soltanto Markdown durante la stesura; generare i PDF successivamente, su richiesta.

### Perimetro applicativo confermato

Il portale WordPress di gestione delle licenze è escluso dal perimetro uSee-uSS. Le Lambda accedono direttamente al database e il funzionamento operativo di uSee-uSS è indipendente dalla disponibilità del portale. Il database resta nel perimetro.
