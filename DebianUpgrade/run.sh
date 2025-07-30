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
#!/bin/bash
set -e

# Ensure script is run as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

# Install whiptail if not present
if ! command -v whiptail &> /dev/null; then
    apt update -qq
    apt install -y whiptail
fi

# Ordered list of Debian releases
RELEASE_CHAIN=("stretch" "buster" "bullseye" "bookworm" "trixie")
declare -A RELEASE_NAMES=(
    [stretch]="Debian 9"
    [buster]="Debian 10"
    [bullseye]="Debian 11"
    [bookworm]="Debian 12"
    [trixie]="Debian 13"
)

# Detect current version
CURRENT_VERSION=$(lsb_release -cs)

# Determine next target version
TARGET_VERSION=""
for i in "${!RELEASE_CHAIN[@]}"; do
    if [[ "${RELEASE_CHAIN[$i]}" == "$CURRENT_VERSION" && $((i+1)) -lt ${#RELEASE_CHAIN[@]} ]]; then
        TARGET_VERSION="${RELEASE_CHAIN[$((i+1))]}"
        break
    fi
done

# No higher version available
if [[ -z "$TARGET_VERSION" ]]; then
    whiptail --title "Debian Upgrade" --msgbox "You are already using the latest Debian release: $CURRENT_VERSION." 8 60
    exit 0
fi

# Ask for confirmation
whiptail --title "Upgrade Preparation" --yesno \
"You are currently using: ${RELEASE_NAMES[$CURRENT_VERSION]} ($CURRENT_VERSION)\n\nThe upgrade target is:\n${RELEASE_NAMES[$TARGET_VERSION]} ($TARGET_VERSION)\n\n⚠️ Please make a backup before proceeding.\n\nDo you want to continue?" \
15 60 || exit 0

# Backup sources.list
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# Replace codename in sources.list
sed -i "s/${CURRENT_VERSION}/${TARGET_VERSION}/g" /etc/apt/sources.list

# Update Docker repo if exists
DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
if [[ -f "$DOCKER_LIST" ]]; then
    sed -i "s/${CURRENT_VERSION}/${TARGET_VERSION}/g" "$DOCKER_LIST"
fi

# Run upgrade
apt update -y -qq
apt full-upgrade -y
apt autoremove -y

# Notify user
whiptail --title "Upgrade Complete" --msgbox \
"The upgrade to ${RELEASE_NAMES[$TARGET_VERSION]} has been completed.\n\nA system reboot is recommended." \
10 60

# Offer reboot
if whiptail --yesno "Would you like to reboot now?" 8 60; then
    reboot
fi
