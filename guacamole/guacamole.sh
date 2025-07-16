#!/bin/bash
#                                             _      
#                                            | |     
#  __ _ _   _  __ _  ___ __ _ _ __ ___   ___ | | ___ 
# / _` | | | |/ _` |/ __/ _` | '_ ` _ \ / _ \| |/ _ \
#| (_| | |_| | (_| | (_| (_| | | | | | | (_) | |  __/
# \__, |\__,_|\__,_|\___\__,_|_| |_| |_|\___/|_|\___|
#  __/ |                                             
# |___/                                              
#	guacamole docker Raphael Jäger 15.07.2025

set -euo pipefail
# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Installing whiptail..."
    apt update && apt install -y whiptail
fi

# Install mysql-client (needed for connectivity check and SQL execution)
apt update && apt install -y mariadb-client

# Check if docker network 'produktiv' exists
if ! docker network ls --format '{{.Name}}' | grep -q '^produktiv$'; then
    whiptail --title "Docker Network Missing" \
        --msgbox "The 'produktiv' network does not exist.\n\nIt seems you did not use the shQuick install script for Docker installation.\nPlease create the 'produktiv' network manually." 12 60
    exit 1
fi

# Prompt for MySQL connection details
MYSQL_HOSTNAME=$(whiptail --inputbox "Enter MySQL Server Hostname or IP:" 8 60 --title "MySQL Hostname" 3>&1 1>&2 2>&3)
MYSQL_DATABASE=$(whiptail --inputbox "Enter MySQL Database Name:" 8 60 --title "MySQL Database" 3>&1 1>&2 2>&3)
MYSQL_USER=$(whiptail --inputbox "Enter MySQL Username:" 8 60 --title "MySQL User" 3>&1 1>&2 2>&3)
MYSQL_PASSWORD=$(whiptail --passwordbox "Enter MySQL Password:" 8 60 --title "MySQL Password" 3>&1 1>&2 2>&3)
MYSQL_PORT=$(whiptail --inputbox "Enter MySQL Port:" 8 60 "3306" --title "MySQL Port" 3>&1 1>&2 2>&3)

# Validate database name (simple pattern)
if [[ ! "$MYSQL_DATABASE" =~ ^[a-zA-Z0-9_]+$ ]]; then
    whiptail --title "Invalid Database Name" \
        --msgbox "The database name is invalid.\nOnly letters, numbers, and underscores are allowed." 10 60
    exit 1
fi

# Test MySQL connection
if ! mysqladmin ping -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --silent; then
    whiptail --title "MySQL Connection Failed" \
        --msgbox "Unable to connect to the MySQL server with the provided credentials.\n\nAborting installation." 10 60
    exit 1
fi

GUACD_HOSTNAME="guacd"

# Create volume only if it doesn't exist
if ! docker volume ls --format '{{.Name}}' | grep -q '^guacamole$'; then
    docker volume create guacamole
fi

# Create guacd container
docker run -d \
    --name guacd \
    --hostname "$GUACD_HOSTNAME" \
    --network produktiv \
    --restart always \
    guacamole/guacd

# Create guacamole container
docker run -d \
    --name guacamole \
    --hostname guacamole \
    --network produktiv \
    -v guacamole:/guacamole \
    -e MYSQL_HOSTNAME="$MYSQL_HOSTNAME" \
    -e MYSQL_DATABASE="$MYSQL_DATABASE" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -e MYSQL_PORT="$MYSQL_PORT" \
    -e GUACD_HOSTNAME="guacd" \
    --restart always \
    guacamole/guacamole

# URLs der SQL-Dateien
SCHEMA_URL="https://example.com/guacamole/schema.sql"
ADMIN_URL="https://example.com/guacamole/admin.sql"

# Temporäre Dateien
SCHEMA_FILE="/tmp/guacamole_schema.sql"
ADMIN_FILE="/tmp/guacamole_admin.sql"

# Herunterladen
curl -fsSL "$SCHEMA_URL" -o "$SCHEMA_FILE"
curl -fsSL "$ADMIN_URL" -o "$ADMIN_FILE"

# Ausführen
mysql -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SCHEMA_FILE"
mysql -h "$MYSQL_HOSTNAME" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$ADMIN_FILE"

# Aufräumen
rm -f "$SCHEMA_FILE" "$ADMIN_FILE"

# mysql-client deinstallieren
apt purge -y mariadb-client && apt autoremove -y

# Erfolgsmeldung
whiptail --title "Installation Complete" \
    --msgbox "Guacamole und guacd wurden erfolgreich eingerichtet!\nDie Datenbank wurde mit Schema und Admin-User befüllt." 12 60
