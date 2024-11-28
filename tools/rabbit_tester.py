import pika

# Stringa di connessione AMQP
# url = "amqp://hypernode:hypernode@127.0.0.1:5672"
url = "amqp://hypernode:hypernode@127.0.0.1:90"


# Connessione con URLParameters
connection = pika.BlockingConnection(pika.URLParameters(url))
channel = connection.channel()


queue = 'testQueue'

# Assicurati che la coda esista
channel.queue_declare(queue=queue)

# Invia un messaggio
channel.basic_publish(exchange='', routing_key=queue, body='Hello, RabbitMQ!')
print(f" [x] Sent 'Hello, RabbitMQ!'")

connection.close()
