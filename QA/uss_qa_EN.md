# uSS Server FAQ

## What happens if I disable the license of a server while it is running?

If the license of a **uSS** server is disabled while the server is running:

- At the next license validation (performed approximately once per hour) or after the next server restart, the license will be invalidated.
- **The server will continue running**: it will keep recording and streaming video through **uSee**.
- However, it will no longer be possible to manage the server through the **Configurator**, as you will always be prompted to complete the licensing process.
- Once the **DNS lease** expires, the server will no longer be reachable using its URL:
  ```
  https://VXXXXX.my.lan.omniaweb.cloud
  ```
- It is not possible to determine in advance when the DNS lease will expire, as its duration depends on the network provider and infrastructure.

---

## What happens if I set the local IP address to "Auto" instead of "Manual"?

When the local IP address is set to **Auto**:

- The system will attempt to automatically determine the local IP address by selecting the **first IP address** found among the available network interfaces. As a result, it may select an IP address on a network that is not reachable by the user.
- This feature is supported **only on Linux**.

> **Note**
>
> Automatic local IP detection is **not supported** on **Windows** or **macOS** servers because these operating systems do not provide access to the host machine information required by uSS.

---

## How can I access a uSS server after changing its local IP address?

If the local IP address of a **uSS** server is changed (for example, by moving it to a different subnet or assigning a new IP address):

1. Open the Configurator using the new IP address:
   ```
   https://NEW_IP_ADDRESS
   ```
2. Accept the HTTPS certificate warning.
3. Log in to the Configurator.
4. Update the **Local IP Address** setting by replacing the old address with the new one:
   ```
   NEW_IP_ADDRESS
   ```
5. Wait a few minutes for the new DNS record to propagate.

Once DNS propagation is complete, the server will again be accessible using its URL:

```
https://VXXXXX.my.lan.omniaweb.cloud
```