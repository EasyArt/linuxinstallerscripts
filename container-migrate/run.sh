#!/bin/bash
#                 _        _                                  _                 _       
#                | |      (_)                                (_)               | |      
#  ___ ___  _ __ | |_ __ _ _ _ __   ___ _ __ ______ _ __ ___  _  __ _ _ __ __ _| |_ ___ 
# / __/ _ \| '_ \| __/ _` | | '_ \ / _ \ '__|______| '_ ` _ \| |/ _` | '__/ _` | __/ _ \
#| (_| (_) | | | | || (_| | | | | |  __/ |         | | | | | | | (_| | | | (_| | ||  __/
# \___\___/|_| |_|\__\__,_|_|_| |_|\___|_|         |_| |_| |_|_|\__, |_|  \__,_|\__\___|
#                                                                __/ |                  
#                                                               |___/                   
#	Raphael Jäger

# Advanced Docker Migration Script with Progress UI

set -e

# --- Dependencies ---
install_pkg() {
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y "$1"
    elif command -v yum &> /dev/null; then
        sudo yum install -y "$1"
    else
        echo "Install $1 manually"; exit 1
    fi
}

for cmd in whiptail sshpass jq pv; do
    if ! command -v $cmd &> /dev/null; then
        install_pkg $cmd
    fi
done

# --- Input ---
TARGET_IP=$(whiptail --inputbox "Target IP:" 10 60 3>&1 1>&2 2>&3)
TARGET_PORT=$(whiptail --inputbox "SSH Port:" 10 60 "22" 3>&1 1>&2 2>&3)
TARGET_USER=$(whiptail --inputbox "SSH Username:" 10 60 3>&1 1>&2 2>&3)
TARGET_PASS=$(whiptail --passwordbox "SSH Password:" 10 60 3>&1 1>&2 2>&3)

# --- Checks ---
command -v docker &> /dev/null || { whiptail --msgbox "Docker missing (source)" 10 50; exit 1; }
sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" -o StrictHostKeyChecking=no $TARGET_USER@$TARGET_IP "command -v docker" || {
    whiptail --msgbox "Docker missing (target)" 10 50; exit 1; }

# --- Select Containers ---
OPTIONS=()
for c in $(docker ps --format "{{.Names}}"); do
    OPTIONS+=("$c" "" OFF)
done

SELECTED=$(whiptail --checklist "Select containers" 20 78 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
TOTAL=$(echo $SELECTED | wc -w)
COUNT=0

# --- Progress helpers ---
progress_global() {
    P=$((COUNT*100/TOTAL))
    echo $P
}

# --- Loop ---
for CONTAINER in $SELECTED; do
    CONTAINER=$(echo $CONTAINER | tr -d '"')
    COUNT=$((COUNT+1))

    (
    echo 10
    echo "XXX"; echo "[$CONTAINER] Inspecting..."; echo "XXX"

    INSPECT=$(docker inspect $CONTAINER)
    IMAGE=$(echo "$INSPECT" | jq -r '.[0].Config.Image')

    echo 20
    echo "XXX"; echo "Pulling image..."; echo "XXX"

    sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "docker pull $IMAGE" >/dev/null

    echo 30
    echo "XXX"; echo "Networks..."; echo "XXX"

    for net in $(echo "$INSPECT" | jq -r '.[0].NetworkSettings.Networks | keys[]'); do
        sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP \
        "docker network inspect $net >/dev/null 2>&1 || docker network create $net"
    done

    echo 40
    echo "XXX"; echo "Volumes..."; echo "XXX"

    for mount in $(echo "$INSPECT" | jq -c '.[0].Mounts[]?'); do
        TYPE=$(echo $mount | jq -r '.Type')
        SRC=$(echo $mount | jq -r '.Source')
        NAME=$(echo $mount | jq -r '.Name')

        if [ "$TYPE" == "volume" ]; then
            sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "docker volume create $NAME" >/dev/null

            SIZE=$(docker run --rm -v $NAME:/data alpine sh -c "du -sb /data | cut -f1")

            docker run --rm -v $NAME:/data alpine tar cf - -C /data . \
            | pv -s $SIZE \
            | sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP \
            "docker run -i --rm -v $NAME:/data alpine tar xf - -C /data"
        fi

        if [ "$TYPE" == "bind" ]; then
            sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "mkdir -p $SRC"

            SIZE=$(du -sb "$SRC" | cut -f1)

            tar cf - -C "$SRC" . \
            | pv -s $SIZE \
            | sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP \
            "tar xf - -C $SRC"
        fi
    done

    echo 70
    echo "XXX"; echo "Config..."; echo "XXX"

    PORT_ARGS=""
    for p in $(echo "$INSPECT" | jq -r '.[0].HostConfig.PortBindings | keys[]?'); do
        HP=$(echo "$INSPECT" | jq -r ".[0].HostConfig.PortBindings[\"$p\"][0].HostPort")
        PORT_ARGS+=" -p $HP:${p%%/*}"
    done

    ENV_ARGS=""
    for e in $(echo "$INSPECT" | jq -r '.[0].Config.Env[]'); do
        ENV_ARGS+=" -e $e"
    done

    RESTART=$(echo "$INSPECT" | jq -r '.[0].HostConfig.RestartPolicy.Name')
    [ "$RESTART" != "" ] && RESTART="--restart $RESTART"

    USER=$(echo "$INSPECT" | jq -r '.[0].Config.User')
    [ "$USER" != "" ] && USER="--user $USER"

    CMD=$(echo "$INSPECT" | jq -r '.[0].Config.Cmd | join(" ")')

    echo 90
    echo "XXX"; echo "Starting container..."; echo "XXX"

    sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP \
    "docker run -d --name $CONTAINER $PORT_ARGS $ENV_ARGS $RESTART $USER $IMAGE $CMD" >/dev/null

    echo 100
    echo "XXX"; echo "Done"; echo "XXX"

    ) | whiptail --gauge "Migrating $CONTAINER" 10 70 0

done

whiptail --msgbox "All migrations finished" 10 60
