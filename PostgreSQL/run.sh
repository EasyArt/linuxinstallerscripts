#!/bin/bash
# _____          _                  _____  ____  _      
#|  __ \        | |                / ____|/ __ \| |     
#| |__) |__  ___| |_ __ _ _ __ ___| (___ | |  | | |     
#|  ___/ _ \/ __| __/ _` | '__/ _ \\___ \| |  | | |     
#| |  | (_) \__ \ || (_| | | |  __/____) | |__| | |____ 
#|_|   \___/|___/\__\__, |_|  \___|_____/ \___\_\______|
#                    __/ |                              
#                   |___/                               
#	Raphael Jäger
set -e

# -----------------------------
# Helper functions
# -----------------------------
random_password() {
    tr -dc 'A-Za-z0-9!@#$%&*' </dev/urandom | head -c 16
}

# -----------------------------
# Install whiptail if missing
# -----------------------------
if ! command -v whiptail >/dev/null 2>&1; then
    apt update -y >/dev/null 2>&1
    apt install -y whiptail >/dev/null 2>&1
fi

# -----------------------------
# Selection menu
# -----------------------------
CHOICES=$(whiptail --title "PostgreSQL Setup" \
--checklist "Select what you want to install:" 15 60 2 \
"PGDB" "PostgreSQL Database" OFF \
"PGADMIN" "pgAdmin Web Interface" OFF \
3>&1 1>&2 2>&3)

if [ -z "$CHOICES" ]; then
    exit 0
fi

# -----------------------------
# Check Docker network
# -----------------------------
if ! docker network ls --format '{{.Name}}' | grep -q "^produktiv$"; then
    whiptail --title "Docker Network Missing" --msgbox \
"The Docker network 'produktiv' does not exist.

Please create it manually or install Docker using the shQuick script." 12 60
    exit 1
fi

# -----------------------------
# Variables
# -----------------------------
INSTALL_PGDB=false
INSTALL_PGADMIN=false

PG_DB_USER="pgadmin"
PG_DB_PASS=""
PGADMIN_EMAIL="admin@local"
PGADMIN_PASS=""

# -----------------------------
# Parse selection
# -----------------------------
for choice in $CHOICES; do
    case $choice in
        \"PGDB\")
            INSTALL_PGDB=true
            ;;
        \"PGADMIN\")
            INSTALL_PGADMIN=true
            ;;
    esac
done

# -----------------------------
# Install PostgreSQL
# -----------------------------
if $INSTALL_PGDB; then
    PG_DB_PASS=$(random_password)

    docker run -d \
        --name postgres \
        --hostname postgres \
        --restart always \
        --network produktiv \
        -p 5432:5432 \
        -e POSTGRES_USER="$PG_DB_USER" \
        -e POSTGRES_PASSWORD="$PG_DB_PASS" \
        postgres:latest
fi

# -----------------------------
# Install pgAdmin
# -----------------------------
if $INSTALL_PGADMIN; then
    PGADMIN_PASS=$(random_password)

    docker run -d \
        --name pgadmin \
        --hostname pgadmin \
        --restart always \
        --network produktiv \
        -e PGADMIN_DEFAULT_EMAIL="$PGADMIN_EMAIL" \
        -e PGADMIN_DEFAULT_PASSWORD="$PGADMIN_PASS" \
        dpage/pgadmin4:latest
fi

# -----------------------------
# Summary message
# -----------------------------
SUMMARY="Installation finished successfully.

"

if $INSTALL_PGDB; then
SUMMARY+="PostgreSQL (PGDB):
Host: postgres
Port: 5432
User: $PG_DB_USER
Password: $PG_DB_PASS

"
fi

if $INSTALL_PGADMIN; then
SUMMARY+="pgAdmin:
URL: http://pgadmin (via Reverse Proxy)
Login Email: $PGADMIN_EMAIL
Password: $PGADMIN_PASS

"
fi

SUMMARY+="Note:
pgAdmin runs internally on port 80 and must be configured in your reverse proxy."

whiptail --title "Access Information" --msgbox "$SUMMARY" 20 70
