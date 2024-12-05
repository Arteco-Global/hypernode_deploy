#!/bin/bash

# Global vars
TOTAL_STEPS=13 #Steps for progressbar
CURRENT_STEP=0 #Counter for progressbar
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
        if ! docker compose -f "$ABSOLUTE_PATH/hypernode/hypernode_deploy/dockerService/$SERVICE_NAME/docker-compose.yaml" down; then
            printf "\nError: Failed to stop and remove containers for $SERVICE_NAME."
            return 1
        fi

        # Pulizia delle immagini obsolete
        if ! docker image prune -f >/dev/null 2>&1; then
            printf "\nError: Failed to prune Docker images."
            return 1
        fi
    fi

    # Installazione o aggiornamento
    printf "\nInstalling/updating service: $SERVICE_NAME"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"

    if ! docker compose -f "$ABSOLUTE_PATH/hypernode/hypernode_deploy/dockerService/$SERVICE_NAME/docker-compose.yaml" up -d --build; then
        printf "\nError: Failed to build and start service $SERVICE_NAME."
        return 1
    fi

    printf "\nInstallation/Update completed for $SERVICE_NAME."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"

    return 0
}


dockerInstall() {
    printf "\nInstalling Docker..."

    # Step 1: Update packages
    printf "\nUpdating packages..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! sudo apt-get update -y >/dev/null 2>&1; then
        printf "\nError: Failed to update packages."
        return 1
    fi

    # Step 2: Install required packages
    printf "\nInstalling required packages..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common >/dev/null 2>&1; then
        printf "\nError: Failed to install required packages."
        return 1
    fi

    # Step 3: Add Docker GPG key
    printf "\nAdding Docker GPG key..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1; then
        printf "\nError: Failed to add Docker GPG key."
        return 1
    fi

    # Step 4: Add Docker repository
    printf "\nAdding Docker repository..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable" -y >/dev/null 2>&1; then
        printf "\nError: Failed to add Docker repository."
        return 1
    fi

    # Step 5: Install Docker
    printf "\nInstalling Docker..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! sudo apt-get update -y >/dev/null 2>&1 || ! sudo apt-get install -y docker-ce >/dev/null 2>&1; then
        printf "\nError: Failed to install Docker."
        return 1
    fi

    return 0
}


installGit() {
    printf "\nInstalling Git..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"

    if ! sudo apt update >/dev/null 2>&1 || ! sudo apt install -y git >/dev/null 2>&1; then
        printf "\nError: Failed to install Git."
        return 1
    fi

    return 0
}


cloningCode() {
    printf "\nCloning repositories from GitHub..."

    local usr=mdalprato
    local psw=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

    # Step 1: Creazione della cartella per il clone
    printf "\nCreating folder..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! mkdir -p "$ABSOLUTE_PATH/hypernode" >/dev/null 2>&1; then
        printf "\nError: Failed to create directory for cloning."
        return 1
    fi

    # Step 2: Entrare nella cartella
    printf "\nMoving inside folder..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! cd "$ABSOLUTE_PATH/hypernode" >/dev/null 2>&1; then
        printf "\nError: Failed to access the directory."
        return 1
    fi

    # Step 3: Clonare i repository
    printf "\nCloning repositories..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"

    if ! git clone --quiet https://"$usr":"$psw"@github.com/Arteco-Global/hypernode_deploy.git >/dev/null 2>&1; then
        printf "\nError: Failed to clone hypernode_deploy."
        return 1
    fi

    if ! git clone --quiet https://"$usr":"$psw"@github.com/Arteco-Global/hypernode_server_gui.git >/dev/null 2>&1; then
        printf "\nError: Failed to clone hypernode_server_gui."
        return 1
    fi

    if ! git clone --quiet https://"$usr":"$psw"@github.com/Arteco-Global/hypernode-server.git >/dev/null 2>&1; then
        printf "\nError: Failed to clone hypernode-server."
        return 1
    fi

    # Step 4: Checkout branch per configuratore
    printf "\nChecking out configurator branch..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! cd "$ABSOLUTE_PATH/hypernode/hypernode_server_gui" >/dev/null 2>&1 || ! git checkout "${CONFIGURATOR_BRANCH}" >/dev/null 2>&1; then
        printf "\nError: Failed to checkout branch '${CONFIGURATOR_BRANCH}' for hypernode_server_gui."
        return 1
    fi

    # Step 5: Checkout branch per server
    printf "\nChecking out server branch..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$TOTAL_STEPS" "$CURRENT_STEP"
    if ! cd "$ABSOLUTE_PATH/hypernode/hypernode-server" >/dev/null 2>&1 || ! git checkout "${SERVER_BRANCH}" >/dev/null 2>&1; then
        printf "\nError: Failed to checkout branch '${SERVER_BRANCH}' for hypernode-server."
        return 1
    fi

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

cleanProcedure(){
    
    # *****************************************************************
    # CLEANING PROCEDURE **********************************************
    # *****************************************************************

    printf "\nCleaning code..."
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    rm -rf "$ABSOLUTE_PATH/hypernode" > /dev/null

}

dockerNuke() {
    printf "\nAre you sure you want to stop and remove all containers, images, networks, and volumes? (y/n) \n[there's no going back]"
    read -r confirmation

    if [[ "$confirmation" == "y" || "$confirmation" == "Y" ]]; then
        printf "\nStopping and removing all containers..."

        if ! sudo docker stop $(sudo docker ps -q) >/dev/null 2>&1; then
            printf "\nError: Failed to stop containers."
            return 1
        fi

        if ! sudo docker rm -f $(sudo docker ps -aq) >/dev/null 2>&1; then
            printf "\nError: Failed to remove containers."
            return 1
        fi

        if ! sudo docker rmi -f $(sudo docker images -q) >/dev/null 2>&1; then
            printf "\nError: Failed to remove images."
            return 1
        fi

        if ! sudo docker system prune -a --volumes -f >/dev/null 2>&1; then
            printf "\nError: Failed to prune Docker system."
            return 1
        fi

        end_with_message "Docker cleanup" 0
    else
        printf "\nOperation canceled."
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