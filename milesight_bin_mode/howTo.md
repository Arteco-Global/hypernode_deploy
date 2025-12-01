- Preparazione pacchetti:
  - Entrare dentro la cartella della root di hypernode ed eseguire il comando 'build:distribution'. Questo comando crea i file worker bundles, crea i file binari e combina tutto insieme.
  - 

- Entrare nel menu web della telecamera
- Installare il firmware 'OV_63.8.0.5-r2-o3' tramite pagina web.
- Entrare in "impostazioni" -> "Storage management" -> "Impostare Storage Quota" -> "In base allo spazio sulla sd card, per esempio su una card da 64 GB ho impostato 40GB"






scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/camera-service root@192.168.5.139:/mnt/mmc/arteco/
scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/gateway-service root@192.168.5.139:/mnt/mmc/arteco/
scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/auth-service root@192.168.5.139:/mnt/mmc/arteco/
scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/coretrust-service root@192.168.5.139:/mnt/mmc/arteco/

scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/recording-service root@192.168.5.139:/mnt/mmc/arteco/
scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/event-service root@192.168.5.139:/mnt/mmc/arteco/
scp -r -O -P 6022 /Users/marcodalprato/downloads/pkg/snapshot-service root@192.168.5.139:/mnt/mmc/arteco/


