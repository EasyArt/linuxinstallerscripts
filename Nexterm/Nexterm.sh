#!/bin/bash

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root!"
    exit 1
fi

# --- Whiptail Check ---
if ! command -v whiptail &> /dev/null; then
    apt update && apt install -y whiptail
fi

# --- Docker Check ---
if ! command -v docker &> /dev/null; then
    whiptail --title "Docker Missing" --msgbox "Docker is not installed!\n\nPlease install Docker manually or via shQuick.de." 10 60
    exit 1
fi

# --- Port Check (6989) ---
if ss -tuln | grep -q ":6989 "; then
    whiptail --title "Port in Use" --msgbox "Port 6989 is already in use!\n\nPlease free the port and try again." 10 60
    exit 1
fi

# --- Encryption Key ---
ENCRYPTION_KEY=$(openssl rand -hex 32)

# --- Run Nexterm Container ---
docker run -d \
  -e ENCRYPTION_KEY=$ENCRYPTION_KEY \
  -p 6989:6989 \
  --name nexterm \
  --restart always \
  -v nexterm:/app/data \
  nexterm/aio:development

# --- Get Host IP ---
HOST_IP=$(hostname -I | awk '{print $1}')

# --- Done Message ---
whiptail --title "Installation Complete" --msgbox "Nexterm has been successfully installed!\n\nAccess it at:\nhttp://$HOST_IP:6989" 12 60
