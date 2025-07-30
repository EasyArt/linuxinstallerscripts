#!/bin/bash
#  _____           _       _                   _    _                                      _        
#|  __ \         | |     (_)                 | |  | |                                    | |       
#| |  | |   ___  | |__    _    __ _   _ __   | |  | |  _ __     __ _   _ __    __ _    __| |   ___ 
#| |  | |  / _ \ | '_ \  | |  / _` | | '_ \  | |  | | | '_ \   / _` | | '__|  / _` |  / _` |  / _ \
#| |__| | |  __/ | |_) | | | | (_| | | | | | | |__| | | |_) | | (_| | | |    | (_| | | (_| | |  __/
#|_____/   \___| |_.__/  |_|  \__,_| |_| |_|  \____/  | .__/   \__, | |_|     \__,_|  \__,_|  \___|
#                                                     | |       __/ |                              
#                                                     |_|      |___/                               
# Raphael Jäger
set -e

# Root-Prüfung
if [[ "$EUID" -ne 0 ]]; then
    echo "Bitte führe dieses Skript als root aus."
    exit 1
fi

# Whiptail installieren, falls nicht vorhanden
if ! command -v whiptail &> /dev/null; then
    apt update -qq
    apt install -y whiptail
fi

# Unterstützte Releases in Reihenfolge
declare -A DEBIAN_RELEASES
DEBIAN_RELEASES["stretch"]="Debian 9"
DEBIAN_RELEASES["buster"]="Debian 10"
DEBIAN_RELEASES["bullseye"]="Debian 11"
DEBIAN_RELEASES["bookworm"]="Debian 12"
DEBIAN_RELEASES["trixie"]="Debian 13"

# Aktuell installierte Version ermitteln
CURRENT_VERSION=$(lsb_release -cs)

# Verfügbare neuere Versionen ermitteln
UPGRADE_OPTIONS=()
FOUND_CURRENT=false
for CODE in "${!DEBIAN_RELEASES[@]}"; do
    if [[ "$CODE" == "$CURRENT_VERSION" ]]; then
        FOUND_CURRENT=true
        continue
    fi
    $FOUND_CURRENT && UPGRADE_OPTIONS+=("$CODE" "${DEBIAN_RELEASES[$CODE]}" "off")
done

# Wenn keine neueren Releases gefunden wurden
if [[ ${#UPGRADE_OPTIONS[@]} -eq 0 ]]; then
    whiptail --msgbox "Du verwendest bereits die neueste unterstützte Debian-Version ($CURRENT_VERSION)." 8 60
    exit 0
fi

# Upgrade-Ziel auswählen
TARGET_VERSION=$(whiptail --title "Debian Upgrade" --checklist \
"Dein System verwendet derzeit: ${DEBIAN_RELEASES[$CURRENT_VERSION]} ($CURRENT_VERSION)\n\nWähle die Zielversion für das Upgrade:" \
20 78 10 "${UPGRADE_OPTIONS[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

# Abbrechen
if [[ -z "$TARGET_VERSION" ]]; then
    whiptail --msgbox "Upgrade abgebrochen." 8 60
    exit 0
fi

# Hinweis anzeigen
whiptail --title "Upgrade starten" --yesno "Upgrade von ${DEBIAN_RELEASES[$CURRENT_VERSION]} auf ${DEBIAN_RELEASES[$TARGET_VERSION]}?\n\nSicherung wird dringend empfohlen!" 10 60 || exit 0

# Sicherung der APT-Quellen
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Quellen aktualisieren
sed -i "s/${CURRENT_VERSION}/${TARGET_VERSION}/g" /etc/apt/sources.list

# Docker-Repo anpassen (falls vorhanden)
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
if [[ -f "$DOCKER_LIST" ]]; then
    sed -i "s/${CURRENT_VERSION}/${TARGET_VERSION}/g" "$DOCKER_LIST"
fi

# Paketquellen aktualisieren
apt update -y -qq

# Upgrade starten
whiptail --title "Upgrade wird ausgeführt..." --infobox "Das System wird jetzt auf Debian ${DEBIAN_RELEASES[$TARGET_VERSION]} aktualisiert..." 8 60
apt full-upgrade -y
apt autoremove -y

# Erfolgsmeldung
whiptail --msgbox "Upgrade abgeschlossen! Ein Neustart wird empfohlen." 8 60

# Neustart?
if whiptail --yesno "Möchtest du das System jetzt neu starten?" 8 60; then
    reboot
fi

