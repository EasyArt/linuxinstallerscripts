#!/bin/bash
# ______               _ _     _                    
#|  ____|             | (_)   | |                   
#| |__  __  _____ __ _| |_  __| |_ __ __ ___      __
#|  __| \ \/ / __/ _` | | |/ _` | '__/ _` \ \ /\ / /
#| |____ >  < (_| (_| | | | (_| | | | (_| |\ V  V / 
#|______/_/\_\___\__,_|_|_|\__,_|_|  \__,_| \_/\_/  
# Raphael Jäger

set -e

# Container names / hostnames
FRONTEND="excalidraw"
ROOM="excalidrawroom"
STORAGE="excalidrawstorage"

# Images
IMG_FRONTEND="excalidraw/excalidraw:latest"
IMG_ROOM="excalidraw/excalidraw-room:latest"
IMG_STORAGE="kiliandeca/excalidraw-storage-backend:latest"

# Network
NETWORK="produktiv"

# Ensure whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
  echo "Installing whiptail..."
  apt-get update -y
  apt-get install -y whiptail
fi

# Check if network exists
if ! docker network ls | grep -q "$NETWORK"; then
  whiptail --title "Docker Network Missing" --msgbox \
  "The docker network '$NETWORK' does not exist. Please create it or install Docker using the shQuick script." \
  10 80
  exit 1
fi

# Start frontend (hostname set)
docker run -d \
  --name "$FRONTEND" \
  --hostname "$FRONTEND" \
  --network "$NETWORK" \
  -e VITE_APP_WS_SERVER_URL="http://$ROOM:3002" \
  -e VITE_APP_STORAGE_BACKEND="http" \
  -e VITE_APP_HTTP_STORAGE_BACKEND_URL="http://$STORAGE:8080/api/v2" \
  -e VITE_APP_BACKEND_V2_GET_URL="http://$STORAGE:8080/api/v2/scenes/" \
  -e VITE_APP_BACKEND_V2_POST_URL="http://$STORAGE:8080/api/v2/scenes/" \
  -e VITE_APP_DISABLE_TRACKING="true" \
  "$IMG_FRONTEND"

# Start room server (hostname set)
docker run -d \
  --name "$ROOM" \
  --hostname "$ROOM" \
  --network "$NETWORK" \
  -e PORT="3002" \
  "$IMG_ROOM"

# Start storage backend (hostname set)
docker run -d \
  --name "$STORAGE" \
  --hostname "$STORAGE" \
  --network "$NETWORK" \
  -e PORT="8080" \
  -e STORAGE_URI="sqlite://data/storage.db" \
  -e GLOBAL_PREFIX="/api/v2" \
  -v excalidraw_storage_data:/data \
  "$IMG_STORAGE"

# Success message
whiptail --title "Installation Complete" --msgbox \
"Excalidraw with room and storage has been successfully installed." \
10 80
