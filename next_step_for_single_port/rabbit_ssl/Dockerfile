# Usa l'immagine base di RabbitMQ con management plugin
FROM rabbitmq:3.13-management

# Copia il file rabbitmq.conf nel container
COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
# Copia il certificato SSL nella directory di configurazione di HAProxy
COPY my.omniaweb.cloud.pem /etc/rabbitmq/

# Imposta le variabili di ambiente per il default user e password
ENV RABBITMQ_DEFAULT_USER=hypernode
ENV RABBITMQ_DEFAULT_PASS=hypernode

# Esponi le porte necessarie (5672 per RabbitMQ, 15672 per la console di gestione)
EXPOSE 5672 15672

# Comando per avviare RabbitMQ
CMD ["rabbitmq-server"]

#docker build -t custom-rabbitmq .
#docker run -d --name rabbitForLocalPurposeSSL -p 5672:5672 -p 5671:5671 -p 15672:15672 custom-rabbitmq


#docker run -ti /bin/bash custom-rabbitmq
