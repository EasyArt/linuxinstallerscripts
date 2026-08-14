#!/bin/bash
# _____        _        _                         
#|  __ \      | |      | |                        
#| |  | | __ _| |_ __ _| |__   __ _ ___ _   _ ___ 
#| |  | |/ _` | __/ _` | '_ \ / _` / __| | | / __|
#| |__| | (_| | || (_| | |_) | (_| \__ \ |_| \__ \
#|_____/ \__,_|\__\__,_|_.__/ \__,_|___/\__,_|___/
# Raphael Jäger                                                 

set -e

SCRIPT_NAME="Databasus Installer"
NETWORK_NAME="produktiv"
CONTAINER_NAME="databasus"
VOLUME_NAME="databasus"
IMAGE_NAME="databasus/databasus:latest"

# ---------------------------------------------------------
# Helper functions
# ---------------------------------------------------------

show_info() {
    whiptail --title "$SCRIPT_NAME" --msgbox "$1" 10 70
}

show_error() {
    whiptail --title "$SCRIPT_NAME - Error" --msgbox "$1" 12 70
}

show_success() {
    whiptail --title "$SCRIPT_NAME - Success" --msgbox "$1" 12 70
}

# ---------------------------------------------------------
# Check root privileges
# ---------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        show_error "This script must be run with root privileges.

Please run it using:

sudo $0

Alternatively, switch to the root user and run the script again."
    else
        echo "ERROR: This script must be run as root or with sudo."
    fi

    exit 1
fi

# ---------------------------------------------------------
# Check whiptail
# ---------------------------------------------------------

if ! command -v whiptail >/dev/null 2>&1; then
    # Determine package manager
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y whiptail
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y newt
    elif command -v yum >/dev/null 2>&1; then
        yum install -y newt
    elif command -v apk >/dev/null 2>&1; then
        apk add newt
    else
        echo "ERROR: whiptail is not installed and no supported package manager was found."
        exit 1
    fi
fi

# ---------------------------------------------------------
# Start
# ---------------------------------------------------------

show_info "Starting the Databasus installation.

The script will check the required dependencies and Docker configuration."

# ---------------------------------------------------------
# Check Docker
# ---------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    show_error "Docker is not installed.

Docker must be installed before Databasus can be deployed.

You can install Docker using the installation script provided by:

https://shquick.de/

Please install Docker and run this script again."

    exit 1
fi

# ---------------------------------------------------------
# Check Docker daemon
# ---------------------------------------------------------

if ! docker info >/dev/null 2>&1; then
    show_error "Docker is installed, but the Docker daemon is not running or cannot be accessed.

Please make sure that Docker is running and try again."

    exit 1
fi

# ---------------------------------------------------------
# Check Docker network
# ---------------------------------------------------------

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    show_error "The required Docker network '$NETWORK_NAME' does not exist.

Please create the Docker network '$NETWORK_NAME' before running this script.

Alternatively, you can install Docker using the installation script provided by:

https://shquick.de/

After the required Docker network has been created, run this script again."

    exit 1
fi

# ---------------------------------------------------------
# Check if container already exists
# ---------------------------------------------------------

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    show_error "A Docker container named '$CONTAINER_NAME' already exists.

No changes were made.

Please remove the existing container if you want to perform a fresh installation."

    exit 1
fi

# ---------------------------------------------------------
# Create volume
# ---------------------------------------------------------

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    docker volume create "$VOLUME_NAME" >/dev/null
fi

# ---------------------------------------------------------
# Pull image
# ---------------------------------------------------------

show_info "Downloading the Databasus Docker image.

Image:
$IMAGE_NAME

This may take a moment depending on your Internet connection."

docker pull "$IMAGE_NAME" >/dev/null

# ---------------------------------------------------------
# Create container
# ---------------------------------------------------------

docker create \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --restart always \
    --network "$NETWORK_NAME" \
    -v "$VOLUME_NAME:/databasus-data" \
    "$IMAGE_NAME" >/dev/null

# ---------------------------------------------------------
# Start container
# ---------------------------------------------------------

docker start "$CONTAINER_NAME" >/dev/null

# ---------------------------------------------------------
# Final message
# ---------------------------------------------------------

show_success "Databasus was successfully installed.

Container:
$CONTAINER_NAME

Hostname:
$CONTAINER_NAME

Docker network:
$NETWORK_NAME

Volume:
$VOLUME_NAME:/databasus-data

The Databasus container is now running.

IMPORTANT:

You still need to create a reverse proxy entry.

Reverse proxy target:

Hostname: $CONTAINER_NAME
Port: 4005
Protocol: TCP

Make sure your reverse proxy can reach the Docker network '$NETWORK_NAME'."
