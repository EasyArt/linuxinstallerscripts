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

# --- Installation with Progress Bar ---
{
echo 5
sleep 0.3

echo 15
sleep 0.3

# Image ziehen
docker pull nexterm/aio:development >/dev/null 2>&1
echo 60

# Alten Container entfernen (falls vorhanden)
docker rm -f nexterm >/dev/null 2>&1
echo 70

# Container starten
docker run -d \
  -e ENCRYPTION_KEY=$ENCRYPTION_KEY \
  -p 6989:6989 \
  --name nexterm \
  --restart always \
  -v nexterm:/app/data \
  nexterm/aio:development >/dev/null 2>&1

echo 90
sleep 1

# kurzer Check ob Container läuft
if docker ps | grep -q nexterm; then
    echo 100
else
    echo 100
    whiptail --title "Error" --msgbox "Container failed to start!\n\nCheck logs with:\ndocker logs nexterm" 12 60
    exit 1
fi

} | whiptail --gauge "Installing Nexterm..." 8 60 0

# --- Get Host IP ---
HOST_IP=$(hostname -I | awk '{print $1}')

# --- Done Message ---
whiptail --title "Installation Complete" --msgbox "Nexterm has been successfully installed!\n\nAccess it at:\nhttp://$HOST_IP:6989\n\nNexterm is currently in Development state!" 12 60
