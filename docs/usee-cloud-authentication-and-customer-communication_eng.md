# uSee Cloud Authentication and Communication with the Customer Infrastructure

## Summary

uSee separates cloud authentication from operational communication with uSS deployed at the customer site.

The user authenticates once to uSee through the Arteco Global Identity Provider. After authorization, uSee displays only the sites/uSS servers assigned to that user. When the user selects a uSS server, the browser establishes a **direct, encrypted, and authenticated** session with that uSS node: API, WebSocket, and video flows do not pass through Cloudflare, OpenShift, or the uSee cloud services.

## Involved components

| Component | Role |
|---|---|
| Operator browser | Runs the uSee interface and opens direct connections to uSS. |
| Cloudflare WAF | Protects the public exposure of Arteco Global services, including the SSO endpoint, against web threats and DDoS attacks. |
| uSee Client and Backend (OpenShift) | Provide the web interface, manage the uSee session and site list, and integrate with SSO. |
| Arteco Global SSO / Identity Provider | Verifies credentials and returns the permissions/sites associated with the user. |
| uSS Port Broker | The single application entry point on the uSS node; exposes HTTPS/WSS on port 443 or on the configured port. |
| uSS services | Manage APIs, WebSocket connections, video, events, recording, and integration with devices deployed at the customer site. |

## uSee cloud authentication process

1. **Portal access.** The operator opens `https://vms.usee.cloud`. The connection uses HTTPS over TCP 443 with TLS 1.2 or later and is direct to the uSee OpenShift Route/Ingress.
2. **Routing to uSee.** The uSee web client receives the interface from the OpenShift Route/Ingress and forwards the `/api` and `/socket` application paths to the uSee backend in the private OpenShift namespace.
3. **Credential submission.** The operator enters credentials on the uSee login page. The browser sends them to the uSee backend through the protected HTTPS channel.
4. **SSO verification.** The uSee backend calls the configured Arteco Global SSO endpoint (`https://www.arteco-global.com/en/wp-json/sso-provider`) over HTTPS/TCP 443. The request passes through the Cloudflare WAF, which is placed in front of Arteco Global services; the Identity Provider verifies the identity, uSee service entitlement, and sites assigned to the user.
5. **uSee session creation.** If authentication succeeds, uSee updates the user's application profile and returns a signed session token to the browser, the indication of any required 2FA, and the list of authorized sites.
6. **Second factor, where enabled.** When 2FA is configured for the user, the client requests a TOTP or recovery code. The backend validates it before the client completes login to the uSee interface.
7. **Authorized-site synchronization.** uSee associates the user only with the uSS servers returned by SSO. For each site, it stores the configured connection parameters (FQDN/IP, port, server type, and selected uSS authentication service). No unassigned uSS server is presented to the operator.

## Establishing communication with uSS at the customer site

### 1. Endpoint selection

When an operator opens a site, uSee selects the endpoint of the relevant uSS server:

- on the local network: `[uSS-SerialNumber].lan.omniaweb.cloud`;
- from a remote network: `[uSS-SerialNumber].my.omniaweb.cloud`;
- port: `443` or the value configured on the Port Broker.

LAN/WAN selection depends on the network context of the operator workstation. In both cases, the browser communicates directly with uSS, without an application proxy in the uSee cloud.

### 2. Authentication on the uSS node

1. The browser queries the uSS node capabilities over HTTPS.
2. For a uSS/Hypernode, it logs in to the uSS API (`/api/v2/login?outfmt=json`) over HTTPS, using the credentials and authentication service associated with the authorized site.
3. uSS verifies the credentials and the selected authentication service and, if login is valid, returns a uSS `access_token`.
4. The token is associated with the node session and is distinct from the uSee cloud session token.

### 3. Direct operational session

After logging in to the node, the browser opens a secure WebSocket connection to:

```text
wss://[uSS-SerialNumber].[lan|my].omniaweb.cloud:443/~ws~/
```

The uSS token is supplied when opening the WebSocket session. Subsequent API calls to uSS use HTTPS with `Authorization: Bearer <access_token>`; the WebSocket channel handles commands, notifications, and video frames. The client maintains the session using ping messages and can re-establish it when required.

## Traffic path at the customer site

```text
Operator browser
        │  HTTPS / WSS, TLS 1.2+, access token
        ▼
uSS Port Broker :443
        │  Private Docker network
        ▼
uSS Web Server / Gateway / functional services
        │
        ├─ uSS RabbitMQ and MongoDB (node-internal network only)
        └─ IP cameras and devices on the customer network
```

The Port Broker is the only uSS component intended for application exposure to the operator. RabbitMQ (5672), MongoDB (27017), the Web Server technical mapping (8181), and the other internal services remain confined to the node network and are not directly reachable from the operator workstation or the Internet.

## Security-domain separation

| Domain | Responsibility | Operator traffic |
|---|---|---|
| uSee cloud (OpenShift) | uSee interface, backend, and application session management | HTTPS to `vms.usee.cloud` |
| Arteco Global | Cloudflare WAF, SSO, authorization, and site management | HTTPS between uSee and `arteco-global.com` |
| Customer infrastructure | uSS session, APIs, WebSocket, video, recording, and devices | Direct HTTPS/WSS to the uSS Port Broker |

Cloudflare protects the exposure of Arteco Global services; it is not in front of uSee and is not in the media/control path between the workstation and uSS. Video and operational commands therefore remain on the direct **operator workstation ↔ uSS** path, protected by TLS and the uSS access token.

## Required assumptions and controls

- The uSS FQDN must resolve correctly both on the LAN and from the WAN, and must present a valid TLS certificate.
- The customer firewall must allow only TCP 443 from the operator workstation to the uSS Port Broker, unless a different port is configured.
- Arteco Global SSO, DNS, certificate, and licensing endpoints must be reachable outbound from the uSee cloud or uSS node, according to the network-flow matrix.
- Technical credentials used to connect to the uSS node must be managed and protected according to the applicable customer policies; their encryption at rest and rotation lifecycle must be verified in the production configuration.
