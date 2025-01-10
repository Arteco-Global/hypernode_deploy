#!/bin/bash

# Global vars
TOTAL_STEPS=13 #Steps for progressbar
CURRENT_STEP=0 #Counter for progressbar
SPINNER_ACTIVE=true
SPINNER_PID=""
SCRIPT_DIR=$(dirname "$0") #local path
ABSOLUTE_PATH=$(realpath "$SCRIPT_DIR") #absolute path

SKIP_CLEAN="false"
SKIP_DOCKER_INSTALL="false"
SKIP_GIT_INSTALL="false"
SKIP_GIT_CLONE="false"
SKIP_BRANCH_ASK="false"
SERVER_BRANCH="main"
CONFIGURATOR_BRANCH="main"
ERASE_DB="false"

HYPERNODE_ALREADY_INSTALLED="false"
DOCKER_ALREADY_INSTALLED="false";

# Codici colore ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m' # Reset colore

# Funzione per lo spinner animato
start_spinner() {
    local SPINNER=("|" "/" "-" "\\")
    (
        while $SPINNER_ACTIVE; do
            for c in "${SPINNER[@]}"; do
                printf "\r["
                for ((i = 0; i < CURRENT_COMPLETED; i++)); do
                    printf "#"
                done
                printf "$c"
                for ((i = 0; i < CURRENT_REMAINING; i++)); do
                    printf "-"
                done
                printf "] %d%%" "$CURRENT_PERCENTAGE"
                sleep 0.1
            done
        done
    ) &
    SPINNER_PID=$!
}

# Ferma lo spinner
stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        SPINNER_ACTIVE=false
        kill "$SPINNER_PID" >/dev/null 2>&1
        wait "$SPINNER_PID" 2>/dev/null
        printf "\r\033[K" # Cancella la linea
        SPINNER_PID=""
    fi
}

# Aggiorna la barra di avanzamento
update_progress() {
    local -r BAR_WIDTH=50
    CURRENT_PERCENTAGE=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    CURRENT_COMPLETED=$((CURRENT_STEP * (BAR_WIDTH - 1) / TOTAL_STEPS))
    CURRENT_REMAINING=$((BAR_WIDTH - 1 - CURRENT_COMPLETED))
    CURRENT_STEP=$((CURRENT_STEP + 1))
}

# Funzione per eseguire operazioni con lo spinner
execute_with_spinner() {
    local COMMAND=$1
    local MESSAGE=$2
    local ERROR_LOG="/tmp/command_error.log"

    # Stampa il comando per debug
    # echo "Executing command: $COMMAND"

    # Inizializza lo spinner
    SPINNER_ACTIVE=true
    (
        local SPINNER=("|" "/" "-" "\\")
        while $SPINNER_ACTIVE; do
            for c in "${SPINNER[@]}"; do
                printf "\r%s %s %s" "$c" "$MESSAGE" # Spinner + Messaggio
                sleep 0.1
            done
        done
    ) &
    local SPINNER_PID=$!

    # Esegui il comando e cattura il risultato
    eval "$COMMAND" >/dev/null 2>"$ERROR_LOG"
    local COMMAND_STATUS=$?

    # Ferma lo spinner
    SPINNER_ACTIVE=false
    kill "$SPINNER_PID" >/dev/null 2>&1
    wait "$SPINNER_PID" 2>/dev/null

    # Stampa il risultato
    if [ $COMMAND_STATUS -eq 0 ]; then
        printf "\r✅ %s - Done.\n" "$MESSAGE"
    else
        printf "\r❌ %s - Failed.\n" "$MESSAGE"
        printf "\nError log:\n"
        cat "$ERROR_LOG"
        exit 1
    fi

    # Rimuovi il file temporaneo
    rm -f "$ERROR_LOG"
}



printf "\nInstaller version v1.0.0\n"


while [[ "$#" -gt 0 ]]; do
    case $1 in
        -erase-db) 
            echo "got -erase-db parameter!"
            ERASE_DB="true"
            ;;
        -skip-branch-ask) 
            echo "got -skip-branch-ask parameter!"
            SKIP_BRANCH_ASK="true"
            ;;
        -skip-clean) 
            echo "got -skip-clean parameter!"
            SKIP_CLEAN="true"
            ;;
        -skip-docker-install) 
            echo "got skip-docker-install!"
            SKIP_DOCKER_INSTALL="true"
            ;;

        -skip-git-install) 
            echo "got skip-git-install!"
            SKIP_GIT_INSTALL="true"
            ;;
        -skip-clone) 
            echo "got skip-clone!"
            SKIP_GIT_CLONE="true"
            ;;
        -help) 
            echo "-skip-clean: skip cleaning procedure"
            echo "-skip-docker-install: skip docker installation"
            echo "-skip-git-install: skip git installation"
            echo "-skip-clone: skip git clone"
            exit
            ;;
        *) 
            echo "Unkwnon parameter: $1"
            ;;
    esac
    shift
done

# Funzione per mostrare l'arte ASCII
show_ascii_art() {
    cat << "EOF"
                                                                                                    
                                  #############                                                     
                               ##################                                                   
                             ######################                                                 
                            ########################                                                
    +++           ++++     ######%%%##########              +++++++++++          ++++++++++++       
    ++++         +++++     ####%%%%##############         +++++++++++++++      ++++++++++++++++     
    ++++         +++++     ##%%%%%################       +++++        ++++    +++++        +++++    
    ++++         +++++     %%%%%%%#################     +++++          ++++  +++++          ++++    
    ++++         +++++     %%%%%%%%%       #########    +++++++++++++++++++  ++++++++++++++++++++   
    ++++         +++++      %%%%%%%%%%%%%%%%########    +++++++++++++++++++  +++++++++++++++++++    
    ++++         +++++       %%%%%%%%%%%%%%%%#######    +++++                 ++++                  
    ++++++     ++++++         %%%%%%%%%%%%%%%#######     ++++++       +++     ++++++       +++      
     ++++++++++++++             %%%%%%%%%%%#########       +++++++++++++++      +++++++++++++++     
       ++++++++++          ########################          ++++++++++            +++++++++        
                            ######################                                                  
                             ####################                                                   
                                ##############                                                      
                                     ####                                                           
                                                                                                    
                                                                                                    
    +++++++++++++++ ++++++++  ++ ++++++++ +++++++ ++  ++ ++ ++++++++ +++++ +++++ ++++++++ ++++ ++     

       _____                 _             _____       _ _         _____           _        _ _ 
      / ____|               (_)           / ____|     (_) |       |_   _|         | |      | | |
     | (___   ___ _ ____   ___  ___ ___  | (___  _   _ _| |_ ___    | |  _ __  ___| |_ __ _| | |
      \___ \ / _ \ '__\ \ / / |/ __/ _ \  \___ \| | | | | __/ _ \   | | | '_ \/ __| __/ _` | | |
      ____) |  __/ |   \ V /| | (_|  __/  ____) | |_| | | ||  __/  _| |_| | | \__ \ || (_| | | |
     |_____/ \___|_|    \_/ |_|\___\___| |_____/ \__,_|_|\__\___| |_____|_| |_|___/\__\__,_|_|_|
                                                                                                
                                                                                                

    ++++++++ +++++++++++++++++  +++++++++ +++ ++++  +++++++++++ +++++++++++++++++++++++++ ++  ++++     
                                                                                                    
EOF
}

show_progress() {
    local -r TOTAL_STEPS=$1
    local -r CURRENT_STEP=$2
    local -r BAR_WIDTH=50    

    # Assicurati che CURRENT_STEP non superi TOTAL_STEPS
    local STEPS_TO_SHOW=$((CURRENT_STEP > TOTAL_STEPS ? TOTAL_STEPS : CURRENT_STEP))

    local COMPLETED=$((STEPS_TO_SHOW * (BAR_WIDTH - 1) / TOTAL_STEPS)) # -1 per lasciare spazio allo spinner
    local REMAINING=$((BAR_WIDTH - 1 - COMPLETED))

    # Stampa la barra di progresso
    printf "\r["
    for ((i=0; i<COMPLETED; i++)); do
        printf "#"
    done

    for ((i=0; i<REMAINING; i++)); do
        printf "-"
    done

    # Percentuale
    printf "] %d%%" $((STEPS_TO_SHOW * 100 / TOTAL_STEPS))

    # Se il processo è completo, vai a capo
    if [ "$STEPS_TO_SHOW" -ge "$TOTAL_STEPS" ]; then
        printf "\n"
    fi
}

get_my_local_ip() {
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        echo "127.0.0.1"  # Fallback all'indirizzo localhost
    else
        echo "$ip"
    fi
}

end_with_message() {
    local message=$1
    local success=$2
    local myIp=$(get_my_local_ip)

    # Porta la progress bar al 100%
    show_progress "$TOTAL_STEPS" "$TOTAL_STEPS"

    # Cancella eventuali barre di progresso extra
    printf "\r\033[K"

    if [ "$success" -eq 0 ]; then
        printf "\n🎉 %s: Operation completed successfully!\n\n" "$message"

        if [[ "$message" == "Server installation" || "$message" == "Server update" ]]; then
            printf "\n You can now access the uSee Configurator at http://$myIp:$SSL_PORT\n"
        fi
    else
        printf "\n❌ %s: Operation failed. Please check the logs.\n\n" "$message"
        exit 1
    fi
}

drop_server_collection() {
    printf "\nRe-initializing server DB...\n"

    # Nome del container MongoDB
    local MONGO_CONTAINER_NAME="database"

    # Comando per droppare la collezione 'server' nel database 'gateway-db'
    docker exec "$MONGO_CONTAINER_NAME" mongo gateway-db --eval "
        db.server.drop();
    "

    # Verifica il risultato del comando
    if [ $? -eq 0 ]; then
        printf "\n✅ The 'server' collection has been successfully dropped from the 'gateway-db' database.\n"
    else
        printf "\n❌ Failed to drop the 'server' collection. Please check the container or database status.\n"
    fi
}

additionalServiceInstall() {
    local SERVICE_NAME=$1
    local TYPE_OF_INSTALL=${2:-"install"} # Default a "install" se non specificato

    printf "\nSERVICE_NAME: $SERVICE_NAME"

    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        printf "\nUpdating service: $SERVICE_NAME"

        # Stop e rimuove i container esistenti
        execute_with_spinner "docker compose -f \"$ABSOLUTE_PATH/hypernode/hypernode_deploy/installer_github/dockerService/$SERVICE_NAME/docker-compose.yaml\" down" \
            "Stopping and removing containers for $SERVICE_NAME" || return 1

        # Pulizia delle immagini obsolete
        execute_with_spinner "docker image prune -f >/dev/null 2>&1" \
            "Pruning Docker images" || return 1
    fi

    # Installazione o aggiornamento
    # printenv

    execute_with_spinner "docker compose -f \"$ABSOLUTE_PATH/hypernode/hypernode_deploy/installer_github/dockerService/$SERVICE_NAME/docker-compose.yaml\" up -d --build --remove-orphans" \
        "Installing/updating service: $SERVICE_NAME" || return 1

    printf "\nInstallation/Update completed for $SERVICE_NAME."

    return 0
}



dockerInstall() {
    printf "\nInstalling Docker..."

    # Step 1: Update packages
    execute_with_spinner "sudo apt-get update -y >/dev/null 2>&1" "Updating packages" || return 1

    # Step 2: Install required packages
    execute_with_spinner "sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common >/dev/null 2>&1" "Installing required packages" || return 1

    # Step 3: Add Docker GPG key
    execute_with_spinner "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1" "Adding Docker GPG key" || return 1

    # Step 4: Add Docker repository
    execute_with_spinner "sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable' -y >/dev/null 2>&1" "Adding Docker repository" || return 1

    # Step 5: Install Docker
    execute_with_spinner "sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y docker-ce >/dev/null 2>&1" "Installing Docker" || return 1

    return 0
}


installGit() {
    printf "\nInstalling Git..."

    # Step 1: Update packages
    execute_with_spinner "sudo apt update >/dev/null 2>&1" "Updating packages for Git installation" || return 1

    # Step 2: Install Git
    execute_with_spinner "sudo apt install -y git >/dev/null 2>&1" "Installing Git" || return 1

    return 0
}



cloningCode() {
    printf "\nCloning repositories from GitHub..."

    local usr=mdalprato
    local psw=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

    # Step 0: Verifica se la cartella esiste e, se necessario, la rimuove
    if [ -d "$ABSOLUTE_PATH/hypernode" ]; then
        printf "Directory 'hypernode' already exists. Removing it...\n"
        rm -rf "$ABSOLUTE_PATH/hypernode"
        if [ $? -ne 0 ]; then
            printf "\n❌ Failed to remove existing 'hypernode' directory.\n"
            return 1
        fi
    fi

    # Step 1: Creazione della cartella per il clone
    execute_with_spinner "mkdir -p \"$ABSOLUTE_PATH/hypernode\"" "Creating folder for cloning" || return 1

    # Step 2: Entrare nella cartella
    execute_with_spinner "cd \"$ABSOLUTE_PATH/hypernode\"" "Accessing the folder" || return 1

    # Step 3: Clonare i repository
    execute_with_spinner "git clone https://\"$usr\":\"$psw\"@github.com/Arteco-Global/hypernode_deploy.git" \
        "Cloning repository: hypernode_deploy" || return 1

    execute_with_spinner "git clone --quiet https://\"$usr\":\"$psw\"@github.com/Arteco-Global/hypernode_server_gui.git" \
        "Cloning repository: hypernode_server_gui" || return 1

    execute_with_spinner "git clone --quiet https://\"$usr\":\"$psw\"@github.com/Arteco-Global/hypernode-server.git" \
        "Cloning repository: hypernode-server" || return 1

    # Step 4: Checkout branch per configuratore
    execute_with_spinner "cd \"$ABSOLUTE_PATH/hypernode/hypernode_server_gui\" && git checkout \"${CONFIGURATOR_BRANCH}\"" \
        "Checking out branch '${CONFIGURATOR_BRANCH}' for hypernode_server_gui" || return 1

    # Step 5: Checkout branch per server
    execute_with_spinner "cd \"$ABSOLUTE_PATH/hypernode/hypernode-server\" && git checkout \"${SERVER_BRANCH}\"" \
        "Checking out branch '${SERVER_BRANCH}' for hypernode-server" || return 1

    printf "\nCloning and branch checkouts completed successfully."
    return 0
}

# Menu delle opzioni
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
    echo -e "  ${CYAN}  │${NC}  1. ${GREEN}Suite [Suite Manager, ID Verifier, Live Streamer, Media Recorder, Event Manager]${NC}"
    echo -e "  ${CYAN}  │${NC}  2. ${GREEN}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  3. ${GREEN}ID Verifier{NC}"
    echo -e "  ${CYAN}  │${NC}  4. ${GREEN}Event Manager{NC}"
    echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Media recorder${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Event Manager${NC}"
    echo -e "  ${CYAN}  │${NC} 10. ${BLUE}Media recorder${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${YELLOW}UTILITY OPTIONS:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${RED}Clean everything (remove all containers and db)${NC}"
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
    echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Media Recorder${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  6. ${BLUE}All the Service Suite${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Event Manager${NC}"
    echo -e "  ${CYAN}  │${NC} 10. ${BLUE}Media Recorder${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${YELLOW}UTILITY OPTIONS:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${RED}Clean everything (remove all containers and db)${NC}"
    echo -e "  ${CYAN}  │${NC}  0. ${WHITE}EXIT${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo ""
fi
}


get_config() {


    if [ "$HYPERNODE_ALREADY_INSTALLED" != "true" ]; then
    
        # Menu delle opzioni
        show_menu "install"

    else
        show_menu "update"
        
    fi

 
    # Lettura della scelta dell'utente
    read -p "Enter the option: " INSTALL_OPTION
    INSTALL_OPTION=${INSTALL_OPTION:-1}


     # Esecuzione dell'azione in base alla option
    case $INSTALL_OPTION in
    1 | 6)
  
        read -p "Server port (default 443): " SSL_PORT
        SSL_PORT=${SSL_PORT:-443}

        if [ "$SKIP_BRANCH_ASK" != "true" ]; then
            read -p "| --> Server branch (default is 'main') " SERVER_BRANCH
            SERVER_BRANCH=${SERVER_BRANCH:-main}

            read -p "| --> Web Configurator branch (default is 'main') " CONFIGURATOR_BRANCH
            CONFIGURATOR_BRANCH=${CONFIGURATOR_BRANCH:-main}
        fi
        

        RMQ=amqp://hypernode:hypernode@messagebroker:5672


        # Esporta le variabili per renderle accessibili ad altri script
        export SSL_PORT
        export RMQ
        export SERVER_BRANCH
        export CONFIGURATOR_BRANCH

        ;;
    2 | 3 | 4 | 5 )
       
        read -p "Choose a unique name (in case of update, type the current service name): " PROCESS_NAME

        if [ "$SKIP_BRANCH_ASK" != "true" ]; then
            read -p "| --> branch (default is 'main') " SERVER_BRANCH
            SERVER_BRANCH=${SERVER_BRANCH:-main}
        fi        

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

        #       // "env": {
        #       //   "RABBITMQ_URI": "amqps://hypernode:hypernode@V12230451.my.omniaweb.cloud:443",
        #       //   "GATEWAY_REMOTE_IP": "wss://V12230451.my.omniaweb.cloud:443",
        #       // }

        ;;

     7 | 8 | 9 | 10)

        read -p "Type the service name to update: " PROCESS_NAME

        if [ "$SKIP_BRANCH_ASK" != "true" ]; then
            read -p "| --> branch (default is 'main') " SERVER_BRANCH
            SERVER_BRANCH=${SERVER_BRANCH:-main}
        fi        

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

        #       // "env": {
        #       //   "RABBITMQ_URI": "amqps://hypernode:hypernode@V12230451.my.omniaweb.cloud:443",
        #       //   "GATEWAY_REMOTE_IP": "wss://V12230451.my.omniaweb.cloud:443",
        #       // }

        ;;  
        
    11)
        export SKIP_DOCKER_INSTALL=true
        export SKIP_GIT_INSTALL=true
        export SKIP_GIT_CLONE=true
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

cleanProcedure() {
    # *****************************************************************
    # CLEANING PROCEDURE **********************************************
    # *****************************************************************

    execute_with_spinner "rm -rf \"$ABSOLUTE_PATH/hypernode\" > /dev/null" \
        "Cleaning code" || return 1

    printf "\nCleaning procedure completed successfully.\n\n"
}


dockerNuke() {
    printf "\nAre you sure you want to stop and remove all containers, images, networks, and volumes? (y/n) \n\n[there's no going back]"
    read -r confirmation

    if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
        printf "\nStopping and removing all containers, images, networks, and volumes...\n"

        # Stop containers
        execute_with_spinner "sudo docker stop \$(sudo docker ps -q) >/dev/null 2>&1" \
            "Stopping containers" || return 1

        # Remove containers
        execute_with_spinner "sudo docker rm -f \$(sudo docker ps -aq) >/dev/null 2>&1" \
            "Removing containers" || return 1

        # Remove images
        execute_with_spinner "sudo docker rmi -f \$(sudo docker images -q) >/dev/null 2>&1" \
            "Removing Docker images" || return 1

        # Rimuove tutti i volumi manualmente
        execute_with_spinner "docker volume ls -q | xargs -r docker volume rm" \
            "Removing Docker volumes" || return 1

        # Esegue il prune finale (opzionale)
        execute_with_spinner "docker system prune -a --volumes -f" \
            "Pruning Docker system" || return 1

        end_with_message "Docker cleanup completed successfully" 0
    else
        printf "\nOperation canceled.\n"
        return 1
    fi
}



checkIfHypernodeIsInstalled() {
    local container_name="hypernode-server-gateway"

    # Usa grep per cercare direttamente il nome del container nei risultati di `docker ps`
    if sudo docker ps | grep -qw "$container_name"; then
        printf "\nSuite Manager detected. This is the uSee Gateway.\n"
        HYPERNODE_ALREADY_INSTALLED="true"
    else
        printf "\nNo Suite Manager detected. \nInstall the complete suite (Gateway Mode) or single services. (Runner Mode)\n"
        HYPERNODE_ALREADY_INSTALLED="false"
    fi
}


check_docker_installed() {
    if ! command -v docker &> /dev/null; then       
        printf "\nDocker is not installed.\n" 
        DOCKER_ALREADY_INSTALLED="false"
    else
        printf "\nDocker is already installed.\n"
        DOCKER_ALREADY_INSTALLED="true"
    fi
}



# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step
clear

show_ascii_art

check_docker_installed # Check if docker is installed

checkIfHypernodeIsInstalled # Check if hypernode is already installed

get_config # Get the configuration from the user

clear

show_ascii_art

printf "\n\nStarting installation...\n"


if [ "$SKIP_GIT_INSTALL" != "true" ]; then
    # git installation
    installGit
else
    printf "\nSkipping git install"
fi


if [ "$SKIP_DOCKER_INSTALL" != "true" ] || [ "$DOCKER_ALREADY_INSTALLED" != "true" ]; then
    # docker installation
    dockerInstall
else
    printf "\nSkipping docker install"
fi


if [ "$SKIP_GIT_CLONE" != "true" ]; then
    # d. Cloning code from github
    cloningCode
else
    printf "\nSkipping docker install"
fi

# echo "|-- 2. Additional Camera Service"
# echo "|-- 3. Additional Auth Service"
# echo "|-- 4. Additional Event Service"
# echo "|-- 5. Additional Storage Service"

# echo "|-- 6. Update all the server's servicies "    
# echo "|-- 7. Update Camera Service"
# echo "|-- 8. Update Auth Service"
# echo "|-- 9. Update Event Service"
# echo "|-- 10. Update Storage Service"
# echo "|-- 11. Clean everything (remove all containers and db)"

if [ "$INSTALL_OPTION" -eq 1 ]; then    
    if [ "$ERASE_DB" == "true" ]; then
        drop_server_collection
    fi
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
    if [ "$ERASE_DB" == "true" ]; then
        drop_server_collection
    fi
    additionalServiceInstall "server" "update" && end_with_message "Server update" 0 || end_with_message "Server update" 1
elif [ "$INSTALL_OPTION" -eq 7 ]; then
    additionalServiceInstall "camera" "update" && end_with_message "Camera service update" 0 || end_with_message "Camera service update" 1
elif [ "$INSTALL_OPTION" -eq 8 ]; then
    additionalServiceInstall "auth" "update" && end_with_message "Auth service update" 0 || end_with_message "Auth service update" 1
elif [ "$INSTALL_OPTION" -eq 9 ]; then
    additionalServiceInstall "event" "update" && end_with_message "Event service update" 0 || end_with_message "Event service update" 1
elif [ "$INSTALL_OPTION" -eq 10 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Storage service update" 0 || end_with_message "Storage service update" 1
elif [ "$INSTALL_OPTION" -eq 11 ]; then
    dockerNuke && end_with_message "Cleanup" 0 || end_with_message "Cleanup" 1
fi


if [ "$SKIP_CLEAN" != "true" ]; then
    # server installation
    cleanProcedure
else
    printf "\nSkipping cleaning procedure\n\n"
fi