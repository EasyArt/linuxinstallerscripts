#!/usr/bin/env bash
#           _ _       _                     
#          | | |     | |                    
#  ___ ___ | | | __ _| |__   ___  _ __ __ _ 
# / __/ _ \| | |/ _` | '_ \ / _ \| '__/ _` |
#| (_| (_) | | | (_| | |_) | (_) | | | (_| |
# \___\___/|_|_|\__,_|_.__/ \___/|_|  \__,_|
#  Raphael Jäger                                           
                                           

set -euo pipefail

# --- Helpers ---------------------------------------------------------------
need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root (use sudo)." >&2
    exit 1
  fi
}

install_whiptail() {
  if ! command -v whiptail >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y whiptail
  fi
}

msg_box() {
  whiptail --title "$1" --msgbox "$2" 12 78
}

input_box() {
  local title="$1"; local prompt="$2"; local default="${3:-}"
  whiptail --title "$title" --inputbox "$prompt" 12 78 "$default" 3>&1 1>&2 2>&3
}

err() { echo "Error: $*" >&2; exit 1; }

# --- Start -----------------------------------------------------------------
need_root
install_whiptail

# Check if network "produktiv" exists
if ! docker network ls --format '{{.Name}}' | grep -qx 'produktiv'; then
  msg_box "Network missing" "The Docker network 'produktiv' does not exist.\n\nPlease create this network manually or install Docker using the shQuick script."
  exit 1
fi

# --- Collect inputs --------------------------------------------------------
valid_fqdn() {
  local fq="$1"
  [[ "$fq" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

# Nextcloud address
while :; do
  NEXTCLOUD_FQDN="$(input_box 'Nextcloud address' 'Enter your Nextcloud address (e.g., cloud.example.com):' 'cloud.example.com')" || { msg_box "Aborted" "No input provided."; exit 1; }
  if valid_fqdn "$NEXTCLOUD_FQDN"; then
    break
  else
    msg_box "Invalid hostname" "Please enter a valid FQDN like cloud.example.com."
  fi
done

# Collabora external address
while :; do
  COLLABORA_FQDN="$(input_box 'Collabora address' 'Enter your external Collabora address (e.g., collabora.example.com):' 'collabora.example.com')" || { msg_box "Aborted" "No input provided."; exit 1; }
  if valid_fqdn "$COLLABORA_FQDN"; then
    break
  else
    msg_box "Invalid hostname" "Please enter a valid FQDN like collabora.example.com."
  fi
done

DOMAIN_ESCAPED="$(printf '%s' "$NEXTCLOUD_FQDN" | sed 's/\./\\./g')"

# --- Run container ---------------------------------------------------------
IMAGE="collabora/code:latest"
NAME="collabora"
HOSTNAME_CTR="collabora"
NETWORK="produktiv"

# Remove old container if it exists
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null || true
fi

docker run -d \
  --name "$NAME" \
  --hostname "$HOSTNAME_CTR" \
  --network "$NETWORK" \
  --restart always \
  -e "domain=${DOMAIN_ESCAPED}" \
  -e "extra_params=--o:ssl.enable=false --o:ssl.termination=true --o:server_name=${COLLABORA_FQDN}" \
  -p 9980:9980 \
  "$IMAGE" >/dev/null

msg_box "Success" "Collabora container '${NAME}' is running in network '${NETWORK}'.\n\nExternal: ${COLLABORA_FQDN}\nReverseProxy Host: collabora Port: 9980"
