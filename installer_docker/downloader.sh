#!/bin/bash

wget --no-check-certificate -c -O hypernode_installer.zip https://drive.usercontent.google.com/download?id=1mpKQRz3ihDvnevbY2NRTR1Q8hng9aExW&export=download&authuser=0 && \
mkdir -p hypernode_installer && \
unzip hypernode_installer.zip -d hypernode_installer && \
cd hypernode_installer && \
sh installer.sh -p 443