# Milesight Installer — Step‑by‑Step Walkthrough

This guide explains **exactly what each part of your two commands does**, in plain English, and highlights security/operational caveats. It’s written for constrained Linux environments (e.g., BusyBox `wget`) and for devices that will run Dockerized components.

> **What you run**
>
> 1) **Download the installer script**
> ```bash
> wget -c --no-check-certificate -O installer.sh "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/_recording_on_volumes/milesight/installer_milesight.sh"
> ```
>
> 2) **Execute the installer with your parameters**
> ```bash
> sh installer.sh \
>   --force-install \
>   --tag latest \
>   --mode 1 \
>   --port 445 \
>   --host "V12230451.my.omniaweb.cloud" \
>   --process-name "milesight" \
>   --serial-number "V12230451" \
>   --timezone "Europe/Rome" \
>   --internal-name "milesight" \
>   --email "luca.volta.arteco@gmail.com" \
>   --password "----" \
>   --server-ip "192.168.5.139" \
>   --certificate-provider-url "http://192.168.10.20:3000/certificate" \
>   --dns-provider-url "http://192.168.0.67:3000/dns-update" \
>   --license-provider-url "http://192.168.10.20:3000/sites" \
>   --update-provider-url "http://192.168.10.20:3000/update" \
>   --recording-path "/mnt/mmc/recqu/recording" \
>   --recording-max-disk 500000000000 \
>   --storage-path "/mnt/mmc/recqu/storage" \
>   --storage-max-disk 100000000000 \
>   --snapshot-path "/mnt/mmc/recqu/snapshot" \
>   --snapshot-max-disk 20000000000
> ```

---

## 1) Downloading the script (with `wget`)

Command:
```bash
wget -c --no-check-certificate -O installer.sh "https://raw.githubusercontent.com/.../installer_milesight.sh"
```

**Flags explained**

- `-c` — *Continue mode*. If the download is interrupted, `wget` will try to resume it instead of starting over.
- `--no-check-certificate` — Skip TLS certificate validation. Useful on minimal systems missing CA bundles or with outdated TLS stacks. **Security trade‑off**: this disables protection against MITM (man‑in‑the‑middle). Use only on trusted networks or when you can verify integrity another way (e.g., checksum/signature).
- `-O installer.sh` — Save the response as a file named `installer.sh` (instead of using the remote filename).
- URL — Points at the **Raw** content on GitHub for the `installer_milesight.sh` script, on the `_recording_on_volumes` branch under the `milesight` directory.

**Expected result**: a local executable script file named `installer.sh` appears in your current directory.

> **Tip**: On very minimal devices, `wget` might be BusyBox‑based and have limited TLS/SNI support. The flag `--no-check-certificate` helps with missing CA roots but cannot fix an entirely broken TLS stack. If TLS still fails, fetch the file elsewhere and transfer it over SCP, or proxy the request through a machine that can download it.


---

## 2) Running the installer (with `sh installer.sh …`)

You execute the script using the system shell (`sh`) and pass a set of **flags** that control what the installer configures. Here’s what each flag represents and why you might use it.

| Flag | Value | What it does | Notes |
|---|---|---|---|
| `--force-install` | *(no value)* | Forces a fresh (re)install even if components already exist. | Useful to overwrite old configs/images. May stop existing containers and replace volumes/config files depending on the script’s policy. |
| `--tag` | `latest` | Docker image tag to deploy. | `latest` pulls the newest tag; for reproducibility on older hardware/OS, consider a pinned tag (e.g., `v1.2.3`). |
| `--mode` | `1` | Selects an installation preset/profile. | **Script‑specific.** Typically chooses “standard” or “single‑node” mode. Refer to the installer docs if available. |
| `--port` | `443` | Public HTTPS port to expose. | The installer likely configures a reverse proxy (or app) to listen here. Make sure port 443 is free. |
| `--host` | `V12230451.my.omniaweb.cloud` | FQDN used for TLS certs and routing. | Make sure DNS points to this device’s public IP (or LAN IP if local only). |
| `--process-name` | `milesight` | Logical name for services/processes. | Often used for container names, systemd units, or log prefixes. |
| `--serial-number` | `V12230451` | Device/site identifier. | Often used for licensing, enrollment, and inventory. |
| `--timezone` | `Europe/Rome` | System/app timezone. | Ensures logs, schedules, and cron jobs use local time. |
| `--internal-name` | `milesight` | Internal short name. | Used inside configs and paths; cosmetic/organizational. |
| `--email` | `luca.volta.arteco@gmail.com` | Admin/owner email. | Often used for certificate issuance, alerts, password recovery. |
| `--password` | `Lv042020Arteco!` | Admin or bootstrap password. | **Highly sensitive.** Exposing it on the CLI can leak via shell history and process lists. See **Security notes** below. |
| `--server-ip` | `192.168.5.139` | Local IP where services bind or are reachable. | Keeps internal URIs stable on LAN. |
| `--certificate-provider-url` | `http://192.168.10.20:3000/certificate` | API endpoint to obtain TLS certs. | Using **HTTP** here means the certificate retrieval happens unencrypted on LAN. Prefer HTTPS if the provider supports it. |
| `--dns-provider-url` | `http://192.168.0.67:3000/dns-update` | API for dynamic DNS updates. | Ensures `--host` resolves correctly. |
| `--license-provider-url` | `http://192.168.10.20:3000/sites` | API to fetch/apply licenses. | The installer may POST the serial/email to fetch entitlements. |
| `--update-provider-url` | `http://192.168.10.20:3000/update` | API for software/firmware updates. | Lets the system check for and pull updates. |
| `--recording-path` | `/mnt/mmc/recqu/recording` | Bind‑mount path for **recordings**. | Must exist and be writable. Prefer a dedicated volume/mount. |
| `--recording-max-disk` | `500000000000` | Quota for recordings (in **bytes**). | ≈ **500 GB** (decimal) ≈ **465.66 GiB** (binary). |
| `--storage-path` | `/mnt/mmc/recqu/storage` | Bind‑mount path for **general storage**. | Must exist and be writable. |
| `--storage-max-disk` | `100000000000` | Quota for storage (in **bytes**). | ≈ **100 GB** ≈ **93.13 GiB**. |
| `--snapshot-path` | `/mnt/mmc/recqu/snapshot` | Bind‑mount path for **snapshots**. | Must exist and be writable. |
| `--snapshot-max-disk` | `20000000000` | Quota for snapshots (in **bytes**). | ≈ **20 GB** ≈ **18.63 GiB**. |

> **What the installer typically does** (based on common patterns):
> - Installs Docker / Docker Compose if missing.
> - Pulls the images with the specified `--tag`.
> - Renders `.env` and `docker-compose.yml` using your flags.
> - Creates/uses bind mounts for the three storage paths above and enforces quotas (script‑dependent).
> - Configures a reverse proxy on `--port` with `--host`.
> - Calls your certificate/DNS/license/update provider endpoints to bootstrap the device.
> - Enables auto‑start (e.g., via systemd) and health checks.
>
> Exact behavior can vary by script version; consult the repository’s README if present.


---

## 3) Storage & quotas — sanity checklist

- **Paths exist**: make sure `/mnt/mmc/recqu/{recording,storage,snapshot}` are present and writable by the user running Docker/containers.
- **Free space**: your quotas must be **≤ available space** on the underlying filesystem. Oversized quotas will fail at runtime.
- **Media type**: `/mnt/mmc` suggests embedded flash/SD. For heavy, continuous video write loads, consider wear‑resistant storage (SSD/HDD) or at least allocate generous spare area and monitor SMART/lifetime indicators.
- **Host vs container**: the installer likely uses **bind mounts**, so the quotas pertain to the **host** filesystem usage visible inside containers.


---

## 4) Post‑install verification (quick checks)

Run these after the script completes:

```bash
# Check containers are up
docker ps

# Tail the logs of the main service (replace with actual container name if different)
docker logs -f milesight

# Verify the HTTPS endpoint responds (certificate may not be trusted yet depending on your provider)
curl -k https://V12230451.my.omniaweb.cloud:443/ -I

# Check that storage paths are mounted in the container(s)
docker exec -it milesight sh -lc 'df -h | grep -E "recording|storage|snapshot"'
```

If DNS propagation is involved, verify that `V12230451.my.omniaweb.cloud` resolves to the correct IP (public or LAN depending on your topology).


---

## 5) Security notes (important)

- **Plain‑text password on CLI**: Anything passed on the command line can leak via shell history and `ps` process listings.
  - Prefer reading secrets from **environment variables** or **files** (e.g., `.env`) consumed by the installer.
  - If you must use CLI flags, clear your shell history afterward (`history -c` on Bash) and restrict local access.
- **`--no-check-certificate`**: Bypassing TLS verification is risky. Consider downloading from a trusted intermediary host with full CA bundle support, then copying the file over SCP.
- **HTTP provider URLs**: Your `certificate`, `dns-update`, `sites`, and `update` endpoints use `http://`. If supported, migrate them to `https://` and use tokens/keys with least privilege.


---

## 6) Troubleshooting

- **Download fails (TLS / reset by peer)**: On minimal distros, BusyBox `wget` may not support modern TLS/SNI. Options:
  - Use `--no-check-certificate` (already present) *and* ensure the device’s clock is correct (`date`/NTP).
  - Download on another machine and `scp installer.sh <device>:`.
- **Port 443 already in use**: Free the port (`lsof -i :443`) or change `--port`.
- **Missing storage paths**: Create them with correct ownership/permissions:
  ```bash
  mkdir -p /mnt/mmc/recqu/{recording,storage,snapshot}
  chown -R root:root /mnt/mmc/recqu
  chmod -R 755 /mnt/mmc/recqu
  ```
- **DNS not updating**: Ensure the device can reach `--dns-provider-url` and that the token/credentials (if any) are valid.
- **Certificates not issued**: Confirm reachability of `--certificate-provider-url`, check logs for CSR/ACME errors, and verify that `--host` resolves to this device.


---

## 7) Re‑running and cleanup

- Re‑run with `--force-install` to refresh containers/configs as the script allows.
- To remove containers/images/volumes (destructive):
  ```bash
  docker compose down -v    # from the deployment folder
  docker system prune -af   # removes dangling images/containers
  ```

---

## Appendix: Byte conversions used

- `500000000000` bytes ≈ **500 GB** (decimal) ≈ **465.66 GiB** (binary).
- `100000000000` bytes ≈ **100 GB** ≈ **93.13 GiB**.
- `20000000000` bytes ≈ **20 GB** ≈ **18.63 GiB**.

> **Formula**: `GiB = bytes / 1,073,741,824` (2^30), `GB = bytes / 1,000,000,000`.

---

### Final checklist before you run

- [ ] Correct hostname and DNS routing for `V12230451.my.omniaweb.cloud`.
- [ ] Port **443** is available.
- [ ] Storage paths exist and have enough free space for your quotas.
- [ ] Network can reach certificate/DNS/license/update provider URLs.
- [ ] You’re comfortable with the security trade‑offs (or have mitigations in place).

All set—run the commands in order and watch the logs.
