#!/bin/bash
#  _____                          
# / ____|                         
#| (___   ___ _ ____   _____ _ __ 
# \___ \ / _ \ '__\ \ / / _ \ '__|
# ____) |  __/ |   \ V /  __/ |   
#|_____/ \___|_|    \_/ \___|_|   
# Serversetup by Raphael Jäger 04.03.2025                                 

# Function to modify /etc/profile (Beautiful login)
modify_profile() {
    PROFILE_CONTENT="\nclear\nfiglet -f big \"\$(hostname)\"\necho \"==============================\"\necho \"Support: shquick@jaeger-raphael.de\"\necho \"==============================\"\nneofetch\n"

    if ! grep -q "Support: shquick@jaeger-raphael.de" /etc/profile; then
        echo -e "# The following entries were added by this script. Do not add again.\n$PROFILE_CONTENT" >> /etc/profile
    fi
    echo "Beautiful login applied!"
}

# Function to modify /etc/bash.bashrc (Beautiful bash)
modify_bash() {
    cat > /etc/bash.bashrc << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.
[ -z "$PS1" ] && return

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

if [[ ${EUID} == 0 ]] ; then
    PS1='\[\033[48;2;221;75;57;38;2;255;255;255m\] \$ \[\033[48;2;0;135;175;38;2;221;75;57m\]\[\033[48;2;0;135;175;38;2;255;255;255m\] \h \[\033[48;2;83;85;85;38;2;0;135;175m\]\[\033[48;2;83;85;85;38;2;255;255;255m\] \w \[\033[49;38;2;83;85;85m\]\[\033[00m\] '
else
    PS1='\[\033[48;2;105;121;16;38;2;255;255;255m\] \$ \[\033[48;2;0;135;175;38;2;105;121;16m\]\[\033[48;2;0;135;175;38;2;255;255;255m\] \u@\h \[\033[48;2;83;85;85;38;2;0;135;175m\]\[\033[48;2;83;85;85;38;2;255;255;255m\] \w \[\033[49;38;2;83;85;85m\]\[\033[00m\] '
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
EOF

    cp /etc/bash.bashrc /root/.bashrc
    echo "Beautiful bash applied!"
}

# Function to install Cockpit
install_cockpit() {
    COCKPIT_CHOICE=$(whiptail --title "Cockpit Installation" --menu "Choose an installation type:" 15 50 2 \
    "Agent only" "Install Cockpit Agent only" \
    "Full" "Install Cockpit with Web Interface" 3>&1 1>&2 2>&3)

    if [ "$COCKPIT_CHOICE" == "Agent only" ]; then
        apt update && apt install -y cockpit-system
        echo "Cockpit agent installed!"
    elif [ "$COCKPIT_CHOICE" == "Full" ]; then
        apt update && apt install -y cockpit
        systemctl enable --now cockpit.socket
        echo "Cockpit with web interface installed!"
    fi
}

# Install required packages
apt update && apt install -y whiptail neofetch figlet sudo htop curl

# Main menu
CHOICE=$(whiptail --title "Setup Menu" --menu "Choose an option:" 15 50 3 \
"Beautiful login" "Modify /etc/profile" \
"Beautiful bash" "Modify /etc/bash.bashrc" \
"Cockpit" "Install Cockpit" 3>&1 1>&2 2>&3)

case $CHOICE in
    "Beautiful login")
        modify_profile
        ;;
    "Beautiful bash")
        modify_bash
        ;;
    "Cockpit")
        install_cockpit
        ;;
    *)
        echo "No valid option selected. Exiting."
        exit 1
        ;;
esac

echo "Setup completed. Please log out and log back in to see the changes."
