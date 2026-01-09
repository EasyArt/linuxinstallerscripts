#!/bin/bash
# _____                     _      _     
#|_   _|                   (_)    | |    
#  | |  _ __ ___  _ __ ___  _  ___| |__  
#  | | | '_ ` _ \| '_ ` _ \| |/ __| '_ \ 
# _| |_| | | | | | | | | | | | (__| | | |
#|_____|_| |_| |_|_| |_| |_|_|\___|_| |_|
# Raphael Jäger
                                                                               
set -e

# ---------- FUNCTIONS ----------
error_exit() {
  whiptail --title "Immich Installer" --msgbox "$1" 10 60
  exit 1
}

# ---------- CHECK ROOT ----------
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# ---------- INSTALL WHIPTAIL ----------
if ! command -v whiptail &>/dev/null; then
  apt update && apt install -y whiptail || error_exit "Failed to install whiptail."
fi

# ---------- CHECK DOCKER ----------
if ! command -v docker &>/dev/null; then
  error_exit "Docker is not installed.\n\nPlease install Docker manually or using shQuick."
fi

if ! docker info &>/dev/null; then
  error_exit "Docker daemon is not running."
fi

# ---------- CHECK NETWORK ----------
if ! docker network inspect produktiv &>/dev/null; then
  error_exit "Docker network 'produktiv' does not exist.\n\nPlease create it manually or install Docker using shQuick."
fi

# ---------- DATABASE ----------
DB_HOST=$(whiptail --inputbox "PostgreSQL hostname:" 10 60 database 3>&1 1>&2 2>&3)
DB_PORT=$(whiptail --inputbox "PostgreSQL port:" 10 60 5432 3>&1 1>&2 2>&3)
DB_NAME=$(whiptail --inputbox "PostgreSQL database name:" 10 60 immich 3>&1 1>&2 2>&3)
DB_USER=$(whiptail --inputbox "PostgreSQL username:" 10 60 immich 3>&1 1>&2 2>&3)
DB_PASS=$(whiptail --passwordbox "PostgreSQL password:" 10 60 3>&1 1>&2 2>&3)

# ---------- REDIS ----------
USE_REDIS=$(whiptail --yesno "Do you want to use Redis?" 10 60 && echo "yes" || echo "no")

if [ "$USE_REDIS" = "yes" ]; then
  REDIS_HOST=$(whiptail --inputbox "Redis hostname:" 10 60 redis 3>&1 1>&2 2>&3)
  REDIS_PORT=$(whiptail --inputbox "Redis port:" 10 60 6379 3>&1 1>&2 2>&3)
fi

# ---------- STORAGE ----------
STORAGE_TYPE=$(whiptail --menu "Select storage type:" 12 60 2 \
  "volume" "Docker volume" \
  "bind" "Bind mount" 3>&1 1>&2 2>&3)

if [ "$STORAGE_TYPE" = "volume" ]; then
  VOLUME_NAME="immich_library"
  docker volume inspect "$VOLUME_NAME" &>/dev/null || docker volume create "$VOLUME_NAME" >/dev/null
  VOLUME_DEF="-v ${VOLUME_NAME}:/usr/src/app/upload"
else
  HOST_PATH=$(whiptail --inputbox "Enter host path for bind mount:" 10 60 /srv/immich/library 3>&1 1>&2 2>&3)
  mkdir -p "$HOST_PATH"
  VOLUME_DEF="-v ${HOST_PATH}:/usr/src/app/upload"
fi

# ---------- ENV VARS ----------
ENV_VARS=(
  -e DB_HOSTNAME="$DB_HOST"
  -e DB_PORT="$DB_PORT"
  -e DB_DATABASE_NAME="$DB_NAME"
  -e DB_USERNAME="$DB_USER"
  -e DB_PASSWORD="$DB_PASS"
)

if [ "$USE_REDIS" = "yes" ]; then
  ENV_VARS+=(
    -e REDIS_HOSTNAME="$REDIS_HOST"
    -e REDIS_PORT="$REDIS_PORT"
  )
fi

# ---------- REMOVE OLD CONTAINERS ----------
docker rm -f immich immich-backend &>/dev/null || true

# ---------- CREATE CONTAINERS ----------
docker run -d \
  --name immich \
  --hostname immich \
  --network produktiv \
  "${ENV_VARS[@]}" \
  $VOLUME_DEF \
  ghcr.io/immich-app/immich-server:release \
  || error_exit "Failed to start Immich server."

docker run -d \
  --name immich-backend \
  --hostname immich-backend \
  --network produktiv \
  "${ENV_VARS[@]}" \
  $VOLUME_DEF \
  ghcr.io/immich-app/immich-server:release \
  start.sh microservices \
  || error_exit "Failed to start Immich backend."

# ---------- SUCCESS ----------
whiptail --title "Immich Installer" --msgbox \
"Installation successful!

Immich is running internally via Docker.

Server:
  Hostname: immich
  Port: 3001

Use a reverse proxy to expose it externally." \
12 60
