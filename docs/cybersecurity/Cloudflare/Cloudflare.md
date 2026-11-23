# 2. Cloudflare

Aggiornamento: 19 novembre 2026.

## 2.1. Servizi DNS per i server uSS

### Finalità e nomi gestiti

Cloudflare gestisce i record DNS utilizzati da uSee per individuare i server uSS. Ogni installazione dispone di due nomi nella zona `omniaweb.cloud`, associati al seriale del server:

| Nome DNS | Tipo di record | Destinazione |
|---|---|---|
| `[seriale].my.omniaweb.cloud` | A | Indirizzo IPv4 pubblico (WAN) dell'installazione. |
| `[seriale].lan.omniaweb.cloud` | A | Indirizzo IPv4 locale (LAN) del server. |

I record sono gestiti in modalità **DNS-only**, con proxy disattivato. La risoluzione DNS fornisce l'indirizzo per le connessioni dirette HTTPS e WSS fra uSee e uSS.

### Creazione e aggiornamento automatici

Il servizio CoreTrust di uSS rileva gli indirizzi LAN e WAN, oppure utilizza quelli impostati manualmente, e invia la richiesta al servizio di aggiornamento ospitato su AWS Lambda. La Lambda interagisce con le API Cloudflare per cercare il record e crearlo o aggiornarlo nella zona configurata.

CoreTrust controlla gli indirizzi all'avvio e periodicamente, con intervallo automatico di 300 secondi. Gli aggiornamenti vengono richiesti quando un indirizzo differisce dall'ultimo aggiornato con successo. Il completamento dell'installazione attiva inoltre l'aggiornamento del nome LAN.

Le richieste di creazione e aggiornamento dei record A impostano un **TTL di 60 secondi**. La porta del servizio uSS è gestita nei dati applicativi associati al server.

### Accesso alle API e dati trattati

Le operazioni sulle API Cloudflare utilizzano un token di autenticazione recuperato da **AWS Secrets Manager**. Le chiamate di ricerca e aggiornamento dei record avvengono tramite **HTTPS**, con autenticazione **Bearer**.

I dati DNS gestiti comprendono i nomi host derivati dai seriali, gli indirizzi IPv4 LAN e WAN, il tipo di record e il TTL. La Lambda utilizza l'identificativo della zona per indirizzare le operazioni al dominio configurato.

## 2.2. Validazione dei domini per i certificati HTTPS uSS

### Ruolo dei servizi

Cloudflare gestisce i record DNS utilizzati per dimostrare il controllo dei domini durante l'emissione e il rinnovo dei certificati HTTPS dei server uSS. **Let's Encrypt** svolge il ruolo di Certification Authority ed emette il certificato tramite il protocollo **ACME**.

| Componente | Ruolo |
|---|---|
| Lambda di rinnovo su AWS | Generazione della chiave privata e della richiesta di firma del certificato e coordinamento del rinnovo. |
| Cloudflare DNS e API | Creazione e rimozione dei record TXT necessari alla challenge DNS-01. |
| Let's Encrypt | Verifica della challenge ed emissione del certificato. |
| AWS Secrets Manager | Gestione del token Cloudflare e dei parametri della zona e dei domini. |

### Validazione ACME DNS-01

1. La funzione di rinnovo genera una nuova chiave privata e una richiesta di firma del certificato (CSR) con il nome principale e gli eventuali nomi alternativi configurati.
2. Avvia la procedura ACME con Let's Encrypt, selezionando la challenge **DNS-01**.
3. Tramite le API Cloudflare crea i record TXT `_acme-challenge` con i valori richiesti per la validazione dei domini.
4. La Certification Authority verifica i record DNS e procede all'emissione del certificato.
5. La funzione di rinnovo gestisce la rimozione dei record temporanei al termine della challenge.

Il token per le operazioni DNS è recuperato da AWS Secrets Manager. I valori TXT pubblicati sono i dati di validazione del controllo del dominio.

### Utilizzo del certificato

Il certificato emesso e la relativa chiave privata vengono raccolti in un pacchetto conservato su Amazon S3 nella regione Francoforte (`eu-central-1`) e distribuito ai server uSS attraverso il servizio AWS dedicato.

Il server uSS utilizza il materiale TLS per le connessioni HTTPS e WSS con il client uSee. Cloudflare interviene nella gestione DNS e nella pubblicazione dei record di validazione; la firma del certificato è effettuata dalla Certification Authority e il materiale TLS è gestito dal processo di rinnovo e distribuzione su AWS.

## 2.3. WAF e filtro anti-bot per Arteco Global

### Finalità e perimetro

Il **Web Application Firewall (WAF) di Cloudflare** è posto davanti al dominio **`arteco-global.com`** e svolge una funzione di filtro anti-bot sulle richieste dirette ai servizi applicativi esposti attraverso il dominio.

Nel perimetro uSee-uSS, la protezione riguarda gli endpoint applicativi pubblicati sul dominio e serviti dalle funzioni AWS Lambda. Il servizio WAF è gestito dal fornitore.

Il servizio SSO è pubblicato sull’hostname `www.arteco-global.com`, al percorso `/en/wp-json/sso-provider/login`. La connessione HTTPS all’hostname utilizza TLS 1.3 con cifratura AES-128-GCM, scambio di chiavi X25519MLKEM768 e firma del server ECDSA con SHA-256.

### Percorso delle richieste

Le richieste raggiungono Cloudflare, vengono sottoposte ai controlli WAF e anti-bot e, quando consentite, vengono inoltrate al servizio di destinazione. Il filtro interviene quindi prima dell'elaborazione delle richieste da parte delle applicazioni.

| Servizio protetto | Ruolo di Cloudflare |
|---|---|
| Endpoint Lambda esposti tramite Arteco Global | Filtro delle richieste in ingresso prima dell'inoltro agli endpoint applicativi. |

Il WAF costituisce un livello di protezione dell'accesso pubblico, complementare ai controlli applicativi di autenticazione e autorizzazione.

## 2.4. Bilanciamento geografico dei server TURN per WebRTC

### Finalità e funzionamento

Cloudflare Load Balancing gestisce la selezione geografica dei pool di server TURN utilizzati per i video WebRTC. Il relay TURN consente la comunicazione quando le condizioni di rete, come NAT restrittivi o firewall, impediscono il collegamento diretto peer-to-peer tra client uSee e server uSS.

Quando viene utilizzato TURN, il flusso video transita attraverso il server relay selezionato. Cloudflare gestisce la selezione del pool, mentre il servizio TURN è eseguito su infrastruttura Amazon EC2.

### Pool e localizzazione

I pool sono costituiti da repliche del servizio TURN su istanze Amazon EC2 di tipo `t3a.small`, distribuite in tre regioni:

| Pool | Regione AWS | Paese |
|---|---|---|
| Ireland | Europe (Ireland), `eu-west-1` | Irlanda |
| Capetown | Africa (Cape Town), `af-south-1` | Sudafrica |
| Ohio | US East (Ohio), `us-east-2` | Stati Uniti |

L'istanza TURN in Irlanda è collocata nell'Availability Zone `eu-west-1a`.

### Selezione geografica e monitoraggio

Il bilanciatore utilizza la policy **Proximity steering**, basata sulla prossimità geografica, per selezionare il pool di destinazione.

È configurato un monitor di tipo **TCP**, denominato `Monitor turn TCP 22`, per il controllo degli endpoint. Il pool **Ireland** è impostato come fallback da utilizzare quando tutti i pool risultano non disponibili secondo i controlli di salute.

### Percorso dei dati

La comunicazione WebRTC utilizza il percorso diretto quando disponibile e il relay TURN quando necessario. Nel secondo caso, il traffico video transita nella regione del server TURN selezionato: Irlanda, Sudafrica o Stati Uniti.

La distribuzione su tre regioni mette a disposizione punti di relay geograficamente distinti per le installazioni che richiedono questo tipo di collegamento.
