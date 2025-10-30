FROM alpine:3.20

# Installa FUSE3 (non fuse2) + rclone + strumenti base
RUN apk add --no-cache rclone fuse3 bash ca-certificates tzdata \
 && echo "user_allow_other" >> /etc/fuse.conf \
 && ln -s /usr/bin/fusermount3 /usr/bin/fusermount

WORKDIR /app

# Copia lo script di montaggio
COPY mount.sh /app/mount.sh
RUN chmod +x /app/mount.sh

# Variabili di ambiente predefinite
ENV RCLONE_CONFIG_BASE64=""
ENV GDRIVE_REMOTE="gdrive"
ENV GDRIVE_PATH="snapshots"
ENV MOUNT_PATH="/snapshot_files"
ENV RCLONE_CACHE_DIR="/dev/shm/rclone-cache"

ENTRYPOINT ["/app/mount.sh"]
