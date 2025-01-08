import pika
import ssl

# Stringa di connessione AMQP
url = "amqps://hypernode:hypernode@V12230451.my.omniaweb.cloud:443"

# Configura le opzioni SSL per disabilitare la verifica del certificato
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