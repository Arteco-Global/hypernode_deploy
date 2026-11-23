# Cloudflare - Promemoria interno delle verifiche

Aggiornamento: 19 novembre 2026.

Documento di lavoro interno, separato dal capitolo destinato alla condivisione.

## Priorità per la risposta A03

- [ ] Identificare servizi commerciali e piano effettivi: DNS, WAF, specifica funzionalità anti-bot e Load Balancing.
- [ ] Documentare la terminazione TLS per ciascun hostname protetto, distinguendo client-Cloudflare e Cloudflare-origine; acquisire modalità SSL/TLS, certificati e policy minime.
- [ ] Separare i dati elaborati da DNS, WAF/anti-bot e Load Balancing: record, IP, dati HTTP ispezionati, cookie/token, log ed eventuali dati di geolocalizzazione.
- [ ] Verificare localizzazione di elaborazione, terminazione TLS, log e metadati e acquisire le eventuali garanzie contrattuali UE realmente attive, con esatto perimetro di servizi/hostname/dati coperti.
- [ ] Distinguere localizzazione dei relay AWS dalla localizzazione del trattamento Cloudflare; non dedurre una garanzia UE dalla prossimità geografica o da un'origine AWS europea.

## 2.1. Servizi DNS

- [ ] Confermare nella configurazione attiva zona, delega dei nameserver, record LAN/WAN, modalità DNS-only e TTL effettivo. L'automazione imposta record A, TTL 60 e `proxied: false`.
- [ ] Verificare DNSSEC e presenza dei record DS presso il registrar.
- [ ] Verificare visibilità pubblica dei record LAN e valutare la pubblicazione di seriali e indirizzi privati rispetto ai requisiti del servizio.
- [ ] Verificare inventario dei record e modalità di rimozione alla dismissione o riassegnazione di un server.
- [ ] Precisare controlli di validazione degli IP e dei nomi, gestione degli errori API e aggiornamenti concorrenti.

## 2.2. Validazione dei certificati

- [ ] Confermare domini, SAN ed eventuali wildcard coperti dal certificato attivo.
- [ ] Verificare ambiente ACME di produzione e corrispondenza con il certificato distribuito: la configurazione di rinnovo esaminata include il valore `staging`.
- [ ] Verificare gestione delle challenge concorrenti, attesa della propagazione DNS, retry e rimozione dei record TXT anche dopo errori.
- [ ] Verificare eventuali record CAA e loro coerenza con la Certification Authority utilizzata.
- [ ] Confermare pianificazione del rinnovo, allarmi di fallimento e monitoraggio della scadenza del certificato.

## Token, accessi e tracciamento

- [ ] Identificare i token usati dal servizio DNS e dal servizio di rinnovo, verificando se siano distinti o condivisi.
- [ ] Verificare permessi effettivi, limitazione alle zone necessarie, scadenza, rotazione ed eventuali restrizioni IP dei token.
- [ ] Verificare ruoli amministrativi Cloudflare, MFA/SSO e accessi di servizio.
- [ ] Documentare audit log, conservazione, accesso e allarmi sulle modifiche DNS.
- [ ] Verificare che gli errori API e i log applicativi non registrino token o altri segreti.
- [ ] Confermare versioni TLS minime e validazione dei certificati nelle chiamate alle API Cloudflare; non attribuire a tali chiamate i parametri TLS osservati sul configurator uSS.

## Localizzazione e trattamento dei dati

- [ ] Documentare localizzazione e trattamento dei dati DNS e dei log da parte di Cloudflare, inclusi conservazione, copie e accessi di supporto. Le regioni delle Lambda AWS non determinano la localizzazione dei dati Cloudflare.
- [ ] Precisare le condizioni contrattuali del servizio e i soggetti coinvolti nel trattamento dei dati.

## 2.3. WAF e filtro anti-bot per Arteco Global

- [x] Confermata la presenza del WAF Cloudflare davanti ad `arteco-global.com`, con filtro anti-bot per gli endpoint Lambda pubblicati sul dominio nel perimetro uSee-uSS.
- [ ] Elencare hostname e percorsi effettivamente protetti, incluse le corrispondenti API e origini AWS; non estendere automaticamente questa copertura a ogni funzione Lambda.
- [ ] Identificare le funzionalità anti-bot effettivamente abilitate, il piano Cloudflare, le regole WAF gestite e personalizzate e le azioni applicate (blocco, challenge, log o esclusione).
- [ ] Verificare eventuali regole di rate limiting, soglie ed eccezioni per i client applicativi legittimi.
- [ ] Verificare come viene impedito l'aggiramento del WAF tramite accesso diretto alle origini o agli endpoint API Gateway/Lambda.
- [ ] Documentare TLS sui tratti client-Cloudflare e Cloudflare-origine, modalità SSL/TLS, validazione dei certificati e versioni minime ammesse.
- [ ] Documentare campi delle richieste trattati dal filtro, mascheramento delle credenziali, localizzazione e conservazione dei log di sicurezza, accessi e allarmi.
- [ ] Mantenere distinta questa protezione dalla gestione DNS-only dei nomi uSS e dal deploy uSee su `vms.usee.cloud`.

## 2.4. Bilanciamento geografico dei server TURN

- [x] Pool Ireland, Capetown e Ohio, con repliche TURN su AWS EC2 `t3a.small`; istanza Irlanda in `eu-west-1a`.
- [x] Policy Proximity steering e pool di fallback Ireland; monitor TCP denominato `Monitor turn TCP 22`.
- [ ] Identificare hostname del load balancer, modalità DNS-only/proxy, TTL, coordinate dei pool e criterio effettivo di geolocalizzazione. Non affermare che il video attraversi la rete Cloudflare senza verificare il percorso dati.
- [ ] Confermare numero e identificativi degli endpoint nei pool e Availability Zone di Cape Town e Ohio.
- [ ] Verificare porta, timeout, intervallo e soglie del monitor. Il nome suggerisce TCP 22, ma la porta non è stata letta dalla configurazione. Un controllo TCP/SSH non dimostra il funzionamento delle allocazioni TURN o del relay video.
- [ ] Verificare comportamento di failover, caching DNS e recupero delle sessioni WebRTC già avviate. Il fallback non garantisce disponibilità quando tutti i pool risultano guasti.
- [ ] Documentare software/versione TURN, protocolli e porte abilitati (UDP, TCP, TURN su TLS), certificati e policy TLS.
- [ ] Verificare autenticazione TURN, durata e generazione delle credenziali, rotazione dei segreti, limiti di banda/allocazioni e protezioni contro abuso del relay.
- [ ] Verificare cifratura dei media WebRTC (DTLS-SRTP) lungo il percorso relay e separarla dall'eventuale TLS del trasporto TURN; non trasferire a questo percorso le conclusioni TLS del configurator o del portale.
- [ ] Documentare security group, patching, accesso amministrativo e cifratura dei volumi delle istanze TURN.
- [ ] Verificare contenuto, localizzazione e conservazione dei log TURN e Cloudflare; distinguere transito del video da registrazione o persistenza.
- [ ] Precisare gestione del transito dei dati in Sudafrica e negli Stati Uniti e disponibilità di eventuali vincoli regionali.
- [ ] Allineare la documentazione di rete AWS/uSee con l'eccezione WebRTC: i flussi diretti e quelli tramite relay TURN devono essere descritti separatamente.

## Dipendenze dalle verifiche AWS e uSS

I dettagli operativi dei punti seguenti sono mantenuti nel promemoria AWS, sezioni 1.2 e 1.3:

- [ ] Allineare il servizio DNS distribuito con CoreTrust: differiscono i parametri di autenticazione e le rotte nelle implementazioni esaminate.
- [ ] Verificare e correggere la validazione del certificato dell'endpoint DNS nel client CoreTrust, che imposta `rejectUnauthorized: false`.
- [ ] Completare i controlli di autorizzazione alle richieste DNS e di protezione delle credenziali.
- [ ] Completare le verifiche sulla protezione della chiave privata, sull'accesso a S3 e sulla distribuzione del pacchetto TLS ai server.

## Regole per proseguire la documentazione

- Inserire nel documento condivisibile soltanto informazioni confermate, senza riferimenti alla raccolta delle informazioni, agli scambi preparatori o ai repository.
- Conservare le verifiche aperte e le note operative in questo file.
- Aggiungere altri servizi Cloudflare soltanto quando affrontati e verificati; mantenere distinta la gestione DNS dall'eventuale utilizzo di proxy, WAF o CDN.
- Produrre soltanto Markdown durante la stesura; generare i PDF successivamente, su richiesta.

### Verifiche da richiedere al fornitore del WAF

- Il WAF è gestito su un account Cloudflare del fornitore, al quale non abbiamo accesso. Il portale WordPress è escluso dal perimetro applicativo; restano gli endpoint delle Lambda.
- [x] Connessione pubblica a `www.arteco-global.com`: TLS 1.3, X25519MLKEM768, AES-128-GCM, firma ECDSA con SHA-256, certificato emesso da WE1. Confermato che il servizio SSO utilizza lo stesso hostname, con percorso `/en/wp-json/sso-provider/login`. I parametri descrivono la connessione negoziata, non la policy minima né il tratto Cloudflare-origine.
- [ ] Completare l’elenco degli altri hostname e percorsi API protetti oltre all’endpoint SSO confermato; acquisire stato proxy, modalità SSL/TLS effettiva ed eventuali regole specifiche, TLS minimo e protezione Cloudflare-origine.
- [ ] Acquisire dal fornitore configurazione Regional Services per hostname, Customer Metadata Boundary a livello account, destinazioni e conservazione dei log, nonché garanzie contrattuali UE e relativo perimetro. Le impostazioni del nostro account DNS/load balancing non attestano quelle del fornitore.

- [ ] Confermare con il fornitore l’instradamento del percorso `/en/wp-json/sso-provider/login` verso l’ingresso AWS e le regole WAF applicate. Il prefisso `wp-json` non dimostra una dipendenza operativa da WordPress; resta confermata l’indipendenza indicata per il servizio e l’accesso diretto Lambda-DB.
