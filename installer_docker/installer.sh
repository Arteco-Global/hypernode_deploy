#!/bin/bash

# LOCAL INSTALLER TEST |

# Global vars
SCRIPT_DIR=$(dirname "$0") #local path
DEPLOY_BRANCH="main"
ABSOLUTE_PATH_BASE="https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
ABSOLUTE_PATH="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"

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
RABBITMQ_DEFAULT_USER="${RABBITMQ_DEFAULT_USER:-hypernode}"
RABBITMQ_DEFAULT_PASS="${RABBITMQ_DEFAULT_PASS:-hypernode}"

PROCESS_NAME="--"
remote_host="--"   

ENV_LOG_FILE="${PWD}/.hypernode-install-env.log"
ENV_LOG_DIR_SYSTEM="/etc/.hypernode"
ENV_LOG_FILE_SYSTEM="${ENV_LOG_DIR_SYSTEM}/.hypernode-install-env.log"
MACHINE=""
MACHINE_JSON_NAME="machine.json"
MACHINE_FILE_LOCAL="${PWD}/${MACHINE_JSON_NAME}"
MACHINE_FILE_SYSTEM="${ENV_LOG_DIR_SYSTEM}/${MACHINE_JSON_NAME}"
MACHINE_FILE=""

generate_machine_id() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
        return
    fi

    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
        return
    fi

    printf '%s-%s-%s\n' "$(date +%s)" "$RANDOM" "$RANDOM"
}

read_machine_id_from_file() {
    local file="$1"
    local value=""

    if [[ -f "$file" ]]; then
        if [[ -r "$file" ]]; then
            value=$(sed -n 's/.*"MACHINE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1)
            if [[ -z "$value" ]]; then
                value=$(sed -n 's/^MACHINE=\(.*\)$/\1/p' "$file" | head -n 1)
            fi
        elif command -v sudo >/dev/null 2>&1; then
            value=$(sudo cat "$file" 2>/dev/null | sed -n 's/.*"MACHINE"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            if [[ -z "$value" ]]; then
                value=$(sudo cat "$file" 2>/dev/null | sed -n 's/^MACHINE=\(.*\)$/\1/p' | head -n 1)
            fi
        fi
    fi

    printf '%s' "$value"
}

write_machine_json() {
    local file="$1"
    local id="$2"
    local dir
    local tmp

    dir=$(dirname "$file")
    if mkdir -p "$dir" 2>/dev/null; then
        :
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$dir" 2>/dev/null || true
    fi

    tmp=$(mktemp)
    printf '{\"MACHINE\":\"%s\"}\n' "$id" > "$tmp"

    if cp "$tmp" "$file" 2>/dev/null; then
        chmod 600 "$file" 2>/dev/null || true
        rm -f "$tmp"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        if sudo cp "$tmp" "$file" 2>/dev/null; then
            sudo chmod 600 "$file" 2>/dev/null || true
            rm -f "$tmp"
            return 0
        fi
    fi

    rm -f "$tmp"
    return 1
}

if [[ -f "$MACHINE_FILE_LOCAL" ]]; then
    MACHINE_FILE="$MACHINE_FILE_LOCAL"
elif [[ -f "$MACHINE_FILE_SYSTEM" ]]; then
    MACHINE_FILE="$MACHINE_FILE_SYSTEM"
fi

if [[ -n "$MACHINE_FILE" ]]; then
    MACHINE="$(read_machine_id_from_file "$MACHINE_FILE")"
    if [[ -z "$MACHINE" && ! -r "$MACHINE_FILE" ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "❌ machine.json is not readable. Run installer with sudo."
            exit 1
        fi
    fi
fi

if [[ -z "$MACHINE" ]]; then
    MACHINE="$(generate_machine_id)"
    if write_machine_json "$MACHINE_FILE_SYSTEM" "$MACHINE"; then
        MACHINE_FILE="$MACHINE_FILE_SYSTEM"
    else
        write_machine_json "$MACHINE_FILE_LOCAL" "$MACHINE" || true
        MACHINE_FILE="$MACHINE_FILE_LOCAL"
    fi
fi

export MACHINE
if [[ ! -f "$MACHINE_FILE_LOCAL" ]]; then
    write_machine_json "$MACHINE_FILE_LOCAL" "$MACHINE" || true
fi
ENV_VARS=(
    SSL_PORT
    DOCKER_TAG
    MACHINE
    SERIAL_NUMBER
    SERVER_TIMEZONE
    SERVER_NAME
    ARTECO_GLOBAL_EMAIL
    ARTECO_GLOBAL_PASSWORD
    SERVER_IP_ADDRESS
    CERTIFICATE_PROVIDER_URL
    DNS_PROVIDER_URL
    LICENSE_PROVIDER_URL
    RECORDING_PATH
    RECORDING_DISK_SPACE
    STORAGE_PATH
    STORAGE_DISK_SPACE
    SNAPSHOT_PATH
    SNAPSHOT_DISK_SPACE
    DB_PORT
    DB_NAME
    PROCESS_NAME
    DATABASE_URI
    RABBITMQ_DEFAULT_USER
    RABBITMQ_DEFAULT_PASS
    RMQ
    GRI
    INSTALL_OPTION
)

log_install_env() {
    local base_name
    local target_name
    local additional_name

    base_name=".hypernode-install-env.log"
    target_name="$base_name"

    if [[ -n "${INSTALL_OPTION:-}" && "${INSTALL_OPTION}" != "1" ]]; then
        if [[ -n "${PROCESS_NAME:-}" && "${PROCESS_NAME}" != "--" ]]; then
            additional_name="$PROCESS_NAME"
        elif [[ -n "${DB_NAME:-}" && "${DB_NAME}" != "uss_database" ]]; then
            additional_name="$DB_NAME"
        else
            additional_name=""
        fi

        if [[ -n "$additional_name" ]]; then
            target_name=".hypernode-install-${additional_name}-env.log"
        else
            target_name=".hypernode-install-additional-env.log"
        fi
    fi

    ENV_LOG_FILE="${PWD}/${target_name}"
    ENV_LOG_FILE_SYSTEM="${ENV_LOG_DIR_SYSTEM}/${target_name}"

    local tmp_file
    tmp_file=$(mktemp)
    {
        for var_name in "${ENV_VARS[@]}"; do
            if [[ -z "${!var_name+x}" ]]; then
                printf '%s=\n' "$var_name"
            else
                printf '%s=%q\n' "$var_name" "${!var_name}"
            fi
        done
    } > "$tmp_file"

    mv "$tmp_file" "$ENV_LOG_FILE"
    chmod 600 "$ENV_LOG_FILE" 2>/dev/null || true

    if mkdir -p "$ENV_LOG_DIR_SYSTEM" 2>/dev/null; then
        cp "$ENV_LOG_FILE" "$ENV_LOG_FILE_SYSTEM" 2>/dev/null || true
        chmod 600 "$ENV_LOG_FILE_SYSTEM" 2>/dev/null || true
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$ENV_LOG_DIR_SYSTEM" 2>/dev/null || true
        if [[ -d "$ENV_LOG_DIR_SYSTEM" ]]; then
            sudo cp "$ENV_LOG_FILE" "$ENV_LOG_FILE_SYSTEM" 2>/dev/null || true
            sudo chmod 600 "$ENV_LOG_FILE_SYSTEM" 2>/dev/null || true
        fi
    fi
}

log_env_before_compose() {
    local command=$1
    if [[ "$command" == *"docker compose"* || "$command" == *"docker-compose"* ]]; then
        log_install_env
    fi
}




execute_command() {
    local COMMAND=$1
    local MESSAGE=$2

    log_env_before_compose "$COMMAND"

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
    -db|--deploy-branch)
      DEPLOY_BRANCH="$2"
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
    echo ""
    echo "Network options:"
    echo "  -p, --port                    Set the port for the server (default: 443)"
    echo "  -t, --tag                     Set the docker tag (default: latest)"
    echo "  -fi, --force-install          Force the installation"
    echo "  -m, --mode                    Set the installation mode"
    echo "  -host, --host                 Set the remote host (e.g., domain:443)"
    echo "  -pn, --process-name           Set the process name"
    echo ""
    echo "Setup info:"
    echo "  -sn, --serial-number          Set the device serial number"
    echo "  -tz, --timezone               Set the timezone (e.g., Europe/Rome)"
    echo "  -in, --internal-name          Set the internal server name"
    echo "  -email, --email               Set the admin email"
    echo "  -pass, --password             Set the admin password"
    echo "  -sip, --server-ip             Set the server IP"
    echo ""
    echo "Provider URLs:"
    echo "  -cert-url, --certificate-provider-url   Set the certificate provider URL"
    echo "  -dns-url, --dns-provider-url           Set the DNS provider URL"
    echo "  -lic-url, --license-provider-url       Set the license provider URL"
    echo "  -upd-url, --update-provider-url        Set the update provider URL"
    echo "  -db, --deploy-branch                   Set the deploy branch for compose files (default: main)"
    echo ""
    echo "Storage/Recording/Snapshot options:"
    echo "  -rec-path, --recording-path            Set the path to save recordings (default: /recording_files)"
    echo "  -rec-max-disk, --recording-max-disk    Set max disk space for recordings in Kbytes (default: 10000000)"
    echo "  -storage-path, --storage-path          Set the path to save storage files (default: /storage_files)"
    echo "  -storage-max-disk, --storage-max-disk  Set max disk space for storage in Kbytes (default: 10000000)"
    echo "  -snapshot-path, --snapshot-path        Set the path to save snapshots (default: /snapshot_files)"
    echo "  -snapshot-max-disk, --snapshot-max-disk Set max disk space for snapshots in Kbytes (default: 10000000)"
    echo ""
    echo "Example:"
    echo "  ./installer.sh --tag latest --force-install --port 443 --mode 1 --host example.com:443 --process-name cam1 --serial-number SN001 --timezone Europe/Rome --internal-name SRV1 --email test@example.com --password 1234 --server-ip 192.168.1.10 --certificate-provider-url https://cert.example.com --dns-provider-url https://dns.example.com --license-provider-url https://lic.example.com --update-provider-url https://upd.example.com --deploy-branch main --recording-path /recording_files --recording-max-disk 10000000 --storage-path /storage_files --storage-max-disk 10000000 --snapshot-path /snapshot_files --snapshot-max-disk 10000000"
    exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      shift
      ;;
  esac
done

ABSOLUTE_PATH="$ABSOLUTE_PATH_BASE/$DEPLOY_BRANCH/installer_docker/composes"



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

installLocalDb() {
    printf "\nInstalling local database on port $DB_PORT"

    printf "\nDatabase name: "$ABSOLUTE_PATH/database/docker-compose.yaml""

    execute_command "$COMPOSE_CMD -f <(curl -sSL "$ABSOLUTE_PATH/database/docker-compose.yaml") up -d --build --remove-orphans" \
        "Installing local database" || return 1

    return 0
}

additionalServiceInstall() {
    local SERVICE_NAME=$1
    local TYPE_OF_INSTALL=${2:-"install"} 
    local COMPOSE_FILE="$ABSOLUTE_PATH/$SERVICE_NAME/docker-compose.yaml"

    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        if reuseExistingDbPort "$DB_NAME"; then
            printf "\nFound existing database port %s for %s.\n" "$DB_PORT" "$SERVICE_NAME"
        else
            printf "\nExisting database for %s not found. Searching for a free port.\n" "$SERVICE_NAME"
            getFirstDbPortFree
        fi
    else
        getFirstDbPortFree
    fi

    installLocalDb


    printf "\nInstalling '$SERVICE_NAME'"


    if [ "$SERVICE_NAME" != "server" ] ; then
    
        printf "\nInstalling additional database for $SERVICE_NAME"
        execute_command "$COMPOSE_CMD -f <(curl -sSL "$ABSOLUTE_PATH/database/docker-compose.yaml") up -d --build --remove-orphans --pull always" 

    fi

 
    if [ "$TYPE_OF_INSTALL" == "update" ]; then
        printf "\nUpdating service: $SERVICE_NAME"

        execute_command "$COMPOSE_CMD -f  <(curl -sSL "$COMPOSE_FILE") pull" \
            "Pulling latest images for $SERVICE_NAME" || return 1

        execute_command "$COMPOSE_CMD -f  <(curl -sSL "$COMPOSE_FILE") down" \
            "Stopping and removing containers for $SERVICE_NAME" || return 1

        execute_command "docker image prune -f >/dev/null 2>&1" \
            "Pruning Docker images" || return 1
    fi

    execute_command "$COMPOSE_CMD -f <(curl -sSL "$COMPOSE_FILE") up -d --build --remove-orphans --pull always" \
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
    # echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC}  6. ${GREEN}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC} 15. ${GREEN}Metadata Manager${NC}"

    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Event Manager${NC}"
    # echo -e "  ${CYAN}  │${NC} 10. ${BLUE}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${BLUE}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC} 16. ${BLUE}Metadata Manager${NC}"
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
    # echo -e "  ${CYAN}  │${NC}  5. ${GREEN}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC}  6. ${GREEN}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC}  7. ${GREEN}Recording${NC}"
    echo -e "  ${CYAN}  │${NC} 15. ${GREEN}Metadata Manager${NC}"
    echo -e "  ${CYAN}  └─────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BLUE}UPDATE EXISTING SERVICE:${NC}"
    echo -e "  ${CYAN}  ┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}  │${NC}  8. ${BLUE}All the Service Suite${NC}"
    echo -e "  ${CYAN}  │${NC}  9. ${BLUE}Live streamer${NC}"
    echo -e "  ${CYAN}  │${NC}  10. ${BLUE}ID Verifier${NC}"
    echo -e "  ${CYAN}  │${NC} 11. ${BLUE}Event Manager${NC}"
    # echo -e "  ${CYAN}  │${NC} 12. ${BLUE}Storage service${NC}"
    echo -e "  ${CYAN}  │${NC} 13. ${BLUE}Thumbnail Engine${NC}"
    echo -e "  ${CYAN}  │${NC} 14. ${BLUE}Recording${NC}"
    echo -e "  ${CYAN}  │${NC} 16. ${BLUE}Metadata Manager${NC}"
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

reuseExistingDbPort() {
    local container_name=$1

    if [ -z "$container_name" ]; then
        return 1
    fi

    local host_port
    host_port=$(docker inspect -f '{{range $port, $bindings := .NetworkSettings.Ports}}{{if eq $port "27017/tcp"}}{{(index $bindings 0).HostPort}}{{end}}{{end}}' "$container_name" 2>/dev/null)

    if [[ -n "$host_port" ]]; then
        DB_PORT=$host_port
        export DB_PORT
        echo "Reusing existing database mapped port $DB_PORT for $container_name."
        return 0
    fi

    return 1
}






get_config() {

    RABBITMQ_DEFAULT_USER="${RABBITMQ_DEFAULT_USER:-hypernode}"
    RABBITMQ_DEFAULT_PASS="${RABBITMQ_DEFAULT_PASS:-hypernode}"
    export RABBITMQ_DEFAULT_USER
    export RABBITMQ_DEFAULT_PASS

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

        RMQ="amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@messagebroker:5672"
        export DB_NAME='uss_database'
        export RMQ

        ;;
    2 | 3 | 4 | 5 | 6 | 7 | 15)
       

        if [ "$FORCE_INSTALL" == "false" ]; then
            # Install single services (Runner Mode)
            read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud:443): " remote_host
            read -p "Type the service name to update: " PROCESS_NAME

        fi

        REMOTE_GATEWAY_URL="$remote_host"
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@$remote_host"
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

      8 | 9 | 10 | 11 | 12 | 16)

        # Update single services (Runner Mode)
        read -p "Type the service name to update: " PROCESS_NAME
        read -p "Insert uSee Gateway url (VXXXXXX.my|lan.omniaweb.cloud:443): " remote_host
     
        export PROCESS_NAME=additional-${PROCESS_NAME}
        export DB_NAME=database-for-${PROCESS_NAME}
        export DATABASE_URI=mongodb://${DB_NAME}:27017/${PROCESS_NAME}
        export RMQ="amqps://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@$remote_host"
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
        
    99 | 666)
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
    local skip_confirmation=${1:-false}
    local confirmation

    if [ "$skip_confirmation" == "true" ]; then
        confirmation="y"
    else
        printf "\nAre you sure you want to stop and remove all containers, images, networks, and volumes? (y/n) \n\n[there's no going back]"
        read -r confirmation
    fi

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
elif [ "$INSTALL_OPTION" -eq 15 ]; then
    additionalServiceInstall "metadata" && end_with_message "Metadata service installation" 0 || end_with_message "Metadata service installation" 1
elif [ "$INSTALL_OPTION" -eq 16 ]; then
    additionalServiceInstall "metadata" "update" && end_with_message "Metadata service update" 0 || end_with_message "Metadata service update" 1
elif [ "$INSTALL_OPTION" -eq 99 ]; then
    dockerNuke && end_with_message "Cleanup" 0 || end_with_message "Cleanup" 1
elif [ "$INSTALL_OPTION" -eq 666 ]; then
    dockerNuke "true" && end_with_message "Cleanup" 0 || end_with_message "Cleanup" 1
fi
