FROM rabbitmq:3.8.17-management

# Copy the combined PEM file
COPY my.omniaweb.cloud.pem /etc/rabbitmq/certs/my.omniaweb.cloud.pem

# Copy RabbitMQ configuration file
COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf

# Expose the AMQPS port
EXPOSE 5671