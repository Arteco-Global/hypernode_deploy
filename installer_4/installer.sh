#!/bin/bash

# Global vars
TOTAL_STEPS=13 #Steps for progressbar
CURRENT_STEP=0 #Counter for progressbar
SCRIPT_DIR=$(dirname "$0") #local path
ABSOLUTE_PATH=$(realpath "$SCRIPT_DIR") #absolute path

SKIP_CLEAN="false"
SKIP_DOKER_INSTALL="false"
SKIP_GIT_INSTALL="false"
SKIP_GIT_CLONE="false"
SERVER_BRANCH="main"
CONFIGURATOR_BRANCH="main"
# Getting input parameters

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -skip-clean) 
            echo "got -skip-clean parameter!"
            SKIP_CLEAN="true"
            ;;
        -skip-docker-install) 
            echo "got skip-docker-install!"
            SKIP_DOKER_INSTALL="true"
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




serverInstall(){

    # *****************************************************************
    # SERVER INSTALLATION
    # *****************************************************************

    # le variuabili sono state settate in get_config

    printf "Installing server                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    docker compose -f "$ABSOLUTE_PATH/hypernode/hypernode_deploy/docker-compose.yaml" up -d --build

    # Pulire lo schermo alla fine
    #clear

    printf "Installation completed !                   \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP


    #!/bin/bash


}


additionalServiceInstall() {

    SERVICE_NAME=$1  # Il primo parametro passato alla funzione

    echo "SERVICE_NAME: $SERVICE_NAME"
    # *****************************************************************
    # ADDITIONAL SERVICE INSTALLATION
    # *****************************************************************

    
    #sudo bash installer.sh -skip-clean
    # le var sono state settate in get_config


    printf "Installing additional service: $SERVICE_NAME \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    docker compose -f "$ABSOLUTE_PATH/hypernode/hypernode_deploy/singleService/$SERVICE_NAME/docker-compose.yaml" up -d --build


    printf "Installation completed !                   \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP


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

installGit(){

    printf "Installing git ...                          \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    # Esegui i comandi in modo silenzioso e cattura i warning
    sudo apt update > /dev/null 2>&1
    sudo apt install -y git > /dev/null 2>&1

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
    mkdir "$ABSOLUTE_PATH/hypernode" > /dev/null 2>&1

    printf "Moving inside folder ...                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd "$ABSOLUTE_PATH/hypernode" > /dev/null

    printf "Cloning code (may take a while) ...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode_deploy.git > /dev/null 2>&1
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode_server_gui.git > /dev/null 2>&1
    git clone --quiet https://$usr:$psw@github.com/Arteco-Global/hypernode-server.git > /dev/null 2>&1

    # CONFIGURATOR BRANCH *********************************************************

    printf "Moving into folder ...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd "$ABSOLUTE_PATH/hypernode/hypernode_server_gui"  > /dev/null
    
    printf "Checkout branch...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    git checkout "${CONFIGURATOR_BRANCH}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Branch '${CONFIGURATOR_BRANCH}' not found or checkout failed."
        exit 1
    fi

    # SERVER BRANCH *****************************************************************

    printf "Moving into folder ...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    cd "$ABSOLUTE_PATH/hypernode/hypernode-server"  > /dev/null
    
    printf "Checkout branch...                         \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    git checkout "${SERVER_BRANCH}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Branch '${SERVER_BRANCH}' not found or checkout failed."
        exit 1
    fi
        

}


get_config() {

    printf "\n"
    printf "************************************************************* \n"
    printf "Welcome to Hypernode installation process \n"
    printf "************************************************************* \n"
    printf "\n"

   # Menu delle opzioni
    echo "-------------------------------------:"
    echo "-------------- INSTALL  -------------:"
    echo "-------------------------------------:"
    echo ""
    echo "What do you want to install:"
    echo "|-- 1. All Server servicies (full install) [auth,camera,storage,event,gateway] "    
    echo "|-- 2. Additional Camera Service (To manage new/existing cameras)"
    echo "|-- 3. Additional Auth Service (To manage new/existing users )"
    echo "|-- 4. Additional Event Service (To manage new/existing events)"
    echo "|-- 5. Additional Storage Service (To manage new/existing storage destinations)"
    echo ""
    echo "-------------------------------------:"
    echo "-------------- UPDATE  --------------:"
    echo "-------------------------------------:"
    echo ""
    echo "What do you want to update:"
    echo "|-- 1. Update all the server's servicies "    
    echo "|-- 2. Update Camera Service"
    echo "|-- 3. Update Auth Service"
    echo "|-- 4. Update Event Service"
    echo "|-- 5. Update Storage Service"
    echo ""
    echo "-------------------------------------:"
    echo "0. EXIT"

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

        read -p "| --> Server branch (default is 'main') " SERVER_BRANCH
        SERVER_BRANCH=${SERVER_BRANCH:main}

        read -p "| --> Web Configurator branch (default is 'main') " CONFIGURATOR_BRANCH
        CONFIGURATOR_BRANCH=${CONFIGURATOR_BRANCH:main}

        RMQ=amqp://hypernode:hypernode@messageBroker:5672


        # Esporta le variabili per renderle accessibili ad altri script
        export SERVER_PORT
        export SSL_PORT
        export CONF_PORT
        export RMQ
        export SERVER_BRANCH
        export CONFIGURATOR_BRANCH

        # echo "SERVER_PORT: $SERVER_PORT"
        # echo "SSL_PORT: $SSL_PORT"
        # echo "CONF_PORT: $CONF_PORT"
        # echo "RMQ: $RMQ"

        ;;
    2 | 3 | 4 | 5)
       
        read -p "Choose a unique name: " PROCESS_NAME

        read -p "| --> branch (default is 'main') " SERVER_BRANCH
        SERVER_BRANCH=${SERVER_BRANCH:main}

        read -p "Is the main gateway local (l) o (r)remote ? [l/r]: " IS_CAMERA_RMQ_LOCAL_OR_REMOTE

        # Imposta la variabile RABBITMQ_HOST in base alla scelta
        if [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "l" ] || [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "L" ]; then
            RABBITMQ_HOST_FOR_ADDITIONAL="172.17.0.1"
            echo "Gateway set as local. Host: $RABBITMQ_HOST_FOR_ADDITIONAL"
        elif [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "r" ] || [ "$IS_CAMERA_RMQ_LOCAL_OR_REMOTE" == "R" ]; then
            read -p "Insert the ip/url: " remote_host
            RABBITMQ_HOST_FOR_ADDITIONAL="$remote_host"
            echo "Gateway set as remote $RABBITMQ_HOST_FOR_ADDITIONAL"
        else
            echo "Wrong choice mate."
            exit 1
        fi
     
        export PROCESS_NAME=camera-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/camera-service
        export RMQ="amqp://hypernode:hypernode@$RABBITMQ_HOST_FOR_ADDITIONAL:5672"
        export SERVER_BRANCH

        ;;
    0)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Wrong choice mate."
        exit 1
        ;;
    esac

    export INSTALL_OPTION

    #echo "INSTALL_OPTION: $INSTALL_OPTION"


}

cleanProcedure(){
    
    # *****************************************************************
    # CLEANING PROCEDURE **********************************************
    # *****************************************************************

    printf "Cleaning code ...                  \r"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress $TOTAL_STEPS $CURRENT_STEP
    rm -rf "$ABSOLUTE_PATH/hypernode" > /dev/null

}


# *****************************************************************
# STEP BY STEP INSTALLATION
# *****************************************************************

#a. Welcome step
get_config 


if [ "$SKIP_GIT_INSTALL" != "true" ]; then
    # git installation
    installGit
else
    echo "Skipping git install"
fi


if [ "$SKIP_DOKER_INSTALL" != "true" ]; then
    # server installation
    dockerInstall
else
    echo "Skipping docker install"
fi


if [ "$SKIP_GIT_CLONE" != "true" ]; then
    # d. Cloning code from github
    cloningCode
else
    echo "Skipping docker install"
fi

# echo "|-- 2. Additional Camera Service"
# echo "|-- 3. Additional Auth Service"
# echo "|-- 4. Additional Event Service"
# echo "|-- 5. Additional Storage Service"

if [ "$INSTALL_OPTION" -eq 1 ]; then
    serverInstall
elif [ "$INSTALL_OPTION" -eq 2 ]; then
    additionalServiceInstall "camera"
elif [ "$INSTALL_OPTION" -eq 3 ]; then
    additionalServiceInstall "auth"
elif [ "$INSTALL_OPTION" -eq 4 ]; then
    additionalServiceInstall "event"
elif [ "$INSTALL_OPTION" -eq 5 ]; then
    additionalServiceInstall "storage"
fi

if [ "$SKIP_CLEAN" != "true" ]; then
    # server installation
    cleanProcedure
else
    echo "Skipping cleaning procedure"
fi