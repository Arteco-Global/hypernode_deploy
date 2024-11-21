#!/bin/bash

echo "What would you like to do?"
echo "1. Stop all containers"
echo "2. Start all containers"
echo "3. Stop a specific container"
echo "4. Start a specific container"
read -p "Enter the number of your choice: " choice

case $choice in
    1)
        echo "Stopping all containers..."
        sudo docker stop $(sudo docker ps -aq)
        ;;
    2)
        echo "Starting all containers..."
        sudo docker start $(sudo docker ps -aq)
        ;;
    3)
        read -p "Enter the name or ID of the container to stop: " container_name
        echo "Stopping container $container_name..."
        sudo docker stop $container_name
        ;;
    4)
        read -p "Enter the name or ID of the container to start: " container_name
        echo "Starting container $container_name..."
        sudo docker start $container_name
        ;;
    *)
        echo "Invalid choice. Exiting..."
        ;;
esac
