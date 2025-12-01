- Preparazione pacchetti:
  - Entrare dentro la cartella della root di hypernode ed eseguire il comando 'build:distribution'. Questo comando crea i file worker bundles, crea i file binari e combina tutto insieme.
  - Creare una cartella "ffmpeg" nella root (pkg) dove copi dentro i binari corretti per quella soluzione.
  - 

- Entrare nel menu web della telecamera
- Installare il firmware 'OV_63.8.0.5-r2-o3' tramite pagina web.
- Entrare in "impostazioni" -> "Storage management" -> "Impostare Storage Quota" -> "In base allo spazio sulla sd card, per esempio su una card da 64 GB ho impostato 40GB"

- Sulla milesight, via SSH:

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
  - MongoDB (port 27017)
    - Check if mongo respond on port (127.0.0.1:27017)
  - Nginx
    - Upload della nuova configurazione di nginx col comando 'scp -r -O -P 6022 ./nginx.conf root@192.168.5.139:/tools/nginx/conf/nginx.conf'
    - Avvia nginx con '/tools/nginx/conf$ nginx -c /tools/nginx/conf/nginx.conf -p /tools/nginx'
    - Verifica che all'ip della telecamera sulla porta 8080 risponda ora nginx


scp -r -O -P 6022 ./nginx.conf root@192.168.5.139:/tools/nginx/conf/nginx.conf

scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/camera-service root@192.168.5.139:/mnt/mmc/arteco/