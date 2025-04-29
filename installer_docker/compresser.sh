#!/bin/bash

# This script compresses the installer and composes directories into a zip file.
# It creates a new directory called hypernode_installer, copies the necessary files into it,
# and then zips the entire directory. Finally, it cleans up by removing the hypernode_installer directory.
# Usage: ./compresser.sh
# Check if the script is run from the correct directory

# Upload the file to the server

mkdir -p hypernode_installer
cd hypernode_installer
mkdir -p composes

cp -r ../composes ./
cp ../installer.sh ./installer.sh

zip -r  ../hypernode_installer.zip .
rm -rf ../hypernode_installer
