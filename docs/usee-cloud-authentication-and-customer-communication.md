# Autenticazione cloud uSee e comunicazione con l'infrastruttura del cliente

## Sintesi

uSee separa l'autenticazione cloud dalla comunicazione operativa con uSS presso il cliente.

L'utente si autentica una sola volta su uSee tramite l'Identity Provider Arteco Global. Dopo l'autorizzazione, uSee presenta esclusivamente i siti/uSS assegnati all'utente. Quando l'utente seleziona un uSS, il browser instaura una sessione **diretta, cifrata e autenticata** con il nodo uSS: i flussi API, WebSocket e video non transitano attraverso Cloudflare, OpenShift o i servizi cloud uSee.

## Componenti coinvolti

| Componente | Ruolo |
|---|---|
| Browser dell'operatore | Esegue l'interfaccia uSee e apre le connessioni dirette verso uSS. |
| Cloudflare WAF | Protegge l'esposizione pubblica dei servizi Arteco Global, incluso l'endpoint SSO, contro minacce web e DDoS. |
| uSee Client e Backend (OpenShift) | Espongono l'interfaccia web, gestiscono la sessione uSee, l'elenco dei siti e l'integrazione con l'SSO. |
| Arteco Global SSO / Identity Provider | Verifica le credenziali e restituisce le autorizzazioni/siti associati all'utente. |
| uSS Port Broker | Unico punto di ingresso applicativo sul nodo uSS; pubblica HTTPS/WSS sulla porta 443 o sulla porta configurata. |
| Servizi uSS | Gestiscono API, WebSocket, video, eventi, recording e integrazione con le periferiche presenti presso il cliente. |

## Processo di autenticazione cloud uSee

1. **Accesso al portale.** L'operatore apre `https://vms.usee.cloud`. La connessione usa HTTPS su TCP 443 con TLS 1.2 o superiore ed è diretta verso la Route/Ingress OpenShift di uSee.
2. **Inoltro verso uSee.** Il client web uSee riceve l'interfaccia dalla Route/Ingress OpenShift e inoltra i percorsi applicativi `/api` e `/socket` al backend uSee nel namespace privato OpenShift.
3. **Invio delle credenziali.** L'operatore inserisce le credenziali nella pagina di login uSee. Il browser le invia al backend uSee attraverso il canale HTTPS protetto.
4. **Verifica SSO.** Il backend uSee contatta l'endpoint SSO Arteco Global configurato (`https://www.arteco-global.com/en/wp-json/sso-provider`) tramite HTTPS/TCP 443. La richiesta attraversa il WAF Cloudflare, posto davanti ai servizi Arteco Global; l'Identity Provider verifica l'identità, l'abilitazione al servizio uSee e i siti assegnati all'utente.
5. **Creazione della sessione uSee.** Se l'autenticazione ha esito positivo, uSee aggiorna il profilo applicativo dell'utente e restituisce al browser un token di sessione firmato, l'indicazione dell'eventuale 2FA e l'elenco dei siti autorizzati.
6. **Secondo fattore, se abilitato.** Quando il 2FA è configurato per l'utente, il client richiede un codice TOTP oppure un recovery code. Il backend verifica il codice prima che il client completi il login nell'interfaccia uSee.
7. **Sincronizzazione dei siti autorizzati.** uSee associa l'utente solo agli uSS restituiti dall'SSO. Per ciascun sito conserva i parametri di connessione configurati (FQDN/IP, porta, tipo di server e servizio di autenticazione uSS selezionato). Nessun uSS non assegnato è presentato all'operatore.

## Instaurazione della comunicazione verso uSS presso il cliente

### 1. Scelta dell'endpoint

Quando un operatore apre un sito, uSee seleziona l'endpoint del relativo uSS:

- in rete locale: `[uSS-SerialNumber].lan.omniaweb.cloud`;
- da rete remota: `[uSS-SerialNumber].my.omniaweb.cloud`;
- porta: `443` oppure il valore configurato sul Port Broker.

La scelta LAN/WAN dipende dal contesto di rete della postazione operatore. In entrambi i casi il browser comunica direttamente con uSS, senza proxy applicativo nel cloud uSee.

### 2. Autenticazione sul nodo uSS

1. Il browser interroga le capacità del nodo uSS tramite HTTPS.
2. Per un uSS/Hypernode effettua il login sull'API uSS (`/api/v2/login?outfmt=json`) tramite HTTPS, usando le credenziali e il servizio di autenticazione associati al sito autorizzato.
3. uSS verifica le credenziali e il servizio di autenticazione selezionato e, se il login è valido, restituisce un `access_token` di uSS.
4. Il token è associato alla sessione del nodo ed è distinto dal token di sessione uSee cloud.

### 3. Sessione operativa diretta

Dopo il login sul nodo, il browser apre un WebSocket sicuro verso:

```text
wss://[uSS-SerialNumber].[lan|my].omniaweb.cloud:443/~ws~/
```

Il token uSS viene presentato all'apertura della sessione WebSocket. Le successive chiamate API verso uSS usano HTTPS con `Authorization: Bearer <access_token>`; il canale WebSocket gestisce comandi, notifiche e frame video. Il client mantiene la sessione con messaggi di ping e può ristabilirla quando necessario.

## Percorso del traffico presso il cliente

```text
Browser operatore
        │  HTTPS / WSS, TLS 1.2+, access token
        ▼
uSS Port Broker :443
        │  rete Docker privata
        ▼
uSS Web Server / Gateway / servizi funzionali
        │
        ├─ RabbitMQ e MongoDB uSS (solo rete interna al nodo)
        └─ Telecamere e periferiche IP nella rete del cliente
```

Il Port Broker è l'unico componente uSS previsto per l'esposizione applicativa all'operatore. RabbitMQ (5672), MongoDB (27017), il mapping tecnico del Web Server (8181) e gli altri servizi interni restano confinati alla rete del nodo e non sono accessibili direttamente dalla postazione operatore o da Internet.

## Separazione dei domini di sicurezza

| Dominio | Responsabilità | Traffico dell'operatore |
|---|---|---|
| Cloud uSee (OpenShift) | Interfaccia uSee, backend e gestione della sessione applicativa | HTTPS verso `vms.usee.cloud` |
| Arteco Global | WAF Cloudflare, SSO, autorizzazione e gestione dei siti | HTTPS tra uSee e `arteco-global.com` |
| Infrastruttura del cliente | Sessione uSS, API, WebSocket, video, recording e periferiche | HTTPS/WSS diretto verso il Port Broker uSS |

Cloudflare protegge l'esposizione dei servizi Arteco Global; non è davanti a uSee e non è nel percorso di media/controllo tra la postazione e uSS. Il video e i comandi operativi restano quindi nel percorso diretto **postazione operatore ↔ uSS**, protetto da TLS e dal token di accesso uSS.

## Presupposti e controlli richiesti

- Il FQDN uSS deve risolvere correttamente sia in LAN sia da WAN e presentare un certificato TLS valido.
- Il firewall del cliente deve consentire dalla postazione operatore verso il Port Broker uSS esclusivamente TCP 443, salvo una porta configurata in modo diverso.
- Gli endpoint SSO, DNS, certificati e licensing Arteco Global devono essere raggiungibili in uscita dal cloud uSee o dal nodo uSS, secondo la matrice di rete.
- Le credenziali tecniche di connessione al nodo uSS devono essere gestite e protette secondo le policy applicabili del cliente; la loro protezione a riposo e il ciclo di rotazione devono essere verificati nella configurazione di produzione.
