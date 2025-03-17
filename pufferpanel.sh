#!/bin/bash
# _____        __  __                                 _ 
#|  __ \      / _|/ _|                               | |
#| |__) |   _| |_| |_ ___ _ __ _ __   __ _ _ __   ___| |
#|  ___/ | | |  _|  _/ _ \ '__| '_ \ / _` | '_ \ / _ \ |
#| |   | |_| | | | ||  __/ |  | |_) | (_| | | | |  __/ |
#|_|    \__,_|_| |_| \___|_|  | .__/ \__,_|_| |_|\___|_|
#                             | |                       
#                             |_|                       
# 17.03.2025 Raphael Jäger

apt install sudo -y && apt install curl -y && apt install bc -y

# Ensure whiptail is installed
if ! command -v whiptail &> /dev/null; then
    echo "Installing Whiptail..."
    sudo apt update
    sudo apt install -y whiptail
fi

# Main menu
OPTION=$(whiptail --title "PufferPanel Installation" --menu "Choose an option" 15 60 5 \
"1" "Install PufferPanel" \
"2" "Migrate PufferPanel 2 to 3" \
"3" "Create user" \
"4" "Uninstall PufferPanel" 3>&1 1>&2 2>&3)

case $OPTION in
    1)
        # Submenu for version selection
        VERSION=$(whiptail --title "PufferPanel Version" --menu "Choose the version to install" 15 60 3 \
        "2" "Install PufferPanel v2" \
        "3" "Install PufferPanel v3" 3>&1 1>&2 2>&3)
        
        if [ "$VERSION" == "2" ]; then
            curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh | sudo bash
            sudo apt-get install -y pufferpanel
            sudo systemctl enable --now pufferpanel
            sudo pufferpanel user add
        elif [ "$VERSION" == "3" ]; then
            # Check Debian version
            OS_VERSION=$(lsb_release -rs)
            if (( $(echo "$OS_VERSION < 12" | bc -l) )); then
                whiptail --title "Installation Aborted" --msgbox "Debian version $OS_VERSION detected. Please upgrade to at least Debian 12 before installing PufferPanel v3." 10 60
                exit 1
            fi
            
            curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true | sudo bash
            sudo apt update
            sudo apt-get install -y pufferpanel
            sudo systemctl enable --now pufferpanel
            sudo pufferpanel user add
        fi
        ;;
    2)
        # Check Debian version
        OS_VERSION=$(lsb_release -rs)
        if (( $(echo "$OS_VERSION < 12" | bc -l) )); then
            whiptail --title "Migration Aborted" --msgbox "Debian version $OS_VERSION detected. Please upgrade to at least Debian 12 before proceeding with the migration." 10 60
            exit 1
        fi
        
        # Migration from v2 to v3
        curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh?any=true | sudo bash
        sudo apt update
        sudo apt-get install -y pufferpanel
        sudo systemctl restart pufferpanel
        ;;
    3)
        # Create user
        sudo pufferpanel user add
        ;;
    4)
        # Uninstall PufferPanel
        sudo apt purge -y pufferpanel
        ;;
    *)
        echo "Invalid option selected or canceled."
        exit 1
        ;;
esac
