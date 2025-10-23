# copy file
*scp -O -P 6022 ./milesight_camera.zip root@192.168.5.139:/mnt/mmc/milesight_camera.zip
unzip it

# run db
cd /mnt/mmc/zipfolder/ferretdb
./ferretdb --handler=sqlite --sqlite-url=file:ferret.db --listen-addr=0.0.0.0:27017

# run camera service
cd /mnt/mmc/zipfolder/camera.sh