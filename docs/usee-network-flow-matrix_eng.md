# Network Flow Matrix — uSee with uSS

## Scope and conventions

This matrix applies to the solution composed of uSee, Arteco Global/AWS cloud services, and an on-premises uSS deployment at the customer site.

- All listed flows are bidirectional at the TCP level; the direction in the table identifies the connection initiator.
- `Private` indicates that the flow must remain within a private network/namespace; it does not require an Internet firewall rule.
- For HTTPS destinations, the minimum requirement is TLS 1.2 or later. Certificates must be valid for the FQDN in use.
- Cloudflare is configured in end-to-end mode (`Full (strict)` or equivalent).

## Mandatory operational flows

| ID | Source | Destination | IP / FQDN to be registered | Protocol | Destination port | Communication purpose | Exposure / security requirement |
|---|---|---|---|---|---:|---|---|
| F-01 | Operator workstation | Cloudflare WAF | `https://vms.usee.cloud` | HTTPS | TCP 443 | Loading the uSee interface, API calls and application WebSockets | Public; TLS 1.2+, Cloudflare WAF and DDoS protection |
| F-02 | Cloudflare WAF | uSee OpenShift Route/Ingress | `omnia-web-client-usee-production.apps.cluprod03.ocparteco.com` | HTTPS | TCP 443 | Secure forwarding of uSee traffic to the origin | Expose the origin only to Cloudflare IPs where possible; end-to-end TLS |
| F-03 | OpenShift Route/Ingress | uSee Client service | `omnia-web-client.usee-production.svc.cluster.local` | HTTP | TCP 3000 | Publishing the uSee SPA | Private, internal to the cluster; TLS terminates at the edge route |
| F-04 | uSee Client (Nginx) | uSee Backend | `omnia-backend.usee-production.svc.cluster.local` | HTTP and WebSocket | TCP 5000 | Proxying `/api`, `/socket` and dynamic asset paths | Private, internal to the cluster; public traffic remains HTTPS/WSS up to the edge |
| F-05 | uSee Backend | Arteco Global SSO / Identity Provider | `https://www.arteco-global.com/en/wp-json/sso-provider` | HTTPS | TCP 443 | Centralized authentication, credential verification and authorization | Outbound from the uSee cloud; TLS 1.2+ |
| F-06 | uSee Backend | AWS database cluster | `omniawebcluster.16ivv.mongodb.net` | MongoDB over TCP, with TLS if configured | TCP 27017 | Persistence of users, configurations, layouts, events and preferences | Private AWS/VPC or strict allow-list; database authentication is mandatory |
| F-07 | uSee Backend | AWS Redis | `redis-19423.c111.us-east-1-mz.ec2.redns.redis-cloud.com` | Redis TCP (`redis`/`rediss` depending on configuration) | TCP 6379 | Sessions, user presence, chat and PUB/SUB messaging | Private AWS/VPC or strict allow-list; TLS if the service is reachable beyond the private network |
| F-08 | Operator workstation | uSS Port Broker | `[uSS-SerialNumber].[lan/my].omniaweb.cloud` | HTTPS and WSS | TCP 443 (or configured value) | VMS control, uSS APIs, WebSocket and video-frame transport | Expose only the Port Broker; TLS 1.2+ and access-token authentication |
| F-09 | uSS Port Broker | uSS Web Server | uSS Docker network | HTTP / WebSocket | TCP 80 | Termination/routing of Port Broker-exposed traffic to uSS services | Private, internal to the Docker node |
| F-10 | uSS Web Server / Gateway / services | uSS RabbitMQ | `messagebroker` or node loopback | AMQP | TCP 5672 | Commands, events and coordination between uSS microservices | Private, internal to the Docker node; AMQP credentials are mandatory |
| F-11 | uSS Gateway, watchdog, auth, recording, snapshot, event, coretrust, camera and metadata | uSS MongoDB | `host.docker.internal` / node loopback | MongoDB TCP | TCP 27017 | Persistence for uSS microservices | Private, internal to the node; MongoDB authentication is mandatory |
| F-12 | uSS camera/live streamer and metadata | uSS Web Server | Node loopback | WebSocket | TCP 8181 (internal mapping to 80) | Internal gateway and video/metadata service signalling | Private, internal to the node; must not be exposed to the Internet |
| F-13 | uSS Coretrust and Gateway | Arteco Global services: certificates, DNS and licensing | `https://xs9punpjw2.execute-api.eu-central-1.amazonaws.com`, `https://zqhck0x3yi.execute-api.eu-central-1.amazonaws.com`, `https://www.arteco-global.com` | HTTPS | TCP 443 | Registration/management of certificates, DNS and licences | Outbound from the customer site; TLS 1.2+ and resolvable DNS |

## Conditional flows, to be completed for each installation

| ID | Source | Destination | IP / FQDN to be registered | Protocol / port | Communication purpose | Activation criterion |
|---|---|---|---|---|---|---|
| C-01 | uSS camera/live streamer services | Customer IP cameras and peripherals | `<camera-ip or camera-fqdn>` | Depends on the peripheral profile: typically RTSP TCP 554 and ONVIF HTTP/HTTPS TCP 80/443 | Video acquisition, discovery, configuration and peripheral control | One row per peripheral family/model; the integration profile determines the actual ports |
| C-02 | Operator workstation | uSS Port Broker | `[uSS-SerialNumber].[lan/my].omniaweb.cloud` | HTTPS/WSS TCP (or configured value) | Live and recorded playback through frames over WSS | Required when an operator displays a channel; video does not transit through Cloudflare or uSee cloud services |

## Ports that must not be exposed to operators or the Internet

| Port | Component | Required rule |
|---:|---|---|
| TCP 27017 | uSS MongoDB and uSee MongoDB | No public exposure. Allow only authorized workloads within the same private network. |
| TCP 5672 | uSS RabbitMQ | No public exposure. Allow only authorized uSS microservices. |
| TCP 8181 | uSS Web Server, node technical mapping | No public exposure; use Port Broker on 443. |
| TCP 3000 and TCP 5000 | uSee services in the cluster | No direct Internet exposure; publish only through the protected Route/Ingress. |
| TCP 6379 | AWS Redis | No direct Internet exposure; use private network/allow-list only. |
