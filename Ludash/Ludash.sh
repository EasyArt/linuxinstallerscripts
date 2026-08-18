#!/usr/bin/env bash
# _               _           _     
#| |             | |         | |    
#| |    _   _  __| | __ _ ___| |__  
#| |   | | | |/ _` |/ _` / __| '_ \ 
#| |___| |_| | (_| | (_| \__ \ | | |
#|______\__,_|\__,_|\__,_|___/_| |_|
#  Raphael Jäger shQuick.de

set -e

# ============================================================
# Ludash Installer
# ============================================================

CONTAINER_NAME="ludash"
LUDASH_HOSTNAME="ludash"
NETWORK="produktiv"
IMAGE="ghcr.io/theduffman85/linux-update-dashboard:latest"
CONTAINER_PORT="3001"

# ============================================================
# Helper functions
# ============================================================

msg_info() {
    whiptail \
        --title "Ludash Installer" \
        --msgbox "$1" \
        10 70
}

msg_error() {
    whiptail \
        --title "Error" \
        --msgbox "$1" \
        11 75
}

msg_no_produktiv() {
    whiptail \
        --title "Error" \
        --msgbox "$1" \
        13 75
}

msg_success() {
    whiptail \
        --title "Installation" \
        --msgbox "$1" \
        12 75
}

msg_finalmsg() {
    whiptail \
        --title "Installation" \
        --msgbox "$1" \
        22 75
}

ask_yes_no() {
    whiptail \
        --title "$1" \
        --yesno "$2" \
        12 70
}

# ============================================================
# Root / sudo check
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo
    echo "ERROR: This script must be run as root or with sudo."
    echo
    echo "Example:"
    echo "  sudo $0"
    exit 1
fi

# ============================================================
# Check whiptail
# ============================================================

if ! command -v whiptail >/dev/null 2>&1; then

    # whiptail is not available yet, therefore normal shell
    # output is unavoidable at this point.

    echo "whiptail is not installed."
    echo "Attempting to install whiptail..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y whiptail

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y newt

    elif command -v yum >/dev/null 2>&1; then
        yum install -y newt

    elif command -v apk >/dev/null 2>&1; then
        apk add newt

    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm libnewt

    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install newt

    else
        echo
        echo "ERROR: Could not determine the package manager."
        echo "Please install whiptail manually."
        exit 1
    fi

    if ! command -v whiptail >/dev/null 2>&1; then
        echo
        echo "ERROR: whiptail installation failed."
        exit 1
    fi
fi

# ============================================================
# From here on EVERYTHING uses whiptail
# ============================================================

msg_success \
"whiptail is installed successfully.

The Ludash installer can now continue."

# ============================================================
# Check Docker
# ============================================================

if ! command -v docker >/dev/null 2>&1; then
    msg_error \
"Docker is not installed.

Docker is required to install Ludash.

Please install Docker using the installation script from
shQuick.de and run this Ludash installer again."

    exit 1
fi

# ============================================================
# Check Docker daemon
# ============================================================

if ! docker info >/dev/null 2>&1; then

    msg_error \
"Docker is installed, but the Docker daemon is not running.

Please start the Docker service and run this installer again."

    exit 1
fi

msg_success "Docker is installed and the Docker daemon is running."

# ============================================================
# Check produktiv network
# ============================================================

if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then

    msg_no_produktiv \
"The Docker network '$NETWORK' does not exist.

The network must be created manually before Ludash can be
installed.

You can create it with:

docker network create $NETWORK

Alternatively, you can install Docker using the installation
script available at shQuick.de."

    exit 1
fi

msg_success \
"The Docker network '$NETWORK' exists.

Ludash will be connected to this network."

# ============================================================
# Ask for Ludash Base URL
# ============================================================

while true; do

    LUDASH_BASE_URL=$(whiptail \
        --title "Ludash Base URL" \
        --inputbox \
"Enter the URL under which Ludash will be accessible.

Examples:

https://ludash.example.com
http://192.168.1.50:3001" \
        15 75 \
        "http://localhost:3001" \
        3>&1 1>&2 2>&3) || {
            msg_error "Installation cancelled."
            exit 1
        }

    if [ -n "$LUDASH_BASE_URL" ]; then
        break
    fi

    msg_error "The Ludash Base URL cannot be empty."
done

# ============================================================
# Reverse Proxy
# ============================================================

LUDASH_TRUST_PROXY=""

if ask_yes_no \
    "Reverse Proxy" \
    "Will Ludash be accessed through a reverse proxy?

Select YES if you are using Nginx Proxy Manager, Traefik,
Caddy, HAProxy or another reverse proxy."; then

    while true; do

        LUDASH_TRUST_PROXY=$(whiptail \
            --title "Reverse Proxy IP Address" \
            --inputbox \
"Enter the IP address of the reverse proxy.

Example:

192.168.1.10" \
            12 70 \
            "" \
            3>&1 1>&2 2>&3) || {
                msg_error "Installation cancelled."
                exit 1
            }

        if [ -n "$LUDASH_TRUST_PROXY" ]; then
            break
        fi

        msg_error "The reverse proxy IP address cannot be empty."
    done
fi

# ============================================================
# Check existing container
# ============================================================

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then

    msg_error \
"A container named '$CONTAINER_NAME' already exists.

Please remove the existing container before running this
installer again.

Command:

docker rm -f $CONTAINER_NAME"

    exit 1
fi

# ============================================================
# Check OpenSSL
# ============================================================

if ! command -v openssl >/dev/null 2>&1; then

    msg_error \
"OpenSSL is not installed.

OpenSSL is required to generate the Ludash encryption key.

Please install OpenSSL and run this installer again."

    exit 1
fi

# ============================================================
# Generate encryption key
# ============================================================

LUDASH_ENCRYPTION_KEY=$(openssl rand -base64 32)

# ============================================================
# Installation summary
# ============================================================

SUMMARY="Ludash installation is ready.

Container:
  $CONTAINER_NAME

Hostname:
  $LUDASH_HOSTNAME

Docker network:
  $NETWORK

Port:
  $CONTAINER_PORT

Base URL:
  $LUDASH_BASE_URL
"

if [ -n "$LUDASH_TRUST_PROXY" ]; then
    SUMMARY="${SUMMARY}
Reverse proxy:
  $LUDASH_TRUST_PROXY
"
else
    SUMMARY="${SUMMARY}
Reverse proxy:
  None
"
fi

SUMMARY="${SUMMARY}
The container will be started automatically after installation.

Continue?"

if ! whiptail \
    --title "Installation Summary" \
    --yesno "$SUMMARY" \
    22 75; then

    msg_info "Installation cancelled."
    exit 0
fi

# ============================================================
# Pull Docker image
# ============================================================

(
    echo "10"
    echo "XXX"
    echo "Pulling Ludash Docker image..."
    echo "XXX"

    docker pull "$IMAGE" >/tmp/ludash-docker-pull.log 2>&1

    echo "100"
    echo "XXX"
    echo "Docker image downloaded successfully."
    echo "XXX"
) | whiptail \
    --title "Installing Ludash" \
    --gauge \
    "Preparing installation..." \
    10 70 0

if [ "${PIPESTATUS[0]}" -ne 0 ]; then

    msg_error \
"Failed to download the Ludash Docker image.

Docker output:

$(cat /tmp/ludash-docker-pull.log)"

    rm -f /tmp/ludash-docker-pull.log
    exit 1
fi

rm -f /tmp/ludash-docker-pull.log

# ============================================================
# Build Docker arguments
# ============================================================

DOCKER_ARGS=(
    -d
    --name "$CONTAINER_NAME"
    --hostname "$LUDASH_HOSTNAME"
    --network "$NETWORK"
    -e "LUDASH_ENCRYPTION_KEY=${LUDASH_ENCRYPTION_KEY}"
    -e "LUDASH_BASE_URL=${LUDASH_BASE_URL}"
    -v "ludash_data:/data"
    --restart unless-stopped
)

if [ -n "$LUDASH_TRUST_PROXY" ]; then
    DOCKER_ARGS+=(
        -e "LUDASH_TRUST_PROXY=${LUDASH_TRUST_PROXY}"
    )
else
    DOCKER_ARGS+=(
        -p "${CONTAINER_PORT}:${CONTAINER_PORT}"
    )
fi

# ============================================================
# Start container
# ============================================================

if ! docker run "${DOCKER_ARGS[@]}" "$IMAGE" >/tmp/ludash-docker-run.log 2>&1; then

    msg_error \
"Failed to create the Ludash container.

Docker output:

$(cat /tmp/ludash-docker-run.log)"

    rm -f /tmp/ludash-docker-run.log
    exit 1
fi

rm -f /tmp/ludash-docker-run.log

# ============================================================
# Wait for container
# ============================================================

sleep 3

if ! docker ps \
    --filter "name=^${CONTAINER_NAME}$" \
    --filter "status=running" \
    --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then

    msg_error \
"The Ludash container was created but is not running.

Container logs:

$(docker logs "$CONTAINER_NAME" 2>&1)"

    exit 1
fi

# ============================================================
# Installation completed
# ============================================================

FINAL_MESSAGE="Ludash has been installed successfully.

Container:
  $CONTAINER_NAME

Hostname:
  $LUDASH_HOSTNAME

Docker network:
  $NETWORK

Port:
  $CONTAINER_PORT

Ludash URL:
  $LUDASH_BASE_URL
"

if [ -n "$LUDASH_TRUST_PROXY" ]; then

    FINAL_MESSAGE="${FINAL_MESSAGE}
Reverse proxy:
  $LUDASH_TRUST_PROXY

Create a reverse proxy entry pointing to:

Host:
  $LUDASH_HOSTNAME

Port:
  $CONTAINER_PORT

Protocol:
  HTTP
"

else

    FINAL_MESSAGE="${FINAL_MESSAGE}
No reverse proxy was configured.

Ludash is directly exposed on port $CONTAINER_PORT.
"
fi

msg_finalmsg "$FINAL_MESSAGE"
