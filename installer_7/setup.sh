#!/bin/bash

# File to transfer
FILE="installer.sh"

# Ask for the server address
read -p "Enter the server address (e.g., 192.168.10.31): " HOST
HOST=${HOST:-192.168.10.31}

# Ask for the username
read -p "Enter the username (e.g., arteco): " USER
USER=${USER:-arteco}

# # Ask for the password securely
# echo -n "Enter the password: "
# stty -echo
# read PASSWORD
# stty echo
# echo

# where to copy the file

# Transfer the file using scp with -o StrictHostKeyChecking=no to avoid the authenticity prompt
echo "$PASSWORD" | scp -o StrictHostKeyChecking=no "$FILE" "$USER@$HOST:~"

# Check if the transfer was successful
if [ $? -eq 0 ]; then
    echo "File successfully copied to $USER@$HOST:~"

    #   # Connect to the server and execute the file
    # ssh -o StrictHostKeyChecking=no "$USER@$HOST" "bash ~/installer.sh"
  

else
    echo "Error: File transfer failed."
fi
