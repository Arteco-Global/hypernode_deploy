
# Installer Script Documentation

This document provides an overview and usage instructions for the installer script located at `installer.sh`.

## Table of Contents
- [Installer Script Documentation](#installer-script-documentation)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Global Variables](#global-variables)
  - [Functions](#functions)
    - [start\_spinner](#start_spinner)
    - [stop\_spinner](#stop_spinner)
    - [update\_progress](#update_progress)
    - [execute\_with\_spinner](#execute_with_spinner)
    - [show\_ascii\_art](#show_ascii_art)
    - [show\_progress](#show_progress)
    - [get\_my\_local\_ip](#get_my_local_ip)
    - [end\_with\_message](#end_with_message)
    - [drop\_server\_collection](#drop_server_collection)
    - [additionalServiceInstall](#additionalserviceinstall)
    - [dockerLogin](#dockerlogin)
    - [dockerInstall](#dockerinstall)
    - [show\_menu](#show_menu)
    - [get\_config](#get_config)
    - [cleanProcedure](#cleanprocedure)
    - [dockerNuke](#dockernuke)
    - [checkIfHypernodeIsInstalled](#checkifhypernodeisinstalled)
    - [check\_docker\_installed](#check_docker_installed)
    - [detectArchitecture](#detectarchitecture)
  - [Installation Steps](#installation-steps)
- [How to run](#how-to-run)

## Overview

This script automates the installation and management of various services for the uSee Service suite. It includes options for installing, updating, and cleaning up services, as well as managing Docker installations.

## Global Variables

- `TOTAL_STEPS`: Total number of steps for the progress bar.
- `CURRENT_STEP`: Counter for the progress bar.
- `SPINNER_ACTIVE`: Flag to control the spinner.
- `SPINNER_PID`: Process ID of the spinner.
- `SCRIPT_DIR`: Local path of the script.
- `ABSOLUTE_PATH`: Absolute path of the script.
- `SKIP_CLEAN`, `SKIP_DOCKER_INSTALL`, `ERASE_DB`: Flags for skipping certain steps.
- `HYPERNODE_ALREADY_INSTALLED`, `DOCKER_ALREADY_INSTALLED`: Flags indicating the installation status.
- `ARCH`: System architecture.
- ANSI color codes for formatting output.

## Functions

### start_spinner
Starts an animated spinner in the terminal.

### stop_spinner
Stops the animated spinner.

### update_progress
Updates the progress bar based on the current step.

### execute_with_spinner
Executes a command with an animated spinner and displays a message.

### show_ascii_art
Displays ASCII art in the terminal.

### show_progress
Displays a progress bar in the terminal.

### get_my_local_ip
Retrieves the local IP address of the machine.

### end_with_message
Displays a completion message and the local IP address.

### drop_server_collection
Drops the 'server' collection from the 'gateway-db' database in MongoDB.

### additionalServiceInstall
Installs or updates a specified service using Docker Compose.

### dockerLogin
Logs into Docker using a predefined token.

### dockerInstall
Installs Docker on the system.

### show_menu
Displays the installation or update menu based on the mode.

### get_config
Prompts the user for configuration options and sets environment variables.

### cleanProcedure
Cleans up the installation directory.

### dockerNuke
Stops and removes all Docker containers, images, networks, and volumes.

### checkIfHypernodeIsInstalled
Checks if the Hypernode suite is already installed.

### check_docker_installed
Checks if Docker is installed on the system.

### detectArchitecture
Detects the system architecture and sets the appropriate MongoDB image.

## Installation Steps

1. **Welcome Step**: Clears the terminal and displays ASCII art.
2. **Check Docker Installation**: Checks if Docker is installed.
3. **Check Hypernode Installation**: Checks if Hypernode is already installed.
4. **Get Configuration**: Prompts the user for configuration options.
5. **Detect Architecture**: Detects the system architecture.
6. **Docker Installation**: Installs Docker if not already installed.
7. **Docker Login**: Logs into Docker.
8. **Service Installation/Update**: Installs or updates the selected service.
9. **Clean Procedure**: Cleans up the installation directory if not skipped.

# How to run

To run the script, just call it with sh (onMacos) or bash (on Linux) ` sudo bash (sh) installer.sh`.