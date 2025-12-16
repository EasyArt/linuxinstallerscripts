#!/bin/bash
# ______    _             _       
#|  ____|  (_)           | |      
#| |__ _ __ _  __ _  __ _| |_ ___ 
#|  __| '__| |/ _` |/ _` | __/ _ \
#| |  | |  | | (_| | (_| | ||  __/
#|_|  |_|  |_|\__, |\__,_|\__\___|
#              __/ |              
#             |___/               
# Raphael Jäger

apt install whiptail -y
set -e

NETWORK="produktiv"
CONTAINER_NAME="frigate"
IMAGE="ghcr.io/blakeblackshear/frigate:stable"
CONFIG_VOLUME="frigate_config"
MEDIA_VOLUME="frigate_media"

# --- check docker network ---
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  whiptail --title "Docker network missing" \
    --msgbox "The Docker network 'produktiv' does not exist.

Please create it manually:
  docker network create produktiv

or install Docker using the shQuick installation script." 12 70
  exit 1
fi

# --- password input ---
RTSP_PASSWORD=$(whiptail --passwordbox \
  "Enter FRIGATE_RTSP_PASSWORD" 10 60 3>&1 1>&2 2>&3)

if [ -z "$RTSP_PASSWORD" ]; then
  whiptail --msgbox "Password must not be empty." 8 45
  exit 1
fi

# --- raspberry pi selection ---
IS_RPI=false
if whiptail --yesno "Are you installing on a Raspberry Pi 4B?" 10 60; then
  IS_RPI=true
fi

# --- coral selection ---
CORAL_TYPE=$(whiptail --title "Coral selection" --menu \
  "Select Coral type" 15 60 3 \
  "none" "No Coral (default)" \
  "usb" "Coral USB" \
  "pcie" "Coral PCIe" \
  3>&1 1>&2 2>&3)

# --- media storage selection ---
MEDIA_TYPE=$(whiptail --title "Frigate Media Storage" --menu \
  "How should /media/frigate be stored?" 15 70 2 \
  "volume" "Use Docker volume (frigate_media)" \
  "mount" "Use bind mount (host path)" \
  3>&1 1>&2 2>&3)

MEDIA_MOUNT=""

if [ "$MEDIA_TYPE" = "volume" ]; then
  if ! docker volume inspect "$MEDIA_VOLUME" >/dev/null 2>&1; then
    docker volume create "$MEDIA_VOLUME"
  fi
  MEDIA_MOUNT="-v ${MEDIA_VOLUME}:/media/frigate"
else
  HOST_PATH=$(whiptail --inputbox \
    "Enter host path for Frigate media storage:" 10 70 \
    "/opt/frigate/media" \
    3>&1 1>&2 2>&3)

  if [ -z "$HOST_PATH" ]; then
    whiptail --msgbox "Path must not be empty." 8 45
    exit 1
  fi

  if [ ! -d "$HOST_PATH" ]; then
    whiptail --msgbox "The specified path does not exist." 8 55
    exit 1
  fi

  MEDIA_MOUNT="-v ${HOST_PATH}:/media/frigate"
fi

# --- create config volume ---
if ! docker volume inspect "$CONFIG_VOLUME" >/dev/null 2>&1; then
  docker volume create "$CONFIG_VOLUME"
fi

# --- device arguments ---
DEVICE_ARGS=""

case "$CORAL_TYPE" in
  usb)
    DEVICE_ARGS+=" --device /dev/bus/usb:/dev/bus/usb"
    ;;
  pcie)
    DEVICE_ARGS+=" --device /dev/apex_0:/dev/apex_0"
    ;;
esac

if [ "$IS_RPI" = true ]; then
  DEVICE_ARGS+=" --device /dev/video11:/dev/video11"
fi

# --- remove existing container ---
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker rm -f "$CONTAINER_NAME"
fi

# --- docker run ---
docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname frigate \
  --network "$NETWORK" \
  --restart always \
  --privileged \
  --shm-size=512mb \
  $DEVICE_ARGS \
  -v /etc/localtime:/etc/localtime:ro \
  -v "${CONFIG_VOLUME}:/config" \
  $MEDIA_MOUNT \
  --tmpfs /tmp/cache:size=1000000000 \
  -p 8971:8971 \
  -p 8554:8554 \
  -p 8555:8555/tcp \
  -p 8555:8555/udp \
  -e FRIGATE_RTSP_PASSWORD="$RTSP_PASSWORD" \
  "$IMAGE"

whiptail --msgbox "Frigate container installed successfully. Port 8971 Username Admin Password in Docker Logs." 8 45
