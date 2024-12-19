# Use the official Nginx base image
FROM nginx

# Copy custom configuration file to the container
COPY nginx_config/nginx.conf /etc/nginx/nginx.conf
COPY nginx_config/ssl/my.omniaweb.cloud.pem /etc/nginx/ssl/my.omniaweb.cloud.pem

# Expose port 80 for HTTP traffic
EXPOSE 80
EXPOSE 443

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]

#docker build -t nginx-local-purpose -f nginx.dockerfile .
#docker run --name custom-nginx-container --network bridge -p 80:80 -p 443:443 custom-nginx-image