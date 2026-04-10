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

# ---------------- LOGGING ----------------
LOGFILE="$(pwd)/container-migrate.log"
touch "$LOGFILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

# stdout + stderr ins Log (kein Freeze)
exec > >(tee -a "$LOGFILE") 2>&1

# Fehler mit Container-Kontext
trap 'log "[ERROR][$CONTAINER] Fehler in Zeile $LINENO"' ERR

# ---------------- DEPENDENCIES ----------------
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

# ---------------- INPUT ----------------
TARGET_IP=$(whiptail --inputbox "Target IP:" 10 60 3>&1 1>&2 2>&3)
TARGET_PORT=$(whiptail --inputbox "SSH Port:" 10 60 "22" 3>&1 1>&2 2>&3)
TARGET_USER=$(whiptail --inputbox "SSH Username:" 10 60 3>&1 1>&2 2>&3)
TARGET_PASS=$(whiptail --passwordbox "SSH Password:" 10 60 3>&1 1>&2 2>&3)

log "Start migration to $TARGET_USER@$TARGET_IP:$TARGET_PORT"

# ---------------- CHECKS ----------------
command -v docker &> /dev/null || { whiptail --msgbox "Docker missing (source)" 10 50; exit 1; }

sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" -o StrictHostKeyChecking=no $TARGET_USER@$TARGET_IP "command -v docker" || {
    whiptail --msgbox "Docker missing (target)" 10 50; exit 1;
}

# ---------------- SELECT CONTAINERS ----------------
OPTIONS=()
for c in $(docker ps -a --format "{{.Names}}"); do
    OPTIONS+=("$c" "" OFF)
done

SELECTED=$(whiptail --checklist "Select containers" 20 78 10 "${OPTIONS[@]}" 3>&1 1>&2 2>&3)
TOTAL=$(echo $SELECTED | wc -w)
COUNT=0

# ---------------- BUILD RUN ----------------
build_run_cmd() {
    INSPECT="$1"

    IMAGE=$(echo "$INSPECT" | jq -r '.[0].Config.Image')
    NAME=$(echo "$INSPECT" | jq -r '.[0].Name' | sed 's#^/##')

    PORT_ARGS=""
    for p in $(echo "$INSPECT" | jq -r '.[0].HostConfig.PortBindings // {} | keys[]'); do
        HP=$(echo "$INSPECT" | jq -r ".[0].HostConfig.PortBindings[\"$p\"][0].HostPort")
        PORT_ARGS+=" -p $HP:${p%%/*}"
    done

    ENV_ARGS=""
    for e in $(echo "$INSPECT" | jq -r '.[0].Config.Env[]?'); do
        ENV_ARGS+=" -e '$e'"
    done

    VOLUME_ARGS=""
    for mount in $(echo "$INSPECT" | jq -c '.[0].Mounts[]?'); do
        TYPE=$(echo $mount | jq -r '.Type')
        SRC=$(echo $mount | jq -r '.Source')
        DST=$(echo $mount | jq -r '.Destination')
        NAMEV=$(echo $mount | jq -r '.Name')

        if [ "$TYPE" == "volume" ]; then
            VOLUME_ARGS+=" -v $NAMEV:$DST"
        fi

        if [ "$TYPE" == "bind" ]; then
            VOLUME_ARGS+=" -v $SRC:$DST"
        fi
    done

    RESTART=$(echo "$INSPECT" | jq -r '.[0].HostConfig.RestartPolicy.Name')
    [ "$RESTART" != "" ] && RESTART="--restart $RESTART"

    NET=$(echo "$INSPECT" | jq -r '.[0].HostConfig.NetworkMode')
    NET_ARG=""
    if [ "$NET" != "default" ] && [ "$NET" != "null" ]; then
        NET_ARG="--network $NET"
    fi

    CMD=$(echo "$INSPECT" | jq -r '.[0].Config.Cmd | join(" ")')

    echo "docker run -d --name $NAME $PORT_ARGS $ENV_ARGS $VOLUME_ARGS $RESTART $NET_ARG $IMAGE $CMD"
}

# ---------------- MIGRATION ----------------
for CONTAINER in $SELECTED; do
    CONTAINER=$(echo $CONTAINER | tr -d '"')
    COUNT=$((COUNT+1))

    log "[$CONTAINER] Start migration"

    (
    echo "XXX"
    echo "[$COUNT/$TOTAL] $CONTAINER"
    echo "Initialisiere..."
    echo "XXX"
    echo 5

    INSPECT=$(docker inspect $CONTAINER)

    echo "XXX"
    echo "[$COUNT/$TOTAL] $CONTAINER"
    echo "$CONTAINER Image wird geladen"
    echo "XXX"
    echo 15

    IMAGE=$(echo "$INSPECT" | jq -r '.[0].Config.Image')
    sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "docker pull $IMAGE"

    echo "XXX"
    echo "[$COUNT/$TOTAL] $CONTAINER"
    echo "$CONTAINER Volumes werden kopiert"
    echo "XXX"
    echo 30

    for mount in $(echo "$INSPECT" | jq -c '.[0].Mounts[]?'); do
        TYPE=$(echo $mount | jq -r '.Type')
        NAMEV=$(echo $mount | jq -r '.Name')

        if [ "$TYPE" == "volume" ]; then
            log "[$CONTAINER] Copy volume $NAMEV"

            sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "docker volume create $NAMEV"

            SIZE=$(docker run --rm -v $NAMEV:/data alpine sh -c "du -sb /data | cut -f1")

            docker run --rm -v $NAMEV:/data alpine tar cf - -C /data . \
            | pv -s $SIZE \
            | sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP \
            "docker run -i --rm -v $NAMEV:/data alpine tar xf - -C /data"
        fi
    done

    echo "XXX"
    echo "[$COUNT/$TOTAL] $CONTAINER"
    echo "$CONTAINER Container wird erstellt"
    echo "XXX"
    echo 70

    RUN_CMD=$(build_run_cmd "$INSPECT")
    log "[$CONTAINER] Run: $RUN_CMD"

    sshpass -p "$TARGET_PASS" ssh -p "$TARGET_PORT" $TARGET_USER@$TARGET_IP "$RUN_CMD"

    echo "XXX"
    echo "[$COUNT/$TOTAL] $CONTAINER"
    echo "Fertig"
    echo "XXX"
    echo 100

    ) | whiptail --gauge "[$COUNT/$TOTAL] $CONTAINER wird migriert" 12 70 0

    log "[$CONTAINER] Done"
done

whiptail --msgbox "Migration complete" 10 60
