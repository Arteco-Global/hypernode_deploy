#!/bin/sh

# Default port
PORT=443

# Parse command-line arguments
while getopts "p:" opt; do
  case $opt in
    p) PORT=$OPTARG ;;
    *) echo "Usage: $0 -p <port>"; exit 1 ;;
  esac
done

# Create the working directory
mkdir -p hypernode
cd hypernode || { echo "Error entering the hypernode directory"; exit 1; }

# Download the ZIP file with authentication
wget "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/main/installer_docker/hypernode_installer.zip" \
  --header="Authorization: token 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" \
  -O hypernode_installer.zip

# Check if the download was successful
if [ $? -ne 0 ]; then
  echo "Error downloading the ZIP file"
  exit 1
fi

# Extract the contents of the ZIP
unzip -o hypernode_installer.zip

# Check if the installer.sh file exists
if [ ! -f installer.sh ]; then
  echo "installer.sh not found after extraction"
  exit 1
fi

# Make the script executable
chmod +x installer.sh

# Run the script with the specified port
sh installer.sh -fi -p "$PORT"
