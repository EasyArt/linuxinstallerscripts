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

# --- Check for Docker network ---
if ! docker network inspect produktiv &>/dev/null; then
    whiptail --title "Missing Docker Network" --msgbox "Docker was not installed via shQuick.\nPlease create the 'produktiv' network manually before proceeding." 10 60
    exit 1
fi

# --- User input ---
TRUSTED_PROXIES=$(whiptail --title "Trusted Proxies" --inputbox "Enter trusted proxy IPs (comma-separated):" 10 60 "10.0.0.0/8" 3>&1 1>&2 2>&3)

USE_CUSTOM_PATH=$(whiptail --title "Data Directory" --yesno "Do you want to use a custom data directory path?" 10 60 && echo "yes" || echo "no")
if [ "$USE_CUSTOM_PATH" = "yes" ]; then
    BASEDIR=$(whiptail --title "Base Directory" --inputbox "Enter base directory path (e.g. /home/nextcloud):" 10 60 "/home/nextcloud" 3>&1 1>&2 2>&3)
    DATADIR_CONTAINER="/mnt/data"
else
    BASEDIR="/opt/nextcloud"
    DATADIR_CONTAINER="/var/www/html/data"
fi

USE_REDIS=false
if whiptail --title "Redis" --yesno "Do you want to use Redis for caching?" 10 60; then
    USE_REDIS=true
    REDIS_IP=$(whiptail --title "Redis IP" --inputbox "Enter the Redis server IP address:" 10 60 "127.0.0.1" 3>&1 1>&2 2>&3)
    REDIS_PORT=$(whiptail --title "Redis Port" --inputbox "Enter the Redis port:" 10 60 "6379" 3>&1 1>&2 2>&3)
fi

LANGUAGE=$(whiptail --title "Default Language" --radiolist "Choose default language:" 15 60 2 \
"de" "German" ON \
"en" "English" OFF 3>&1 1>&2 2>&3)

# Get Nextcloud Hostname
NEXTCLOUD_HOST=$(whiptail --title "Nextcloud URL" --inputbox "Enter your Nextcloud URL without https:// (e.g. cloud.example.com):" 10 60 "cloud.example.com" 3>&1 1>&2 2>&3)

# Determine phone region from language
if [ "$LANGUAGE" = "de" ]; then
    PHONE_REGION="DE"
else
    PHONE_REGION="US"
fi

# --- Create directories ---
mkdir -p "$BASEDIR"/{config,html,data}
chown -R 33:33 "$BASEDIR"   # www-data UID:GID = 33

# --- Create config.php ---
CONFIG_FILE="$BASEDIR/config/config.php"
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

# Add datadirectory only if custom used
if [ "$USE_CUSTOM_PATH" = "yes" ]; then
    echo "  'datadirectory' => '$DATADIR_CONTAINER'," >> "$CONFIG_FILE"
fi

# Redis block (if enabled)
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

# Close config
echo ");" >> "$CONFIG_FILE"

# --- Start Docker container ---
docker run -d \
  --name nextcloud \
  --hostname nextcloud \
  --network produktiv \
  -v "$BASEDIR/html":/var/www/html \
  -v "$BASEDIR/config":/var/www/html/config \
  -v "$BASEDIR/data":"$DATADIR_CONTAINER" \
  nextcloud || error_exit "Failed to start the Nextcloud container."

# --- Done ---
whiptail --title "Installation Complete" --msgbox "Nextcloud has been successfully installed!\nOpen https://$NEXTCLOUD_HOST to complete the setup." 10 60
