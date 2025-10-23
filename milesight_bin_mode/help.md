scp -O -P 6022 /Users/marcodalprato/Downloads/test.zip root@192.168.5.139:/mnt/mmc/SERVER/test.zip

scp -O -P 6022 /Users/marcodalprato/Downloads/ferretdb/FerretDB/ferretdb-sqlite root@192.168.5.139:/mnt/mmc/SERVER/ferretdb-sqlite

scp -O -P 6022 /Users/marcodalprato/Downloads/docker-compose.yml root@192.168.5.139:/mnt/mmc/SERVER/docker-compose.yml



wget -c --no-check-certificate -O ffmpeg-master-latest-linuxarm64-gpl.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz"


#Install mongo
wget -c --no-check-certificate -O mongodb-linux-aarch64-ubuntu2204-7.0.5.tgz https://fastdl.mongodb.org/linux/mongodb-linux-aarch64-ubuntu2204-7.0.5.tgz


"pkg:camera-service": "npm run build:camera-service && pkg dist/apps/camera-service/apps/camera-service/src/main.js --targets node18-linux-arm64 --out-path dist/pkg/camera-service",
    "pkg:gateway-service": "npm run build:gateway-service && pkg dist/apps/gateway-service/apps/gateway-service/src/main.js --targets node18-linux-arm64 --out-path dist/pkg/gateway-service",
    "pkg:event-service": "pkg dist/apps/event-service/apps/event-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/event-service",
    "pkg:storage-service": "pkg dist/apps/storage-service/apps/storage-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/storage-service",
    "pkg:auth-service": "pkg dist/apps/auth-service/apps/auth-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/auth-service",
    "pkg:snapshot-service": "pkg dist/apps/snapshot-service/apps/snapshot-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/snapshot-service",
    "pkg:recording-service": "pkg dist/apps/recording-service/apps/recording-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/recording-service",
    "pkg:coretrust-service": "pkg dist/apps/coretrust-service/apps/coretrust-service/src/main.js --targets node18-linux-x64,node18-win-x64,node18-macos-x64 --out-path dist/pkg/coretrust-service",
    "pkg:all": "npm run pkg:camera-service && npm run pkg:gateway-service && npm run pkg:event-service && npm run pkg:storage-service && npm run pkg:auth-service && npm run pkg:snapshot-service && npm run pkg:recording-service && npm run pkg:coretrust-service",
    "build:workers": "node scripts/build-workers.js",
   


STEP per installare tutto

FerretDB (alternativa a Mongo in quanto piu leggera)
Downloads (https://github.com/FerretDB/FerretDB/releases/)


    cd /hypernode/ferretdb
    # es: una versione 1.24.2 presente su mirror:

    wget -c --no-check-certificate -O ferretdb-arm64-linux https://github.com/FerretDB/FerretDB/releases/download/v1.19.0/ferretdb-linux-arm64

    o in alternativa

    scp -O -P 6022 /Users/marcodalprato/Downloads/ferretdb-linux-arm64_1_9_0 root@192.168.5.139:/mnt/mmc/SERVER/ferretdb-linux-arm64_1_9_0

    chmod +x ferretdb-linux-arm64_1_9_0
    ./ferretdb-linux-arm64_1_9_0 --listen-addr 0.0.0.0:27017 --storage-backend sqlite

** mongo way

    mkdir -p /mnt/mmc/SERVER/mongo
    cd /mnt/mmc/SERVER/mongo

    wget https://fastdl.mongodb.org/linux/mongodb-linux-aarch64-ubuntu2004-6.0.6.tgz
    scp -O -P 6022 /Users/marcodalprato/Downloads/mongodb-linux-aarch64-ubuntu2004-6.0.6.tgz root@192.168.5.139:/mnt/mmc/SERVER/mongo/mongodb-linux-aarch64-ubuntu2004-6.0.6.tgz
    tar -xzf mongodb-linux-aarch64-ubuntu2004-6.0.6.tgz
    cd mongodb-linux-aarch64-ubuntu2004-6.0.6/bin



    scp -O -P 6022 /Users/marcodalprato/Downloads/liblzma5_5.2.4-1ubuntu1.1_arm64.deb root@192.168.5.139:/mnt/mmc/SERVER/mongo/lib/liblzma5_5.2.4-1ubuntu1.1_arm64.deb

    scp -O -P 6022 /Users/marcodalprato/Downloads/libcurl4_7.68.0-1ubuntu2.25_arm64.deb root@192.168.5.139:/mnt/mmc/SERVER/mongo/lib/libcurl4_7.68.0-1ubuntu2.25_arm64.deb




 wget -c --no-check-certificate -O libc6_2.31-0ubuntu9.9_arm64.deb  http://launchpadlibrarian.net/596549974/libc6_2.31-0ubuntu9.9_arm64.deb
cp /mnt/mmc/SERVER/mongo/lib/lib/aarch64-linux-gnu/libresolv.so.2 /mnt/mmc/SERVER/mongo/lib/
cp lib/aarch64-linux-gnu/libresolv.so.2 .


# Scarica ffmpeg per linux-arm64 (versione 6.1)
wget https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffmpeg-6.1-linux-arm-64.zip
# Scarica ffprobe per linux-arm64
wget https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffprobe-6.1-linux-arm-64.zip

# Estrai e installa
unzip ffmpeg-6.1-linux-arm-64.zip -d ffmpeg-bin
unzip ffprobe-6.1-linux-arm-64.zip -d ffprobe-bin

sudo mv ffmpeg-bin/ffmpeg /usr/local/bin/
sudo mv ffprobe-bin/ffprobe /usr/local/bin/
sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# Verifica
ffmpeg -version
ffprobe -version
