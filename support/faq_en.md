# uSS Server - FAQ

## What happens if I disable the license of a running server?

If the license of a **uSS** server is disabled while the server is running:

- At the next license validation (performed approximately once per hour) or after the server is restarted, the license will be invalidated.
- **The server will not stop running**: it will continue recording and streaming video through **uSee**.
- However, it will no longer be possible to manage the server through the **Configurator**, as the licensing procedure will always be required before access is granted.
- Once the **DNS lease** expires, the server will no longer be reachable using its URL:
  ```
  https://VXXXXX.my.lan.omniaweb.cloud
  ```
- It is not possible to determine in advance when the DNS lease will expire, as its duration depends on the provider and the network configuration.

---

## What happens if I set the Local IP Address to "Auto" instead of "Manual"?

When the **Local IP Address** is set to **Auto**:

- The system will automatically determine the local IP address by selecting the **first IP address** found among the available network interfaces (this may result in selecting an IP address that is not reachable by the user).
- This mode is supported **only on Linux**.

> **Note**
>
> Automatic local IP address detection is **not supported** on **Windows** and **macOS**, as these operating systems do not provide the information required to identify the host machine's network interfaces.

---

## How can I reach a uSS server after changing its local IP address?

If the **uSS** server's IP address changes (for example, after changing subnet or assigning a new IP address):

1. Connect to the Configurator using the new IP address:
   ```
   https://NEW_IP_ADDRESS
   ```
2. Accept the warning about the invalid HTTPS certificate.
3. Log in to the Configurator.
4. Update the **Local IP Address** setting by replacing the old address with the new one:
   ```
   NEW_IP_ADDRESS
   ```
5. Wait a few minutes for the new DNS record to propagate.

Once DNS propagation is complete, the server will again be reachable using its URL:

```
https://VXXXXX.my.lan.omniaweb.cloud
```

---

## What happens to the license if a server goes offline?

If a **uSS** server loses its Internet connection:

- The license validation service detects the lack of connectivity and **automatically postpones the license check**.
- As a result, **the license is not invalidated**, and the server continues to operate normally.

However, while the Internet connection is unavailable, **the server may no longer be reachable using its DNS hostname**.

This can happen if, while the server is offline, any of the following changes:

- the server's **local IP address**;
- the network's **public IP address**;
- or both.

In these cases, the DNS record:

```
https://VXXXXX.my.lan.omniaweb.cloud
```

may no longer be synchronized with the server's current addresses.

Once the Internet connection is restored:

- the server automatically updates its DNS record;
- after a few minutes, it will once again be reachable using its URL.

> **Note**
>
> Even if the DNS record is temporarily out of date, the server always remains accessible from the local network using its IP address:
>
> ```
> https://LOCAL_IP_ADDRESS
> ```