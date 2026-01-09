#!/bin/bash
# _____                     _      _     
#|_   _|                   (_)    | |    
#  | |  _ __ ___  _ __ ___  _  ___| |__  
#  | | | '_ ` _ \| '_ ` _ \| |/ __| '_ \ 
# _| |_| | | | | | | | | | | | (__| | | |
#|_____|_| |_| |_|_| |_| |_|_|\___|_| |_|
# Raphael Jäger

set -e

# ================= FUNCTIONS =================
clear_stdin() {
  while read -r -t 0; do read -r; done
}

error_exit() {
  whiptail --title "Immich Installer" --msgbox "$1" 14 70
  exit 1
}

rand_pw() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 24
}

# ================= CHECKS =================
if [ "$EUID" -ne 0 ]; then
  echo "Run as root."
  exit 1
fi

command -v whiptail >/dev/null || error_exit "whiptail is required."
command -v docker >/dev/null || error_exit "Docker is required."
docker info >/dev/null || error_exit "Docker daemon not running."

docker network inspect produktiv >/dev/null || error_exit \
"Docker network 'produktiv' does not exist."

# ================= REDIS (EXTERNAL ONLY) =================
if whiptail --yesno "Use an existing Redis instance?" 10 60; then
  USE_REDIS="yes"

  REDIS_HOST=$(whiptail --inputbox "Redis hostname:" 10 60 redis 3>&1 1>&2 2>&3)
  clear_stdin

  REDIS_PORT=$(whiptail --inputbox "Redis port:" 10 60 6379 3>&1 1>&2 2>&3)
  clear_stdin
else
  USE_REDIS="no"
fi

# ================= STORAGE =================
STORAGE_TYPE=$(whiptail --menu "Select media storage type:" 12 70 2 \
  volume "Docker volume" \
  bind   "Bind mount" \
  3>&1 1>&2 2>&3)
clear_stdin

if [ "$STORAGE_TYPE" = "volume" ]; then
  UPLOAD_LOCATION="immich_upload"
  docker volume inspect "$UPLOAD_LOCATION" >/dev/null || docker volume create "$UPLOAD_LOCATION" >/dev/null
  UPLOAD_VOL="-v ${UPLOAD_LOCATION}:/data"
else
  HOST_PATH=$(whiptail --inputbox "Host path for media:" 10 70 /srv/immich/upload 3>&1 1>&2 2>&3)
  clear_stdin
  mkdir -p "$HOST_PATH"
  UPLOAD_LOCATION="$HOST_PATH"
  UPLOAD_VOL="-v ${UPLOAD_LOCATION}:/data"
fi

# ================= DATABASE =================
DB_NAME="immich"
DB_USER="immich"
DB_PASS="$(rand_pw)"

docker volume inspect immich_pgdata >/dev/null || docker volume create immich_pgdata >/dev/null

# ================= CLEANUP =================
docker rm -f \
  immich_server \
  immich_machine_learning \
  immich_postgres \
  >/dev/null 2>&1 || true

# ================= POSTGRES =================
docker run -d \
  --restart=always \
  --name immich_postgres \
  --hostname immich_postgres \
  --network produktiv \
  -e POSTGRES_DB="$DB_NAME" \
  -e POSTGRES_USER="$DB_USER" \
  -e POSTGRES_PASSWORD="$DB_PASS" \
  -e POSTGRES_INITDB_ARGS="--data-checksums" \
  -v immich_pgdata:/var/lib/postgresql/data \
  --shm-size=128m \
  ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0 \
  || error_exit "PostgreSQL failed to start."

# ================= ENV =================
ENV_VARS=(
  -e DB_HOSTNAME=immich_postgres
  -e DB_PORT=5432
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

# ================= IMMICH SERVER =================
docker run -d \
  --restart=always \
  --name immich_server \
  --hostname immich_server \
  --network produktiv \
  "${ENV_VARS[@]}" \
  $UPLOAD_VOL \
  -v /etc/localtime:/etc/localtime:ro \
  ghcr.io/immich-app/immich-server:release \
  || error_exit "Immich server failed."

# ================= IMMICH MACHINE LEARNING =================
docker volume inspect immich_model_cache >/dev/null || docker volume create immich_model_cache >/dev/null

docker run -d \
  --restart=always \
  --name immich_machine_learning \
  --hostname immich_machine_learning \
  --network produktiv \
  "${ENV_VARS[@]}" \
  -v immich_model_cache:/cache \
  ghcr.io/immich-app/immich-machine-learning:release \
  || error_exit "Immich ML failed."

# ================= DONE =================
whiptail --title "Immich installed" --msgbox \
"SUCCESS

Immich:
  Host: immich_server
  Port: 2283 (internal)

PostgreSQL:
  Host: immich_postgres
  Database: $DB_NAME
  Username: $DB_USER
  Password: $DB_PASS

Redis:
  Used: $USE_REDIS
  Host: ${REDIS_HOST:-n/a}
  Port: ${REDIS_PORT:-n/a}

Docker network:
  produktiv" \
20 75

