# Hypernode Setup and Configuration Procedure on Milesight

## 1. Package Preparation

1. Enter the **Hypernode root folder**.
2. Run:

   ```bash
   build:distribution
   ```

   This command creates the worker bundles, generates the binaries, and assembles everything together.
3. Create an `ffmpeg` folder inside the root (pkg):

   ```bash
   mkdir ffmpeg
   ```

   Copy the correct ffmpeg binaries for your target solution into this folder.

---

## 2. Camera Web Interface Configuration

1. Access the camera's **web interface**.
2. Install the firmware:

   **OV_63.8.0.5-r2-o3**
3. Set the storage quota:
   - Settings → Storage management → Set Storage Quota  
   - Example: on a 64 GB SD card, set the quota to 40 GB.

---

## 3. Configuration on Milesight via SSH

### RabbitMQ (port 15672)

Execute the following:

```bash
find / -name .erlang.cookie 2>/dev/null
cp /.erlang.cookie /root/.erlang.cookie
chmod 400 /root/.erlang.cookie
rabbitmqctl status
rabbitmq-plugins enable rabbitmq_management
rabbitmqctl add_user hypernode hypernode
rabbitmqctl set_user_tags hypernode administrator
rabbitmqctl set_permissions -p / hypernode ".*" ".*"
```
Login the rabbitmq web page (ip:15672) and check if 'hypernode' user got access to 'Can access virtual hosts'. If not, provide it.

---

### MongoDB (port 27017)

Check that MongoDB responds on:

```
127.0.0.1:27017
```

---

### Nginx

1. Upload the new configuration:

   ```bash
   scp -r -O -P 6022 ./nginx.conf root@192.168.5.139:/tools/nginx/conf/nginx.conf
   ```

2. Start nginx:

   ```bash
   nginx -c /tools/nginx/conf/nginx.conf -p /tools/nginx
   ```

3. Verify that nginx responds on **port 8080** at the camera's IP.

---

### HAProxy

1. Create the SSL folder:

   ```bash
   mkdir /tools/haproxy/ssl/
   ```

2. Upload the HAProxy configuration:

   ```bash
   scp -r -O -P 6022 ./haproxy.cfg root@192.168.5.139:/tools/haproxy/haproxy.cfg
   ```

3. Upload the certificate:

   ```bash
   scp -r -O -P 6022 ../../hypernode-server/ssl/my.omniaweb.cloud.pem root@192.168.5.139:/tools/haproxy/ssl/my.omniaweb.cloud.pem
   ```

4. Start HAProxy:

   ```bash
   haproxy -f haproxy.cfg -db
   ```

---

## 4. Hypernode Files on SD Card

1. Create the directory on the SD card:

   ```bash
   mkdir /mnt/mmc/hypernodefull
   ```

2. Copy the prepared `pkg` folder from another location (e.g., Downloads).

3. For each service, **keep only**:
   - `main-linux-arm64`
   - `run-linux-arm64.sh`
   - `worker-bundles`

4. In the main root, keep only:

   - `run-all-linux-arm64.sh`

5. Copy everything to the Milesight device:

   ```bash
   scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg root@192.168.5.139:/mnt/mmc/hypernodefull/
   ```

   The transfer may take some time.

6. Verify that the `pkg` folder is correctly present inside `/mnt/mmc/hypernodefull`.
