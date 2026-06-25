#!/bin/bash

set -e

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Install whiptail if missing
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Whiptail is not installed. Installing..."

    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y whiptail
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y newt
    elif command -v yum >/dev/null 2>&1; then
        yum install -y newt
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y whiptail
    else
        echo "Unable to install whiptail automatically."
        exit 1
    fi
fi

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    whiptail \
        --title "Docker Missing" \
        --msgbox "Docker is not installed.\n\nPlease install Docker first." \
        10 60
    exit 1
fi

# Check Docker network
if ! docker network inspect produktiv >/dev/null 2>&1; then
    whiptail \
        --title "Network Missing" \
        --msgbox "The Docker network 'produktiv' does not exist.\n\nPlease install Docker using the shQuick.de script or create the 'produktiv' network manually." \
        12 75
    exit 1
fi

# Get host IP
HOST_IP=$(hostname -I | awk '{print $1}')

# Create Docker volumes
docker volume inspect beszel_data >/dev/null 2>&1 || docker volume create beszel_data >/dev/null
docker volume inspect beszel_socket >/dev/null 2>&1 || docker volume create beszel_socket >/dev/null

# Remove existing container if present
docker rm -f beszel >/dev/null 2>&1 || true

# Deploy Beszel Hub
docker run -d \
    --name beszel \
    --restart always \
    --network produktiv \
    -e APP_URL="http://${HOST_IP}:8090" \
    -p 8090:8090/tcp \
    -v beszel_data:/beszel_data \
    -v beszel_socket:/beszel_socket \
    henrygd/beszel:latest

whiptail \
    --title "Beszel Installed" \
    --msgbox "Beszel has been installed successfully.\n\nURL:\nhttp://${HOST_IP}:8090" \
    12 60
