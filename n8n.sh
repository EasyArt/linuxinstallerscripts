#!/bin/bash
#        ___        
#       / _ \       
# _ __ | (_) |_ __  
#| '_ \ > _ <| '_ \ 
#| | | | (_) | | | |
#|_| |_|\___/|_| |_|
# 24.07.2025 Raphael Jäger                  
       
# Install whiptail if not present
if ! command -v whiptail &> /dev/null; then
    echo "Installing whiptail..."
    sudo apt-get update && sudo apt-get install -y whiptail
fi

# Check if Docker network 'produktiv' exists
if ! docker network ls --format '{{.Name}}' | grep -q "^produktiv$"; then
    whiptail --title "Docker network missing" --msgbox \
    "Docker was not installed using the shQuick script.\nPlease reinstall Docker or create the 'produktiv' network manually." \
    12 60
    exit 1
fi

# Prompt for timezone
TIMEZONE=$(whiptail --title "Timezone Configuration" \
--inputbox "Enter your timezone (e.g. Europe/Berlin):" \
10 60 "Europe/Berlin" 3>&1 1>&2 2>&3)

# Check if user pressed Cancel
if [ $? -ne 0 ]; then
    echo "Cancelled by user."
    exit 1
fi

# Create Docker volume 'n8n' if it doesn't exist
if ! docker volume ls --format '{{.Name}}' | grep -q "^n8n$"; then
    echo "Creating Docker volume 'n8n'..."
    docker volume create n8n
fi

# Run n8n container
echo "Starting n8n container..."
docker run -d \
    --name n8n \
    --hostname n8n \
    --network produktiv \
    --restart always \
    -e TZ="$TIMEZONE" \
    -e GENERIC_TIMEZONE="$TIMEZONE" \
    -v n8n:/home/node/.n8n \
    n8nio/n8n:latest

echo "n8n container deployed successfully with timezone $TIMEZONE."
