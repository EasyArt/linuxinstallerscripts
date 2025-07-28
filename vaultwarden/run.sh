#!/bin/bash
#                  _ _                         _            
#                 | | |                       | |           
#__   ____ _ _   _| | |___      ____ _ _ __ __| | ___ _ __  
#\ \ / / _` | | | | | __\ \ /\ / / _` | '__/ _` |/ _ \ '_ \ 
# \ V / (_| | |_| | | |_ \ V  V / (_| | | | (_| |  __/ | | |
#  \_/ \__,_|\__,_|_|\__| \_/\_/ \__,_|_|  \__,_|\___|_| |_|
# Raphael Jäger 28.07.2025                                                           
                                                           

vaultwarden_admin_token=""

install_vaultwarden() {
  # Ensure whiptail is installed
  if ! command -v whiptail &> /dev/null; then
    echo "Installing whiptail..."
    apt-get update && apt-get install -y whiptail
  fi

  # Check if Docker network 'produktiv' exists
  if ! docker network ls --format '{{.Name}}' | grep -q '^produktiv$'; then
    whiptail --title "Missing Docker Network" --msgbox \
      "Docker network 'produktiv' was not found.\n\nIt seems Docker was not installed using the 'shQuick' script.\n\nPlease create the network manually:\n\ndocker network create produktiv" \
      15 70
    return 1
  fi

  # Create Docker volume
  docker volume create vaultwarden

  # Generate Admin Token
  vaultwarden_admin_token=$(openssl rand -base64 30 | tr -d /=+ | cut -c -30)

  # Run Vaultwarden container
  docker run -d \
    --name vaultwarden \
    --network produktiv \
    --hostname vaultwarden \
    -v vaultwarden:/data \
    -e ADMIN_TOKEN="$vaultwarden_admin_token" \
    vaultwarden/server:latest

  # Show success message with token
  whiptail --title "Vaultwarden Installed" --msgbox \
    "Vaultwarden has been successfully started.\n\nAdmin Token:\n$vaultwarden_admin_token" \
    12 70
}
