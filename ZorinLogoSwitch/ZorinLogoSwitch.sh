#!/usr/bin/env bash
# ______          _       _                       _____         _ _       _     
#|___  /         (_)     | |                     / ____|       (_) |     | |    
#   / / ___  _ __ _ _ __ | |     ___   __ _  ___| (_____      ___| |_ ___| |__  
#  / / / _ \| '__| | '_ \| |    / _ \ / _` |/ _ \\___ \ \ /\ / / | __/ __| '_ \ 
# / /_| (_) | |  | | | | | |___| (_) | (_| | (_) |___) \ V  V /| | || (__| | | |
#/_____\___/|_|  |_|_| |_|______\___/ \__, |\___/_____/ \_/\_/ |_|\__\___|_| |_|
#                                      __/ |                                    
#                                     |___/                                     
#Raphael Jäger

set -e

TARGET_ICON="/usr/share/gnome-shell/extensions/zorin-menu@zorinos.com/zorin-icon-symbolic.svg"
BACKUP_ICON="${TARGET_ICON}.bak"

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root or with sudo."
  exit 1
fi

echo "Zorin OS Start Menu Icon Manager"
echo "--------------------------------"
echo

# --- whiptail check / install ---
if ! command -v whiptail >/dev/null 2>&1; then
  echo "whiptail not found. Installing..."
  apt update
  apt install -y whiptail
fi

# --- Main choice ---
ACTION=$(whiptail --title "Start Menu Icon" \
  --menu "Choose what you want to do:" 15 70 2 \
  "restore" "Restore original Zorin logo" \
  "custom"  "Use a custom SVG logo" \
  3>&1 1>&2 2>&3)

[[ $? -ne 0 ]] && exit 0

# --- Restore original logo ---
if [[ "$ACTION" == "restore" ]]; then
  if [[ ! -f "$BACKUP_ICON" ]]; then
    whiptail --title "Restore failed" \
      --msgbox "No backup file found:\n$BACKUP_ICON\n\nNothing to restore." 12 70
    exit 1
  fi

  echo "Restoring original Zorin logo..."
  cp "$BACKUP_ICON" "$TARGET_ICON"
  chown root:root "$TARGET_ICON"
  chmod 644 "$TARGET_ICON"

  echo "Original Zorin logo restored."
fi

# --- Custom logo ---
if [[ "$ACTION" == "custom" ]]; then
  echo
  echo "Please enter the FULL path to your SVG icon."
  echo "TAB completion is supported."
  echo

  read -e -p "SVG file path: " ICON_PATH

  if [[ -z "$ICON_PATH" ]]; then
    echo "ERROR: No file path provided."
    exit 1
  fi

  if [[ ! -f "$ICON_PATH" ]]; then
    echo "ERROR: File does not exist."
    exit 1
  fi

  if [[ "${ICON_PATH##*.}" != "svg" ]]; then
    echo "ERROR: File is not an .svg file."
    exit 1
  fi

  if [[ ! -f "$TARGET_ICON" ]]; then
    echo "ERROR: Target icon not found:"
    echo "  $TARGET_ICON"
    exit 1
  fi

  echo "Creating backup..."
  cp "$TARGET_ICON" "$BACKUP_ICON"

  echo "Replacing icon..."
  cp "$ICON_PATH" "$TARGET_ICON"
  chown root:root "$TARGET_ICON"
  chmod 644 "$TARGET_ICON"

  echo "Custom icon installed successfully."
fi

echo

# --- Logout prompt ---
CHOICE=$(whiptail --title "Logout required" \
  --menu "A logout is required for the change to take effect." 15 70 3 \
  "now"   "Log out automatically now" \
  "later" "I will log out manually" \
  "skip"  "Do nothing" \
  3>&1 1>&2 2>&3)

case "$CHOICE" in
  now)
    echo "Logging out user..."
    loginctl terminate-user "${SUDO_USER:-$USER}"
    ;;
  later)
    echo "Please log out manually later."
    ;;
  skip)
    echo "No logout performed."
    ;;
esac
