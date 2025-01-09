# Usa un'immagine base con Python
FROM python:3.9-slim

# Imposta la directory di lavoro all'interno del container
WORKDIR /app

# Copia il file dello script (facoltativo)
COPY script.py /app/script.py

# Installa le librerie necessarie, nano e ping
RUN apt-get update && apt-get install -y nano iputils-ping && pip install pika && apt-get clean

# # Aggiorna il file hosts
# RUN echo "127.0.0.1 V12230451.lan.omniaweb.cloud" >> /etc/hosts && \
#     echo "127.0.0.1 V12230451.my.omniaweb.cloud" >> /etc/hosts

# Imposta il container in modalità interattiva
CMD ["bash"]


#docker build -t rabbitmq-nano .
#docker run -it --add-host V12230451.lan.omniaweb.cloud:192.168.10.67 --add-host V12230451.my.omniaweb.cloud:192.168.10.67 rabbitmq-nano


