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
SERVER_BRANCH="main"
CONFIGURATOR_BRANCH="main"

HYPERNODE_ALREADY_INSTALLED="false"
DOCKER_ALREADY_INSTALLED="false";

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
                                                                                                    
                                                                                                    
    +++++++++++++ ++++++++  ++ ++++++++ +++++++ ++  ++ ++ ++++++++ +++++ +++++ ++++++++ ++++ ++     
    ++++++++ +++++++++++++++++  +++++++++ +++ ++++  +++++++++++ +++++++++++++++++++++++++ ++  +     
                                                                                                    
EOF
}

# Mostra l'arte ASCII prima di qualsiasi altra cosa
show_ascii_art



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



end_with_message() {
    local message=$1
    local success=$2

    # Porta la progress bar al 100%
    show_progress "$TOTAL_STEPS" "$TOTAL_STEPS"

    if [ "$success" -eq 0 ]; then
        printf "\n🎉 %s: Operation completed successfully!\n\n" "$message"
    else
        printf "\n❌ %s: Operation failed. Please check the logs.\n\n" "$message"
        exit 1
    fi

    # Cancella eventuali barre di progresso extra
    printf "\r\033[K"
}


additionalServiceInstall() {
    local SERVICE_NAME=$1
    local TYPE_OF_INSTALL=${2:-"install"} # Default a "install" se non specificato

    printf "\nSERVICE_NAME: $SERVICE_NAME"

    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        printf "\nUpdating service: $SERVICE_NAME"

        # Stop e rimuove i container esistenti
        execute_with_spinner "docker compose -f \"$ABSOLUTE_PATH/hypernode/hypernode_deploy/dockerService/$SERVICE_NAME/docker-compose.yaml\" down" \
            "Stopping and removing containers for $SERVICE_NAME" || return 1

        # Pulizia delle immagini obsolete
        execute_with_spinner "docker image prune -f >/dev/null 2>&1" \
            "Pruning Docker images" || return 1
    fi

    # Installazione o aggiornamento
    execute_with_spinner "docker compose -f \"$ABSOLUTE_PATH/hypernode/hypernode_deploy/dockerService/$SERVICE_NAME/docker-compose.yaml\" up -d --build" \
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

    # local usr=mdalprato
    # local psw=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
    local usr=LucaArteco
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




get_config() {


    if [ "$HYPERNODE_ALREADY_INSTALLED" != "true" ]; then
    
        # Menu delle opzioni
        echo ""
        echo "-------------------------------------:"
        echo "-------------- INSTALL  -------------:"
        echo "-------------------------------------:"
        echo ""
        echo "What do you want to install:"
        echo "|-- 1. Server [auth,camera,storage,event,gateway] "    
        echo "|-- 2. Camera Service"
        echo "|-- 3. Auth Service"
        echo "|-- 4. Event Service"
        echo "|-- 5. Storage Service"
        echo ""
        echo "-------------------------------------:"
        echo "-------------- UPDATE  --------------:"
        echo "-------------------------------------:"
        echo ""
        echo "What do you want to update:"
        echo "|-- 7. Camera Service"
        echo "|-- 8. Auth Service"
        echo "|-- 9. Event Service"
        echo "|-- 10. Storage Service"
        echo ""
        echo "0. EXIT"
        echo ""

    else

        # Menu delle opzioni
        echo ""
        echo "-------------------------------------:"
        echo "-------------- INSTALL  -------------:"
        echo "-------------------------------------:"
        echo ""
        echo "What do you want to install:"
        echo "|-- 2. Camera Service"
        echo "|-- 3. Auth Service"
        echo "|-- 4. Event Service"
        echo "|-- 5. Storage Service"
        echo ""
        echo "-------------------------------------:"
        echo "-------------- UPDATE  --------------:"
        echo "-------------------------------------:"
        echo ""
        echo "What do you want to update:"
        echo "|-- 6. Update all the server's servicies "    
        echo "|-- 7. Update Camera Service"
        echo "|-- 8. Update Auth Service"
        echo "|-- 9. Update Event Service"
        echo "|-- 10. Update Storage Service"
        echo ""
        echo "-------------------------------------:"
        echo "------------- UTILITIES  ------------:"
        echo "-------------------------------------:"
        echo "|-- 11. Clean everything (remove all containers and db)"
        echo ""
        echo "0. EXIT"
        echo ""

       
    fi

 
    # Lettura della scelta dell'utente
    read -p "Enter the option: " INSTALL_OPTION
    INSTALL_OPTION=${INSTALL_OPTION:-1}


     # Esecuzione dell'azione in base alla option
    case $INSTALL_OPTION in
    1 | 6)
        read -p "HTTP server port (default 80): " SERVER_PORT
        SERVER_PORT=${SERVER_PORT:-80}

        read -p "HTTPS server port (default 443): " SSL_PORT
        SSL_PORT=${SSL_PORT:-443}

        read -p "Configurator port (default 8080): " CONF_PORT
        CONF_PORT=${CONF_PORT:-8080}

        read -p "| --> Server branch (default is 'main') " SERVER_BRANCH
        SERVER_BRANCH=${SERVER_BRANCH:-main}

        read -p "| --> Web Configurator branch (default is 'main') " CONFIGURATOR_BRANCH
        CONFIGURATOR_BRANCH=${CONFIGURATOR_BRANCH:-main}

        RMQ=amqp://hypernode:hypernode@messageBroker:5672


        # Esporta le variabili per renderle accessibili ad altri script
        export SERVER_PORT
        export SSL_PORT
        export CONF_PORT
        export RMQ
        export SERVER_BRANCH
        export CONFIGURATOR_BRANCH        

        ;;
    2 | 3 | 4 | 5 )
       
        read -p "Choose a unique name (in case of update, type the current service name): " PROCESS_NAME

        read -p "| --> branch (default is 'main') " SERVER_BRANCH
        SERVER_BRANCH=${SERVER_BRANCH:-main}

        read -p "Is the main gateway local (l) o (r)remote ? [l/r]: " IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE

        # Imposta la variabile RABBITMQ_HOST in base alla scelta
        if [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "l" ] || [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "L" ]; then
            RABBITMQ_HOST_FOR_ADDITIONAL="172.17.0.1"
            printf "\nGateway set as local. Host: $RABBITMQ_HOST_FOR_ADDITIONAL"
        elif [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "r" ] || [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "R" ]; then
            read -p "Insert the ip/url: " remote_host
            RABBITMQ_HOST_FOR_ADDITIONAL="$remote_host"
            printf "\nGateway set as remote $RABBITMQ_HOST_FOR_ADDITIONAL"
        else
            printf "\nWrong choice mate."
            exit 1
        fi
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqp://hypernode:hypernode@$RABBITMQ_HOST_FOR_ADDITIONAL:5672"
        export SERVER_BRANCH
        export GATEWAY_REMOTE_IP=$RABBITMQ_HOST_FOR_ADDITIONAL

        ;;

     7 | 8 | 9 | 10)

        read -p "Type the service name to update: " PROCESS_NAME

        read -p "| --> branch (default is 'main') " SERVER_BRANCH
        SERVER_BRANCH=${SERVER_BRANCH:-main}

        read -p "Is the main gateway local (l) o (r)remote ? [l/r]: " IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE

        # Imposta la variabile RABBITMQ_HOST in base alla scelta
        if [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "l" ] || [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "L" ]; then
            RABBITMQ_HOST_FOR_ADDITIONAL="172.17.0.1"
            printf "\nGateway set as local. Host: $RABBITMQ_HOST_FOR_ADDITIONAL"
        elif [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "r" ] || [ "$IS_ADDITIONAL_SERVICE_RMQ_LOCAL_OR_REMOTE" == "R" ]; then
            read -p "Insert the ip/url: " remote_host
            RABBITMQ_HOST_FOR_ADDITIONAL="$remote_host"
            printf "\nGateway set as remote $RABBITMQ_HOST_FOR_ADDITIONAL"
        else
            printf "\nWrong choice mate."
            exit 1
        fi

        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqp://hypernode:hypernode@$RABBITMQ_HOST_FOR_ADDITIONAL:5672"
        export SERVER_BRANCH
        export GATEWAY_REMOTE_IP=$RABBITMQ_HOST_FOR_ADDITIONAL

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
        printf "\nWrong choice mate."
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

    printf "\nCleaning procedure completed successfully.\n"
}


dockerNuke() {
    printf "\nAre you sure you want to stop and remove all containers, images, networks, and volumes? (y/n) \n[there's no going back]"
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

        # Prune system
        execute_with_spinner "sudo docker system prune -a --volumes -f >/dev/null 2>&1" \
            "Pruning Docker system" || return 1

        end_with_message "Docker cleanup completed successfully" 0
    else
        printf "\nOperation canceled.\n"
        return 1
    fi
}



checkIfHypernodeIsInstaller() {
    local container_name="hypernode-server-gateway"

    # Usa grep per cercare direttamente il nome del container nei risultati di `docker ps`
    if sudo docker ps | grep -qw "$container_name"; then
        printf "\nServer is already installed."
        HYPERNODE_ALREADY_INSTALLED="true"
    else
        printf "\nNo server detected. You should install a new one (or some services)."
        HYPERNODE_ALREADY_INSTALLED="false"
    fi
}


check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        DOCKER_ALREADY_INSTALLED="true"
    else
        DOCKER_ALREADY_INSTALLED="false"
    fi
}



# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step

check_docker_installed # Check if docker is installed

checkIfHypernodeIsInstaller # Check if hypernode is already installed

get_config # Get the configuration from the user

clear # Clear the terminal

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
    additionalServiceInstall "server" "update" && end_with_message "Server update" 0 || end_with_message "Server update" 1
elif [ "$INSTALL_OPTION" -eq 7 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Storage service update" 0 || end_with_message "Storage service update" 1
elif [ "$INSTALL_OPTION" -eq 8 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Auth service update" 0 || end_with_message "Auth service update" 1
elif [ "$INSTALL_OPTION" -eq 9 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Event service update" 0 || end_with_message "Event service update" 1
elif [ "$INSTALL_OPTION" -eq 10 ]; then
    additionalServiceInstall "storage" "update" && end_with_message "Storage service update" 0 || end_with_message "Storage service update" 1
elif [ "$INSTALL_OPTION" -eq 11 ]; then
    dockerNuke && end_with_message "Cleanup" 0 || end_with_message "Cleanup" 1
fi


if [ "$SKIP_CLEAN" != "true" ]; then
    # server installation
    cleanProcedure
else
    printf "\nSkipping cleaning procedure"
fi