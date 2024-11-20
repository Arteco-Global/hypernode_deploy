#!/bin/bash

show_progress() {
    local -r TOTAL_STEPS=$1
    local -r CURRENT_STEP=$2
    local -r BAR_WIDTH=50

    local COMPLETED=$((CURRENT_STEP * BAR_WIDTH / TOTAL_STEPS))
    local REMAINING=$((BAR_WIDTH - COMPLETED))

    # Stampa la barra di progresso
    printf "\r"  # Riporta il cursore all'inizio della riga
    printf "                                                     "  # Cancella la linea precedente con spazi
    printf "\r"  # Riporta il cursore all'inizio della riga di nuovo

    # Stampa la barra di progresso
    printf "["
    for ((i=0; i<COMPLETED; i++)); do
        printf "#"
    done
    for ((i=0; i<REMAINING; i++)); do
        printf "-"
    done
    printf "] %d%% " $((CURRENT_STEP * 100 / TOTAL_STEPS))
}

# Steps counter
TOTAL_STEPS=100
CURRENT_STEP=0

serverSetup(){

    # *****************************************************************
    # SERVER INSTALLATION
    # *****************************************************************

    # le variuabili sono state settate in get_config

    echo "Installation in progress ........"

    docker compose up -d --build


}

dockerInstall(){
            
    # *****************************************************************
    # INSTALLING DOCKER ***********************************************
    # *****************************************************************


    # Step 1: Update packages
    printf "Updating packages                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    sudo apt-get update -y >/dev/null 2>&1
   

    # Step 2: Install required packages
    printf "Installing required packages                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common >/dev/null 2>&1


    # Step 3: Add Docker GPG key
    printf "Adding Docker GPG key...                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1


    # Step 4: Add Docker repository
    printf "Adding Docker GPG key... \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable" -y >/dev/null 2>&1
    

    # Step 5: Install Docker
    printf "Installing docker...                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y docker-ce >/dev/null 2>&1

}

cloningCode(){

    # *****************************************************************
    # CLONING FROM GITHUB *********************************************
    # *****************************************************************

    usr=mdalprato
    psw=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


    # creating folder Add Docker GPG key
    printf "Creating folder ...                        \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    mkdir -p hypernode > /dev/null

    printf "Moving inside folder ...                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd hypernode > /dev/null

    printf "Installing git ...                          \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
        # Esegui i comandi in modo silenzioso e cattura i warning
    sudo apt update > /dev/null 2>&1
    sudo apt install -y git > /dev/null 2>&1

    printf "Cloning code (may take a while) ...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode_deploy.git > /dev/null 2>&1
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode_server_gui.git > /dev/null 2>&1
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode-server.git > /dev/null 2>&1

    printf "Moving into folder ...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd hypernode-server  > /dev/null
    
    printf "Checkout branch...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    git checkout "release_candidate_2" > /dev/null 2>&1

    printf "Change folder...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd ..  > /dev/null

}

installWizard() {

    # *****************************************************************
    # WIZARD **********************************************************
    # *****************************************************************

    cd hypernode_deploy

    # Menu delle opzioni
    echo "What do you want to install:"
    echo "1. Stand alone server"
    echo "2. Additional Camera Service"
    echo "4. Exit"

    # Lettura della scelta dell'utente
    read -p "Enter the option: " option

    # Esecuzione dell'azione in base alla option
    case $option in
    1)
        echo "Stand alone server"
        serverSetup
        ;;
    2)
        echo "Additional Camera Service"
        echo "NOT IMPLEMENTED YET"
    # bash ./singleService/camera/install_camera.sh
        ;;
    3)
        echo "Additional Storage Service"
        echo "NOT IMPLEMENTED YET"
        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Wrong choice mate."
        ;;
    esac

}


get_config() {

    printf "\n"
    printf "************************************************************* \n"
    printf "Welcome to Hypernode installation process \n"
    printf "************************************************************* \n"
    printf "\n"

   # Menu delle opzioni
    echo "What do you want to install (default is '1'):"
    echo "1. Stand alone server"
    echo "2. Additional Camera Service"
    echo "4. Exit"

    # Lettura della scelta dell'utente
    read -p "Enter the option: " INSTALL_OPTION
    INSTALL_OPTION=${INSTALL_OPTION:-1}


     # Esecuzione dell'azione in base alla option
    case $INSTALL_OPTION in
    1)
        read -p "HTTP server port (default 80): " SERVER_PORT
        SERVER_PORT=${SERVER_PORT:-80}

        read -p "HTTPS server port (default 443): " SSL_PORT
        SSL_PORT=${SSL_PORT:-443}

        read -p "Configurator port (default 8080): " CONF_PORT
        CONF_PORT=${CONF_PORT:-8080}

        RMQ=amqp://hypernode:hypernode@messageBroker:5672
        ;;
    2)
       
        read -p "Choose a unique name: " PROCESS_NAME

        # Chiede all'utente se RabbitMQ deve essere locale o remoto
        read -p "Is the main gateway local (l) o (r)remote ? [l/r]: " IS_CAMERA_RMQ_LOCAL_OR_REMOTE

        # Imposta la variabile RABBITMQ_HOST in base alla scelta
        if [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "l" ] || [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "L" ]; then
            RABBITMQ_HOST_FOR_CAMERA="host.docker.internal"
            echo "Gateway set as local. Host: $RABBITMQ_HOST_FOR_CAMERA"
        elif [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "r" ] || [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "R" ]; then
            read -p "Insert the ip/url: " remote_host
            RABBITMQ_HOST_FOR_CAMERA="$remote_host"
            echo "Gateway set as remote $RABBITMQ_HOST_FOR_CAMERA"
        else
            echo "Wrong choice mate."
            exit 1
        fi

         RMQ="amqp://hypernode:hypernode@$RABBITMQ_HOST_FOR_CAMERA:5672"

        ;;
    4)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Wrong choice mate."
        ;;
    esac


    
   
    # Esporta le variabili per renderle accessibili ad altri script
    export SERVER_PORT
    export SSL_PORT
    export CONF_PORT
    export RMQ
    export INSTALL_OPTION


    echo "SERVER_PORT: $SERVER_PORT"
    echo "SSL_PORT: $SSL_PORT"
    echo "CONF_PORT: $CONF_PORT"
    echo "RMQ: $RMQ"
    echo "INSTALL_OPTION: $INSTALL_OPTION"


}



# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step
get_config 

# #b. Docker installation
# dockerInstall

# #c. Cloning code
# cloningCode


