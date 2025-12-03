- Preparazione pacchetti:
  - Entrare dentro la cartella della root di hypernode ed eseguire il comando 'build:distribution'. Questo comando crea i file worker bundles, crea i file binari e combina tutto insieme.
  - Creare una cartella "ffmpeg" nella root (pkg) dove copi dentro i binari corretti per quella soluzione.

- Camera
  - Entrare nel menu web della telecamera
  - Installare il firmware 'OV_63.8.0.5-r2-o3' tramite pagina web.
  - Entrare in "impostazioni" -> "Storage management" -> "Impostare Storage Quota" -> "In base allo spazio sulla sd card, per esempio su una card da 64 GB ho impostato 40GB"

- Sulla milesight, via ssh fai le seguenti operazioni:

  - RabbitMQ (port 15672)
    - lancia in sequenza:
    - find / -name .erlang.cookie 2>/dev/null
    - cp /.erlang.cookie /root/.erlang.cookie
    - chmod 400 /root/.erlang.cookie
    - rabbitmqctl status
    - rabbitmq-plugins enable rabbitmq_management
    - rabbitmqctl add_user hypernode hypernode
    - rabbitmqctl set_user_tags hypernode administrator
    - rabbitmqctl set_permissions -p / hypernode ".*" ".*"
    - Now login the rabbitmq web page (ip:15672) and check if 'hypernode' user got access to 'Can access virtual hosts'. If not, provide it.

  - MongoDB (port 27017)
    - Check if mongo respond on port (127.0.0.1:27017)
    - stop mongo
    - run mongo with: ' /mnt/mmc/tools/mongodb/bin/mongod \
  --dbpath /mnt/mmc/tools/mongodb/data/db \
  --fork \
  --logpath /mnt/mmc/tools/mongodb/mongod.log \
  --bind_ip 0.0.0.0 \
  --port 27017' in order to allow external connections

  
  - Nginx
    - Upload della nuova configurazione di nginx col comando 'scp -r -O -P 6022 ./nginx.conf root@192.168.5.139:/tools/nginx/conf/nginx.conf'
    - Avvia nginx con '/tools/nginx/conf$ nginx -c /tools/nginx/conf/nginx.conf -p /tools/nginx'
    - Verifica che all'ip della telecamera sulla porta 8080 risponda ora nginx
  
  - HaProxy
    - creare la cartella 'ssl' in '/tools/haproxy/ssl/' con 'mkdir /tools/haproxy/ssl/'
    - copia la configurazione con 'scp -r -O -P 6022 ./haproxy.cfg root@192.168.5.139:/tools/haproxy/haproxy.cfg'
    - copiare il certtificato col comando 'scp -r -O -P 6022 ../../hypernode-server/ssl/my.omniaweb.cloud.pem root@192.168.5.139:/tools/haproxy/ssl/my.omniaweb.cloud.pem'
    - lanciare haproxy con 'haproxy -f haproxy.cfg -db'

  - Files
    - creare una cartella dentro la scheda sd '/mnt/mmc/hypernodefull'
    - copiare la root creata prima (pkg) da un'altra parte (tipo download)
    - per ogni servizio, rimuovere a mano tutto tranne 'main-linux-arm64' e 'run-linux-arm64.sh' e 'worker-bundles'
    - nella root, mantenere solo 'run-all-linux-arm64.sh'
    - copiare tutto con 'scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg root@192.168.5.139:/mnt/mmc/hypernodefull/' -> richiederà tempo.
    - verificare che sia stato creato il file pkg.

  - Configurator
    - run 'npm run build' from the 'hypernode_server_gui/configurator' folder.
    - run 'scp -r -O -P 6022 ../../hypernode_server_gui/configurator/dist/* root@192.168.5.139:/tools/nginx/html/'




scp -r -O -P 6022 /Users/marcodalprato/Downloads/ffmpeg/* root@192.168.5.139:/mnt/mmc/hypernodefull/pkg/ffmpeg


scp -r -O -P 6022 ../../hypernode_server_gui/configurator/dist root@192.168.5.139:/tools/nginx/html
scp -r -O -P 6022 ../../hypernode-server/ssl/my.omniaweb.cloud.pem root@192.168.5.139:/tools/haproxy/ssl/my.omniaweb.cloud.pem

cd ../hypernode-server/ssl/my.omniaweb.cloud.pem

haproxy.cfg
scp -r -O -P 6022 ./haproxy.cfg root@192.168.5.139:/tools/haproxy/haproxy.cfg

scp -r -O -P 6022 ./nginx.conf root@192.168.5.139:/tools/nginx/conf/nginx.conf

scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg root@192.168.5.139:/mnt/mmc/hypernodefull/


stop nginx: ./sbin/nginx -s stop

start nginx: ./sbin/nginx -c /tools/nginx/conf/nginx.conf


reload config nginx : ./sbin/nginx -s reload
