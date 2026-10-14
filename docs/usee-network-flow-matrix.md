# Matrice dei flussi di rete — uSee con uSS

## Ambito e convenzioni

Questa matrice si applica alla soluzione composta da uSee, servizi cloud Arteco Global/AWS e un deployment uSS presso il cliente. 

- Tutti i flussi indicati sono bidirezionali a livello TCP: la direzione in tabella identifica chi apre la connessione.
- `Privato` indica che il flusso deve rimanere in una rete/namespace privato; non richiede una regola firewall da Internet.
- Per le destinazioni HTTPS il requisito minimo è TLS 1.2 o superiore. I certificati devono essere validi per il FQDN utilizzato.
- Cloudflare configurato in modalità end-to-end (`Full (strict)` o equivalente).

## Flussi obbligatori di esercizio

| ID | Sorgente | Destinazione | IP / FQDN da censire | Protocollo | Porta destinazione | Finalità | Esposizione / requisito di sicurezza |
|---|---|---|---|---|---:|---|---|
| F-01 | Postazione operatore | Route/Ingress OpenShift uSee | `https://vms.usee.cloud` | HTTPS | TCP 443 | Caricamento dell'interfaccia uSee, chiamate API e WebSocket applicativi | Pubblico; TLS 1.2+ |
| F-02 | OpenShift Route/Ingress | Servizio uSee Client | `omnia-web-client.usee-production.svc.cluster.local` | HTTP | TCP 3000 | Pubblicazione della SPA uSee | Privato, interno al cluster; TLS terminato all'edge route |
| F-03 | uSee Client (Nginx) | uSee Backend | `omnia-backend.usee-production.svc.cluster.local` | HTTP e WebSocket | TCP 5000 | Proxy dei percorsi `/api`, `/socket` e asset dinamici | Privato, interno al cluster; il traffico pubblico rimane HTTPS/WSS fino all'edge |
| F-04 | uSee Backend | Cloudflare WAF / SSO Identity Provider Arteco Global | `https://www.arteco-global.com/en/wp-json/sso-provider` | HTTPS | TCP 443 | Autenticazione centralizzata, verifica credenziali e autorizzazioni | Uscente dal cloud uSee; TLS 1.2+; Cloudflare WAF è posto davanti ai servizi Arteco Global |
| F-05 | uSee Backend | Database cluster AWS | `omniawebcluster.16ivv.mongodb.net` | MongoDB su TCP, con TLS se configurato | TCP 27017 | Persistenza di utenti, configurazioni, layout, eventi e preferenze | Privato AWS/VPC o allow-list stretta; autenticazione database obbligatoria |
| F-06 | uSee Backend | Redis AWS | `redis-19423.c111.us-east-1-mz.ec2.redns.redis-cloud.com` | Redis TCP (`redis`/`rediss` secondo configurazione) | TCP 6379 | Sessioni, presenza utenti, chat e messaggistica PUB/SUB | Privato AWS/VPC o allow-list stretta; TLS se il servizio è raggiungibile oltre la rete privata |
| F-07 | Postazione operatore | uSS Port Broker | `[uSS-SerialNumber].[lan/my].omniaweb.cloud` | HTTPS e WSS | TCP 443 (o valore configurato) | Controllo VMS, API uSS, WebSocket e trasporto dei frame video | Esporre unicamente il Port Broker; TLS 1.2+, autenticazione tramite access token |
| F-08 | Port Broker uSS | Web Server uSS | rete Docker uSS | HTTP / WebSocket | TCP 80 | Terminazione/inoltro del traffico esposto dal Port Broker ai servizi uSS | Privato, interno al nodo Docker |
| F-09 | Web Server / Gateway / servizi uSS | RabbitMQ uSS | `messagebroker` o loopback del nodo | AMQP | TCP 5672 | Comandi, eventi e coordinamento tra microservizi uSS | Privato, interno al nodo Docker; credenziali AMQP obbligatorie |
| F-10 | Gateway, watchdog, auth, recording, snapshot, event, coretrust, camera e metadata uSS | MongoDB uSS | `host.docker.internal` / loopback del nodo | MongoDB TCP | TCP 27017 | Persistenza per i microservizi uSS | Privato, interno al nodo; autenticazione MongoDB obbligatoria |
| F-11 | Camera/live streamer e metadata uSS | Web Server uSS | loopback del nodo | WebSocket | TCP 8181 (mapping interno verso 80) | Gateway interno e segnalazione dei servizi video/metadata | Privato, interno al nodo; non deve essere esposto a Internet |
| F-12 | Coretrust e Gateway uSS | Servizi Arteco Global: certificati, DNS e licensing | `https://xs9punpjw2.execute-api.eu-central-1.amazonaws.com`, `https://zqhck0x3yi.execute-api.eu-central-1.amazonaws.com`, `https://www.arteco-global.com` | HTTPS | TCP 443 | Registrazione/gestione certificati, DNS e licenze | Uscente dal sito cliente; TLS 1.2+ e DNS risolvibile |

## Flussi condizionali, da completare per ciascuna installazione

| ID | Sorgente | Destinazione | IP / FQDN da censire | Protocollo / porta | Finalità | Criterio di attivazione |
|---|---|---|---|---|---|---|
| C-01 | Servizi camera/live streamer uSS | Telecamere e periferiche IP del cliente | `<camera-ip o camera-fqdn>` | Dipende dal profilo della periferica: tipicamente RTSP TCP 554 e ONVIF HTTP/HTTPS TCP 80/443 | Acquisizione video, discovery, configurazione e controllo periferiche | Una riga per famiglia/modello di periferica; il profilo di integrazione determina le porte effettive |
| C-02 | Postazione operatore | uSS Port Broker | `[uSS-SerialNumber].[lan/my].omniaweb.cloud` | HTTPS/WSS TCP (o valore configurato)  | Riproduzione live e registrata tramite frame su WSS | Richiesto quando l'operatore visualizza un canale; il video non transita da Cloudflare né dai servizi cloud uSee |

## Porte che non devono essere esposte agli operatori o a Internet

| Porta | Componente | Regola richiesta |
|---:|---|---|
| TCP 27017 | MongoDB uSS e MongoDB uSee | Nessuna esposizione pubblica. Consentire solo dai workload autorizzati nella stessa rete privata. |
| TCP 5672 | RabbitMQ uSS | Nessuna esposizione pubblica. Consentire solo dai microservizi uSS autorizzati. |
| TCP 8181 | Web Server uSS, mapping tecnico del nodo | Nessuna esposizione pubblica; utilizzare il Port Broker su 443. |
| TCP 3000 e TCP 5000 | Servizi uSee nel cluster | Nessuna esposizione Internet diretta; pubblicare soltanto tramite Route/Ingress protetta. |
| TCP 6379 | Redis AWS | Nessuna esposizione Internet diretta; usare solo rete privata/allow-list. |
