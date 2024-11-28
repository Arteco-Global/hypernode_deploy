docker run -d --name rabbitForLocalPurpose -e RABBITMQ_DEFAULT_USER=hypernode -e RABBITMQ_DEFAULT_PASS=hypernode -p 5672:5672 -p 15672:15672 rabbitmq:3.13-management


#docker run -d --name rabbitdiff -e RABBITMQ_DEFAULT_USER=hypernode -e RABBITMQ_DEFAULT_PASS=hypernode -p 9000:5672 -p 8585:15672 rabbitmq:3.13-management

# docker run  -e RABBITMQ_URI=amqp://hypernode:hypernode@172.17.0.1:5672 -e DATABASE_URI=mongodb://172.17.0.1:27017/camera-db2 --rm hypernode-server-camera 
