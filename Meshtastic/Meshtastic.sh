#!/usr/bin/env bash
# __  __           _     _            _   _      
#|  \/  |         | |   | |          | | (_)     
#| \  / | ___  ___| |__ | |_ __ _ ___| |_ _  ___ 
#| |\/| |/ _ \/ __| '_ \| __/ _` / __| __| |/ __|
#| |  | |  __/\__ \ | | | || (_| \__ \ |_| | (__ 
#|_|  |_|\___||___/_| |_|\__\__,_|___/\__|_|\___|
#  Raphael Jäger

set -euo pipefail

IMAGE="ghcr.io/meshtastic/web:latest"
CNAME="meshtastic"
CHOST="meshtastic"
NET="produktiv"

# Use sudo if not root
SUDO=""
if [[ ${EUID:-0} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "This script needs root privileges. Please run as root or install sudo."
    exit 1
  fi
fi

have() { command -v "$1" >/dev/null 2>&1; }

install_whiptail() {
  if have whiptail; then return 0; fi
  echo "Installing whiptail..."
  if have apt-get; then
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail
  elif have dnf; then
    $SUDO dnf install -y newt
  elif have yum; then
    $SUDO yum install -y newt
  elif have zypper; then
    $SUDO zypper --non-interactive install newt
  elif have pacman; then
    $SUDO pacman -Sy --noconfirm libnewt
  else
    echo "Unsupported distro: please install 'whiptail' (newt) manually."
    exit 1
  fi
}

msgbox() {
  local title="$1" text="$2"
  if have whiptail; then
    whiptail --title "$title" --msgbox "$text" 12 78
  else
    echo -e "\n[$title]\n$text\n"
  fi
}

install_whiptail

# Check Docker
if ! have docker; then
  msgbox "Docker not found" "Docker is not installed.\n\nPlease install Docker first or use the install script from the shQuick page."
  exit 1
fi

# Check network
if ! docker network inspect "$NET" >/dev/null 2>&1; then
  msgbox "Missing Docker network" "The 'produktiv' network does not exist. Please create it or install Docker using the script on the shQuick page."
  exit 1
fi

# Pull latest image
docker pull "$IMAGE"

# Stop & remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -qx "$CNAME"; then
  echo "Container '$CNAME' already exists. Recreating..."
  docker rm -f "$CNAME"
fi

# Run container
docker run -d \
  --name "$CNAME" \
  --hostname "$CHOST" \
  --restart always \
  --network "$NET" \
  "$IMAGE"

clear
msgbox "Meshtastic Web" "Container '$CNAME' has been deployed successfully on network '$NET'."
echo "Deployment complete"
