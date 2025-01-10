import pika
import ssl

# Stringa di connessione AMQP
url = "amqps://hypernode:hypernode@V12230451.my.omniaweb.cloud:443"

# Configura le opzioni SSL per disabilitare la verifica del certificato
# IL CERTIFICATO NON PUo essere validato dentro rabbitmq

context = ssl.create_default_context()
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE

# Connessione con URLParameters e opzioni SSL
parameters = pika.URLParameters(url)
parameters.ssl_options = pika.SSLOptions(context)

connection = pika.BlockingConnection(parameters)
channel = connection.channel()

queue = 'testQueue'

# Assicurati che la coda esista
channel.queue_declare(queue=queue)

# Invia un messaggio
channel.basic_publish(exchange='', routing_key=queue, body='Hello, RabbitMQ!')
print(f" [x] Sent 'Hello, RabbitMQ!'")

connection.close()

# docker run \
#   --add-host V12230451.lan.omniaweb.cloud:192.168.10.67 \
#   -e RABBITMQ_URI="amqps://hypernode:hypernode@V12230451.my.omniaweb.cloud:443" \
#   -e GATEWAY_REMOTE_IP="wss://V12230451.my.omniaweb.cloud:443" \
#   artecoglobalcompany/usee_live_streamer:latest


# docker run \
#     --network=usee_service_suite_hypernode-net \
#     -e "GATEWAY_REMOTE_IP=wss://host.dopcker.internal:443" \
#     -e "SRV_INST_NAME=additional-miopc" \
#     -e "RABBITMQ_URI=amqp://hypernode:hypernode@messageBroker:5672" \
#     -e "DATABASE_URI=mongodb://host.dopcker.internal:27018/additional-miopc" \
#     artecoglobalcompany/usee_live_streamer:latest
