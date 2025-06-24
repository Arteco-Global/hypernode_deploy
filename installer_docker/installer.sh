#!/bin/bash

# Global vars
SCRIPT_DIR=$(dirname "$0") #local path
ABSOLUTE_PATH=$(realpath "$SCRIPT_DIR") #absolute path

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

# Default values for input parameters
SSL_PORT=443
DOCKER_TAG="latest"
FORCE_INSTALL="false"
DB_PORT=27017


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

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -fi|--foce-install)
            FORCE_INSTALL="true"
            shift
            ;;
        -p|--port)
            SSL_PORT="$2"
            shift 2
            ;;
        -tag|--tag)
            DOCKER_TAG="$2"
            shift 2
            ;;
     
        -h|--help) 
            echo "-port: setting the port for the server (default: 443)"
            echo "-tag: setting the docker tag (default: latest)"
            exit
            ;;
        *) 
            echo "Unknown parameter: $1"
            shift
            ;;
    esac
done

#printf "\nSSL_PORT set to: $SSL_PORT\n"
#printf "DOCKER_TAG set to: $DOCKER_TAG\n"

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

additionalServiceInstall() {
    local SERVICE_NAME=$1
    local TYPE_OF_INSTALL=${2:-"install"} 
    local COMPOSE_FILE="$ABSOLUTE_PATH/composes/$SERVICE_NAME/docker-compose.yaml"

    if [ "$SERVICE_NAME" != "server" ] ; then
    #se non è il server, allora devo controllare se il database è già attivo, nel caso crearlo oppure usare quello esistente
    
        checkIfDbPortIsUsed
        if [ $? -eq 0 ]; then
            printf "\nUsing default database for $SERVICE_NAME"
            DB_PORT=27017
        else
            printf "\nInstalling additional database for $SERVICE_NAME"
            execute_command "$COMPOSE_CMD -f \""$ABSOLUTE_PATH/composes/database/docker-compose.yaml"\" up -d --build --remove-orphans" 
            DB_PORT=27017
        fi
        
        export DB_PORT

    fi

 
    #fai le altre qui !!

    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        printf "\nUpdating service: $SERVICE_NAME"

        execute_command "$COMPOSE_CMD -f \"$COMPOSE_FILE\" pull" \
            "Pulling latest images for $SERVICE_NAME" || return 1

        execute_command "$COMPOSE_CMD -f \"$COMPOSE_FILE\" down" \
            "Stopping and removing containers for $SERVICE_NAME" || return 1

        execute_command "docker image prune -f >/dev/null 2>&1" \
            "Pruning Docker images" || return 1
    fi

    execute_command "$COMPOSE_CMD -f \"$COMPOSE_FILE\" up -d --build --remove-orphans" \
        "Installing/updating service: $SERVICE_NAME" || return 1

    printf "\nInstallation/Update completed for $SERVICE_NAME."

    return 0
}



dockerInstall() {

    # Step 1: Update packages
    execute_command "apt-get update -y >/dev/null 2>&1" "Updating packages" || return 1

    # Step 2: Install required packages
    execute_command "apt-get install -y apt-transport-https ca-certificates curl software-properties-common >/dev/null 2>&1" "Installing required packages" || return 1

    # Step 3: Add Docker GPG key
    execute_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - >/dev/null 2>&1" "Adding Docker GPG key" || return 1

    # Step 4: Add Docker repository
    execute_command "add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable' -y >/dev/null 2>&1" "Adding Docker repository" || return 1

    # Step 5: Install Docker
    execute_command "apt-get update -y >/dev/null 2>&1 &&  apt-get install -y docker-ce >/dev/null 2>&1" "Installing Docker" || return 1


    return 0
}


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

checkIfDbPortIsUsed() {
  
    if lsof -i :$DB_PORT > /dev/null; then
        # deb già attivo, inutile aggiungerne uno
        echo "Port used, using default database !"
        return 0;
    else
        ### Installing Database 
        echo "Port $DB_PORT is not in use, proceeding with database installation."
        return 1;

    fi
}

get_config() {


    if [ "$HYPERNODE_ALREADY_INSTALLED" != "true" ]; then
    
        show_menu "install"

    else
        show_menu "update"
        
    fi

 
    if [ "$FORCE_INSTALL" == "true" ]; then
        printf "\nForce install mode enabled. Skipping menu.\n"
        INSTALL_OPTION=1
    else
        read -p "Enter the option: " INSTALL_OPTION
        INSTALL_OPTION=${INSTALL_OPTION:-1}
    fi

    case $INSTALL_OPTION in
    1 | 8)
    
        # Install the complete suite (Gateway Mode)

        RMQ="amqp://hypernode:hypernode@messagebroker:5672"
        export RMQ

        ;;
    2 | 3 | 4 | 5 | 6 | 7)
       
        # Install single services (Runner Mode)
        read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud): " remote_host
        read -p "Insert uSee Gateway port (default 443): " remote_host_port


        REMOTE_GATEWAY_URL="$remote_host"
        REMOTE_GATEWAY_PORT=${remote_host_port:-443}

        printf "\nGateway set as $REMOTE_GATEWAY_URL"

        PROCESS_NAME=$(od -A n -N4 -t x1 /dev/urandom | tr -d ' \n')
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://hypernode:hypernode@$REMOTE_GATEWAY_URL:$REMOTE_GATEWAY_PORT"
        export GRI="wss://$REMOTE_GATEWAY_URL:$REMOTE_GATEWAY_PORT"


        ;;

      8 | 9 | 10 | 11 | 12)

        # Update single services (Runner Mode)
        read -p "Type the service name to update: " PROCESS_NAME
        read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud): " remote_host
        read -p "Insert uSee Gateway port (default 443): " remote_host_port

        REMOTE_GATEWAY_URL="$remote_host"
        REMOTE_GATEWAY_PORT=${remote_host_port:-443}

        printf "\nGateway set as $REMOTE_GATEWAY_URL"
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://hypernode:hypernode@$REMOTE_GATEWAY_URL:$REMOTE_GATEWAY_PORT"
        export GRI="wss://$REMOTE_GATEWAY_URL:$REMOTE_GATEWAY_PORT"

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


detectSudo(){
    
    if [ "$EUID" -ne 0 ]; then
        printf "\nThis script is not running as root/sudo.\n" 
        exit 1
    fi
}

detectDockerCompose(){

    # Step 2: Check if docker-compose command or docker compose command is available
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    elif command -v docker &> /dev/null && docker --version | grep -q "Docker"; then
        # Check if 'docker compose' (the plugin) is available
        COMPOSE_CMD="docker compose"
    else
        printf "❌ Neither 'docker-compose' nor 'docker compose' found. Please install the required tool.\n"
        exit 1
    fi

}

# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step

#clear

detectSudo
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
