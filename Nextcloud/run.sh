#!/bin/bash
# _   _           _       _                 _ 
#| \ | |         | |     | |               | |
#|  \| | _____  _| |_ ___| | ___  _   _  __| |
#| . ` |/ _ \ \/ / __/ __| |/ _ \| | | |/ _` |
#| |\  |  __/>  <| || (__| | (_) | |_| | (_| |
#|_| \_|\___/_/\_\\__\___|_|\___/ \__,_|\__,_|
# Raphael Jäger                                             

set -e

function error_exit {
    whiptail --title "Error" --msgbox "$1" 10 60
    exit 1
}

# --- Check for whiptail ---
if ! command -v whiptail &>/dev/null; then
    echo "Installing whiptail..."
    sudo apt update && sudo apt install -y whiptail || error_exit "Failed to install whiptail."
fi

# --- Check Docker network ---
if ! docker network inspect produktiv &>/dev/null; then
    whiptail --title "Missing Docker Network" --msgbox "Docker was not installed via shQuick.\nPlease create the 'produktiv' network manually." 10 60
    exit 1
fi

# --- User input ---
TRUSTED_PROXIES=$(whiptail --title "Trusted Proxies" --inputbox "Enter trusted proxy IPs (comma-separated):" 10 60 "10.0.0.0/8" 3>&1 1>&2 2>&3)

if whiptail --title "Data Directory" --yesno "Do you want to use a custom data directory path?" 10 60; then
    USE_CUSTOM_PATH="yes"
else
    USE_CUSTOM_PATH="no"
fi

if [ "$USE_CUSTOM_PATH" = "yes" ]; then
    DATADIR=$(whiptail --title "Custom Data Directory" --inputbox "Enter full host path for data (e.g. /mnt/storage/nextcloud):" 10 60 "/mnt/storage/nextcloud" 3>&1 1>&2 2>&3)
    mkdir -p "$DATADIR"
    chown -R 33:33 "$DATADIR"
    chmod -R 750 "$DATADIR"
    DATADIR_CONTAINER="/mnt/data"
fi

USE_REDIS=false
if whiptail --title "Redis" --yesno "Do you want to use Redis for caching?" 10 60; then
    USE_REDIS=true
    REDIS_IP=$(whiptail --title "Redis IP" --inputbox "Enter Redis server IP:" 10 60 "127.0.0.1" 3>&1 1>&2 2>&3)
    REDIS_PORT=$(whiptail --title "Redis Port" --inputbox "Enter Redis port:" 10 60 "6379" 3>&1 1>&2 2>&3)
fi

LANGUAGE=$(whiptail --title "Default Language" --radiolist "Choose default language:" 15 60 2 \
"de" "German" ON \
"en" "English" OFF 3>&1 1>&2 2>&3)

NEXTCLOUD_HOST=$(whiptail --title "Nextcloud URL" --inputbox "Enter your Nextcloud URL without https:// (e.g. cloud.example.com):" 10 60 "cloud.example.com" 3>&1 1>&2 2>&3)

# --- Set default phone region ---
PHONE_REGION="US"
[ "$LANGUAGE" = "de" ] && PHONE_REGION="DE"

# --- Prepare temporary config.php ---
TEMP_DIR=$(mktemp -d)
CONFIG_FILE="$TEMP_DIR/config.php"

cat <<EOF > "$CONFIG_FILE"
<?php
\$CONFIG = array (
  'trusted_proxies' => explode(',', '$TRUSTED_PROXIES'),
  'default_language' => '$LANGUAGE',
  'default_phone_region' => '$PHONE_REGION',
  'overwrite.cli.url' => 'https://$NEXTCLOUD_HOST',
  'overwritehost' => '$NEXTCLOUD_HOST',
  'overwriteprotocol' => 'https',
EOF

if [ "$USE_CUSTOM_PATH" = "yes" ]; then
cat <<EOF >> "$CONFIG_FILE"
  'datadirectory' => '$DATADIR_CONTAINER',
EOF
fi

if [ "$USE_REDIS" = true ]; then
cat <<EOF >> "$CONFIG_FILE"
  'memcache.distributed' => '\\\\OC\\\\Memcache\\\\Redis',
  'memcache.local' => '\\\\OC\\\\Memcache\\\\Redis',
  'redis' => array(
    'host' => '$REDIS_IP',
    'port' => $REDIS_PORT,
    'timeout' => 0.0,
  ),
EOF
fi

echo ");" >> "$CONFIG_FILE"

# --- Start Nextcloud container ---
DOCKER_CMD="docker run -d --restart always --name nextcloud --hostname nextcloud --network produktiv -v nextcloud:/var/www/html"

if [ "$USE_CUSTOM_PATH" = "yes" ]; then
    DOCKER_CMD+=" -v $DATADIR:$DATADIR_CONTAINER"
fi

DOCKER_CMD+=" nextcloud"

eval $DOCKER_CMD || error_exit "Failed to start the Nextcloud container."

# --- Copy config.php into container ---
sleep 5
docker cp "$CONFIG_FILE" nextcloud:/var/www/html/config/config.php || error_exit "Failed to copy config.php into container."

# --- Set correct permissions ---
docker exec nextcloud chown www-data:www-data /var/www/html/config/config.php || error_exit "Failed to set permissions on config.php"

# --- Install smbclient and set crontab ---
docker exec -it nextcloud apt update && apt install smbclient -y
(crontab -l 2>/dev/null ; echo "0 1 * * * docker exec nextcloud sh -c 'apt update && apt install smbclient -y'") | crontab -

# --- Done ---
whiptail --title "Installation Complete" --msgbox "Nextcloud has been successfully installed!\nOpen https://$NEXTCLOUD_HOST to complete the setup." 10 60

rm -rf "$TEMP_DIR"

