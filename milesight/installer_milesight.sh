#!/bin/bash

#wget -c --no-check-certificate -O installer.sh "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/_recording_on_volumes/installer_docker/installer_milesight.sh"

# MILESHIGHT INSTALLER TEST |

# sudo bash installer.sh \
#   --force-install \
#   --tag latest \
#   --mode 1 \
#   --port 443 \
#   --host "v000001.my.omniaweb.cloud" \
#   --process-name "gateway" \
#   --serial-number "A1B2C3D4E5" \
#   --timezone "Europe/Rome" \
#   --internal-name "HyperNodeServer01" \
#   --email "admin@arteco-global.com" \
#   --password "SuperSecret123" \
#   --server-ip "192.168.1.100" \
#   --certificate-provider-url "http://192.168.10.20:3000/certificate" \
#   --dns-provider-url "http://192.168.0.67:3000/dns-update" \
#   --license-provider-url "http://192.168.10.20:3000/sites" \
#   --update-provider-url "http://192.168.10.20:3000/update" \
#   --recording-path "/mnt/mmc/recqu/recording" \
#   --recording-max-disk 500000000000 \
#   --storage-path "/mnt/mmc/recqu/storage" \
#   --storage-max-disk 100000000000 \
#   --snapshot-path "/mnt/mmc/recqu/snapshot" \
#   --snapshot-max-disk 20000000000


# Global vars
SCRIPT_DIR=$(dirname "$0") #local path
ABSOLUTE_PATH=https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads/main/installer_docker/composes

HYPERNODE_ALREADY_INSTALLED="false"
DOCKER_ALREADY_INSTALLED="false";
RUNNING_AS_SUDO="false"
COMPOSE_CMD="docker compose"
ARCH=$(uname -m)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m' # Color reset

COMPOSE_CACHE_DIR=${COMPOSE_CACHE_DIR:-/tmp/hypernode_composes}
COMPOSE_CACHE_IS_TEMP="false"

if command -v mktemp >/dev/null 2>&1; then
    TMP_DIR=$(mktemp -d /tmp/hypernode_composes_XXXX 2>/dev/null)
    if [ -n "$TMP_DIR" ]; then
        COMPOSE_CACHE_DIR="$TMP_DIR"
        COMPOSE_CACHE_IS_TEMP="true"
    fi
fi

mkdir -p "$COMPOSE_CACHE_DIR"

cleanup_compose_cache() {
    if [ "$COMPOSE_CACHE_IS_TEMP" = "true" ] && [ -d "$COMPOSE_CACHE_DIR" ]; then
        rm -rf "$COMPOSE_CACHE_DIR"
    fi
}

trap cleanup_compose_cache EXIT

# Check wget availability
if ! command -v wget &> /dev/null; then
    echo "❌ wget is required but not installed. Install it with: apt install wget -y"
    exit 1
fi

# Default values for input parameters
SSL_PORT=443
DOCKER_TAG="latest"
FORCE_INSTALL="false"
DB_PORT=27017

PROCESS_NAME="--"
remote_host="--"   


execute_command() {
    local COMMAND=$1
    local MESSAGE=$2

    eval "$COMMAND" 
    local COMMAND_STATUS=$?

    if [ $COMMAND_STATUS -eq 0 ]; then
        printf "\r✅ %s - Done.\n" "$MESSAGE"
    else
        printf "\r❌ %s - Failed.\n" "$MESSAGE"
        exit 1
    fi
}

download_compose_file() {
    local REMOTE_PATH=$1
    local OUTPUT_PATH=$2
    local LABEL=$3

    if [ -z "$REMOTE_PATH" ] || [ -z "$OUTPUT_PATH" ]; then
        printf "❌ Missing parameters for download_compose_file.\n"
        exit 1
    fi

    LABEL=${LABEL:-"Downloading compose: $REMOTE_PATH"}
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    rm -f "$OUTPUT_PATH"

    execute_command "wget --no-check-certificate -q -O '$OUTPUT_PATH' '$ABSOLUTE_PATH/$REMOTE_PATH'" "$LABEL"
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -fi|--force-install)
      FORCE_INSTALL="true"
      shift
      ;;
    -p|--port)
      SSL_PORT="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_TAG="$2"
      shift 2
      ;;
    -m|--mode)
      INSTALL_OPTION="$2"
      shift 2
      ;;
    -host|--host)
      remote_host="$2"
      shift 2
      ;;
    -pn|--process-name)
      PROCESS_NAME="$2"
      shift 2
      ;;
    -sn|--serial-number)
      SERIAL_NUMBER="$2"
      export SERIAL_NUMBER
      shift 2
      ;;
    -tz|--timezone)
      SERVER_TIMEZONE="$2"
      export SERVER_TIMEZONE
      shift 2
      ;;
    -in|--internal-name)
      SERVER_NAME="$2"
      export SERVER_NAME
      shift 2
      ;;
    -email|--email)
      ARTECO_GLOBAL_EMAIL="$2"
      export ARTECO_GLOBAL_EMAIL
      shift 2
      ;;
    -pass|--password)
      ARTECO_GLOBAL_PASSWORD="$2"
      export ARTECO_GLOBAL_PASSWORD
      shift 2
      ;;
    -sip|--server-ip)
      SERVER_IP_ADDRESS="$2"
      export SERVER_IP_ADDRESS
      shift 2
      ;;
    -cert-url|--certificate-provider-url)
      CERTIFICATE_PROVIDER_URL="$2"
      export CERTIFICATE_PROVIDER_URL
      shift 2
      ;;
    -dns-url|--dns-provider-url)
      DNS_PROVIDER_URL="$2"
      export DNS_PROVIDER_URL
      shift 2
      ;;
    -lic-url|--license-provider-url)
      LICENSE_PROVIDER_URL="$2"
      export LICENSE_PROVIDER_URL
      shift 2
      ;;
    -upd-url|--update-provider-url)
      UPDATE_PROVIDER_URL="$2"
      export UPDATE_PROVIDER_URL
      shift 2
      ;;
    -rec-path|--recording-path)
      RECORDING_PATH="$2"
      export RECORDING_PATH
      shift 2
      ;;
    -rec-max-disk|--recording-max-disk)
      RECORDING_DISK_SPACE="$2"
      export RECORDING_DISK_SPACE
      shift 2
      ;;
    -storage-path|--storage-path)
      STORAGE_PATH="$2"
      export STORAGE_PATH
      shift 2
      ;;
    -storage-max-disk|--storage-max-disk)
      STORAGE_DISK_SPACE="$2"
      export STORAGE_DISK_SPACE
      shift 2
      ;;
    -snapshot-path|--snapshot-path)
      SNAPSHOT_PATH="$2"
      export SNAPSHOT_PATH
      shift 2
      ;;
    -snapshot-max-disk|--snapshot-max-disk)
      SNAPSHOT_DISK_SPACE="$2"
      export SNAPSHOT_DISK_SPACE
      shift 2
      ;;
    -h|--help)
      echo "Usage: installer.sh [options]"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      shift
      ;;
  esac
done


export SSL_PORT
export DOCKER_TAG

get_my_local_ip() {
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        echo "127.0.0.1" 
    else
        echo "$ip"
    fi
}

end_with_message() {
    local message=$1
    local success=$2
    local myIp=$(get_my_local_ip)

    printf "\r\033[K"
    if [ "$success" -eq 0 ]; then
        printf "\n🎉 %s: Operation completed successfully!\n\n" "$message"
        if [[ "$message" == "Server installation" || "$message" == "Server update" ]]; then
            printf "\n You can now access the uSee Configurator at https://$myIp:$SSL_PORT\n"
        fi
    else
        printf "\n❌ %s: Operation failed. Please check the logs.\n\n" "$message"
        exit 1
    fi
}

installLocalDb() {
    printf "\nInstalling local database on port $DB_PORT"
    printf "\nDatabase compose source: $ABSOLUTE_PATH/database/docker-compose.yaml"

    local DATABASE_COMPOSE_LOCAL="$COMPOSE_CACHE_DIR/database-docker-compose.yaml"
    download_compose_file "database/docker-compose.yaml" "$DATABASE_COMPOSE_LOCAL" "Downloading database compose"

    execute_command "$COMPOSE_CMD -f '$DATABASE_COMPOSE_LOCAL' up -d --build --remove-orphans" \
        "Installing local database" || return 1
    return 0
}

additionalServiceInstall() {
    local SERVICE_NAME=$1
    local TYPE_OF_INSTALL=${2:-"install"} 
    local REMOTE_COMPOSE_PATH="$SERVICE_NAME/docker-compose.yaml"
    local COMPOSE_FILE_LOCAL="$COMPOSE_CACHE_DIR/${SERVICE_NAME//\//_}-docker-compose.yaml"

    getFirstDbPortFree
    installLocalDb

    printf "\nInstalling '$SERVICE_NAME' on port '$DB_PORT'"

    if [ "$SERVICE_NAME" != "server" ] ; then
        printf "\nInstalling additional database for $SERVICE_NAME"
        local DATABASE_COMPOSE_LOCAL="$COMPOSE_CACHE_DIR/database-docker-compose.yaml"
        download_compose_file "database/docker-compose.yaml" "$DATABASE_COMPOSE_LOCAL" "Updating database compose"
        execute_command "$COMPOSE_CMD -f '$DATABASE_COMPOSE_LOCAL' up -d --build --remove-orphans --pull always"
    fi

    download_compose_file "$REMOTE_COMPOSE_PATH" "$COMPOSE_FILE_LOCAL" "Downloading compose for $SERVICE_NAME"

    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        printf "\nUpdating service: $SERVICE_NAME"
        download_compose_file "$REMOTE_COMPOSE_PATH" "$COMPOSE_FILE_LOCAL" "Refreshing compose for $SERVICE_NAME"
        execute_command "$COMPOSE_CMD -f '$COMPOSE_FILE_LOCAL' pull" \
            "Pulling latest images for $SERVICE_NAME" || return 1
        execute_command "$COMPOSE_CMD -f '$COMPOSE_FILE_LOCAL' down" \
            "Stopping and removing containers for $SERVICE_NAME" || return 1
        execute_command "docker image prune -f >/dev/null 2>&1" \
            "Pruning Docker images" || return 1
    fi

    execute_command "$COMPOSE_CMD -f '$COMPOSE_FILE_LOCAL' up -d --build --remove-orphans --pull always" \
        "Installing/updating service: $SERVICE_NAME" || return 1

    printf "\nInstallation/Update completed for $SERVICE_NAME."
    return 0
}

dockerInstall() {
    execute_command "apt-get update -y >/dev/null 2>&1" "Updating packages" || return 1
    execute_command "apt-get install -y apt-transport-https ca-certificates wget software-properties-common >/dev/null 2>&1" "Installing required packages" || return 1
    execute_command "wget --no-check-certificate -qO- https://download.docker.com/linux/ubuntu/gpg | apt-key add - >/dev/null 2>&1" "Adding Docker GPG key" || return 1
    execute_command "add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable' -y >/dev/null 2>&1" "Adding Docker repository" || return 1
    execute_command "apt-get update -y >/dev/null 2>&1 && apt-get install -y docker-ce >/dev/null 2>&1" "Installing Docker" || return 1
    return 0
}

# ... (rest of the script remains identical) ...
# Including show_menu, get_config, dockerNuke, etc.



show_menu() {
    local mode=$1
if [ "$mode" == "install" ]; then        
    echo ""
    echo ""
    echo -e "${WHITE}"
    echo "  ┌───────────────────────────────────────────────────────────┐"
    echo "  │               uSee Service suite | Installation           │"
    echo "  └───────────────────────────────────────────────────────────┘"
    echo -e "  ${NC}"
    echo -e "  ${GREEN}INSTALL NEW:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  1. ${GREEN}Suite${NC}"
    echo -e "  ${CYAN}  │${NC}  2. ${GREEN}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  3. ${GREEN}ID Verifier{NC}"
    echo -e "  ${CYAN}  │${NC}  4. ${GREEN}Event Manager{NC}"
    echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC}  6. ${GREEN}Thumbnail Engine${NC}"

    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Event Manager${NC}"
    echo -e "  ${CYAN}  │${NC} 10. ${BLUE}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${BLUE}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${YELLOW}UTILITY OPTIONS:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC} 99. ${RED}Clean everything (remove all containers and db)${NC}"
    echo -e "  ${CYAN}  │${NC}  0. ${WHITE}EXIT${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo -e "${WHITE}"
    echo "  ┌───────────────────────────────────────────────────────────┐"
    echo "  |          uSee Service suite | Manage installation         │"
    echo "  └───────────────────────────────────────────────────────────┘"
    echo -e "  ${NC}"
    echo -e "  ${GREEN}ADD NEW SERVICES:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"    
    echo -e "  ${CYAN}  │${NC}  2. ${GREEN}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  3. ${GREEN}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC}  4. ${GREEN}Event Manager${NC}"
    echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC}  6. ${GREEN}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${GREEN}Recording${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}All the Service Suite${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  10. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${BLUE}Event Manager${NC}"
    echo -e "  ${CYAN}  │${NC} 12. ${BLUE}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC} 13. ${BLUE}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC} 14. ${BLUE}Recording${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${YELLOW}UTILITY OPTIONS:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC} 99. ${RED}Clean everything (remove all containers and db)${NC}"
    echo -e "  ${CYAN}  │${NC}  0. ${WHITE}EXIT${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo ""
fi
}

getFirstDbPortFree() {
    local DEFAULT_PORT=27017
    local MAX_TRIES=100
    local attempt=0

    # Se DB_PORT non è settata, iniziamo dalla default
    if [ -z "$DB_PORT" ]; then
        DB_PORT=$DEFAULT_PORT
    fi

    while [ $attempt -lt $MAX_TRIES ]; do
        if ss -ltnp | grep ":$DB_PORT " > /dev/null 2>&1; then
            # Porta occupata, proviamo la prossima
            echo "Port $DB_PORT is in use."
            DB_PORT=$((DB_PORT + 1))
            attempt=$((attempt + 1))
        else
            # Porta libera
            export DB_PORT
            echo "Using port $DB_PORT for the database."
            return 0
        fi
    done

    echo "No free port found after $MAX_TRIES attempts!"
    return 1
}






get_config() {


    if [ "$HYPERNODE_ALREADY_INSTALLED" != "true" ]; then
    
        show_menu "install"

    else
        show_menu "update"
        
    fi

 
    if [ "$FORCE_INSTALL" == "true" ]; then
        printf "\nForce install mode enabled. Skipping menu.\n"
    else
        read -p "Enter the option: " INSTALL_OPTION
        INSTALL_OPTION=${INSTALL_OPTION:-1}
    fi

    printf "\nYou selected option: $INSTALL_OPTION\n"



    case $INSTALL_OPTION in
    1 | 8)
    
        # Install the complete suite (Gateway Mode)

        RMQ="amqp://hypernode:hypernode@messagebroker:5672"
        export DB_NAME='USS_SERVER'
        export RMQ

        ;;
    2 | 3 | 4 | 5 | 6 | 7)
       

        if [ "$FORCE_INSTALL" == "false" ]; then
            # Install single services (Runner Mode)
            read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud:443): " remote_host
            read -p "Type the service name to update: " PROCESS_NAME

        fi

        REMOTE_GATEWAY_URL="$remote_host"
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://hypernode:hypernode@$remote_host"
        export GRI="wss://$remote_host"
        printf "\nGateway set as $remote_host"
        printf "\nPROCESS_NAME set as $PROCESS_NAME"
        printf "\nDB_NAME set as $DB_NAME"
        printf "\nDATABASE_URI set as $DATABASE_URI"
        printf "\nRMQ set as $RMQ"
        printf "\nGRI set as $GRI"

        if [ "$FORCE_INSTALL" == "false" ]; then
            read -p $'\nPress enter to continue ...'
        fi
        ;;

      8 | 9 | 10 | 11 | 12)

        # Update single services (Runner Mode)
        read -p "Type the service name to update: " PROCESS_NAME
        read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud:443): " remote_host
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://hypernode:hypernode@$remote_host"
        export GRI="wss://$remote_host"

        printf "\nGateway set as $remote_host"
        printf "\nPROCESS_NAME set as $PROCESS_NAME"
        printf "\nDB_NAME set as $DB_NAME"
        printf "\nDATABASE_URI set as $DATABASE_URI"
        printf "\nRMQ set as $RMQ"
        printf "\nGRI set as $GRI"

        if [ "$FORCE_INSTALL" == "false" ]; then
            read -p $'\nPress enter to continue ...'
        fi
        
        ;;  
        
    99)
        ;;
    0)
        printf "\nExiting."
        exit 0
        ;;
    *)
        printf "\nOption unavailable."
        exit 1
        ;;
    esac

    export INSTALL_OPTION

    printf "\nINSTALL_OPTION: $INSTALL_OPTION"


}


dockerNuke() {
    printf "\nAre you sure you want to stop and remove all containers, images, networks, and volumes? (y/n) \n\n[there's no going back]"
    read -r confirmation

    if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
        printf "\nStopping and removing all containers, images, networks, and volumes...\n"

        # Stop containers
        execute_command "docker stop \$(docker ps -q) >/dev/null 2>&1" \
            "Stopping containers" || return 1

        # Remove containers
        execute_command "docker rm -f \$(docker ps -aq) >/dev/null 2>&1" \
            "Removing containers" || return 1

        # Remove images
        execute_command "docker rmi -f \$(docker images -q) >/dev/null 2>&1" \
            "Removing Docker images" || return 1

        # Rimuove tutti i volumi manualmente
        execute_command "docker volume ls -q | xargs -r docker volume rm" \
            "Removing Docker volumes" || return 1

        # Esegue il prune finale (opzionale)
        execute_command "docker system prune -a --volumes -f" \
            "Pruning Docker system" || return 1

        end_with_message "Docker cleanup completed successfully" 0
    else
        printf "\nOperation canceled.\n"
        return 1
    fi
}


checkIfHypernodeIsInstalled() {
    local container_name="gateway"

    if docker ps | grep -qw "$container_name"; then
        HYPERNODE_ALREADY_INSTALLED="true"
    else
        printf "\nNo Suite Manager detected. \nInstall the complete suite (Gateway Mode) or single services. (Runner Mode)\n"
        HYPERNODE_ALREADY_INSTALLED="false"
    fi
}


check_docker_installed() {
    if ! command -v docker &> /dev/null; then       
        DOCKER_ALREADY_INSTALLED="false"
    else
        DOCKER_ALREADY_INSTALLED="true"
    fi
}


# detectSudo(){
    
#     if [ "$EUID" -ne 0 ]; then
#         printf "\nThis script is not running as root/sudo.\n" 
#         exit 1
#     fi
# }

detectDockerCompose(){
    # Step 2: Check if 'docker compose' (plugin) or 'docker-compose' (legacy) is available
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        printf "❌ Neither 'docker compose' nor 'docker-compose' found. Please install the required tool.\n"
        exit 1
    fi

}

# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step

#clear

#detectSudo
detectDockerCompose
check_docker_installed # Check if docker is installed
checkIfHypernodeIsInstalled # Check if hypernode is already installed
get_config # Get the configuration from the user
clear



if [ "$DOCKER_ALREADY_INSTALLED" != "true" ]; then
 
   dockerInstall

fi


if [ "$INSTALL_OPTION" -eq 1 ]; then    
    additionalServiceInstall "server" && end_with_message "Server installation" 0 || end_with_message "Server installation" 1
elif [ "$INSTALL_OPTION" -eq 2 ]; then
    additionalServiceInstall "camera" && end_with_message "Camera service installation" 0 || end_with_message "Camera service installation" 1
elif [ "$INSTALL_OPTION" -eq 3 ]; then
    additionalServiceInstall "auth" && end_with_message "Auth service installation" 0 || end_with_message "Auth service installation" 1
elif [ "$INSTALL_OPTION" -eq 4 ]; then
    additionalServiceInstall "event" && end_with_message "Event service installation" 0 || end_with_message "Event service installation" 1
elif [ "$INSTALL_OPTION" -eq 5 ]; then
    additionalServiceInstall "storage" && end_with_message "Storage service installation" 0 || end_with_message "Storage service installation" 1
elif [ "$INSTALL_OPTION" -eq 6 ]; then
    additionalServiceInstall "snapshot" && end_with_message "Snapshot service installation" 0 || end_with_message "Snapshot service installation" 1
elif [ "$INSTALL_OPTION" -eq 7 ]; then
    additionalServiceInstall "recording" && end_with_message "Recording service installation" 0 || end_with_message "Recording service installation" 1
elif [ "$INSTALL_OPTION" -eq 8 ]; then
    additionalServiceInstall "server" "update" && end_with_message "Server update" 0 || end_with_message "Server update" 1
elif [ "$INSTALL_OPTION" -eq 9 ]; then
    additionalServiceInstall "camera" "update" && end_with_message "Camera service update" 0 || end_with_message "Camera service update" 1
elif [ "$INSTALL_OPTION" -eq 10 ]; then
    additionalServiceInstall "auth" "update" && end_with_message "Auth service update" 0 || end_with_message "Auth service update" 1
elif [ "$INSTALL_OPTION" -eq 11 ]; then
    additionalServiceInstall "event" "update" && end_with_message "Event service update" 0 || end_with_message "Event service update" 1
elif [ "$INSTALL_OPTION" -eq 12 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Storage service update" 0 || end_with_message "Storage service update" 1
elif [ "$INSTALL_OPTION" -eq 13 ]; then
    additionalServiceInstall "snapshot" "update" && end_with_message "Snapshot service update" 0 || end_with_message "Snapshot service update" 1
elif [ "$INSTALL_OPTION" -eq 99 ]; then
    dockerNuke && end_with_message "Cleanup" 0 || end_with_message "Cleanup" 1
fi
