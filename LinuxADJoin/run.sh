#!/bin/bash
# _      _                            _____       _       _       
#| |    (_)                     /\   |  __ \     | |     (_)      
#| |     _ _ __  _   ___  __   /  \  | |  | |    | | ___  _ _ __  
#| |    | | '_ \| | | \ \/ /  / /\ \ | |  | |_   | |/ _ \| | '_ \ 
#| |____| | | | | |_| |>  <  / ____ \| |__| | |__| | (_) | | | | |
#|______|_|_| |_|\__,_/_/\_\/_/    \_\_____/ \____/ \___/|_|_| |_|
                                                                 
# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

#Install whiptail
apt install whiptail -y

# Whiptail for inputs
DOMAIN=$(whiptail --inputbox "Please enter the domain" 8 78 --title "Domain" 3>&1 1>&2 2>&3)
DOMAIN_ADMIN_GROUP=$(whiptail --inputbox "Please enter the domain admin group" 8 78 --title "Domain Admin Group" 3>&1 1>&2 2>&3)
DOMAIN_JOIN_USER=$(whiptail --inputbox "Please enter the domain join user" 8 78 --title "Domain Join User" 3>&1 1>&2 2>&3)
DOMAIN_JOIN_PASSWORD=$(whiptail --passwordbox "Please enter the password for the domain join user" 8 78 --title "Domain Join Password" 3>&1 1>&2 2>&3)
REALM="${DOMAIN^^}"  # Convert domain to uppercase for the realm
AD_ACCESS_FILTER=$(whiptail --inputbox "Please enter the AD access filter\nExample: (memberOf=CN=Domain Admins,OU=Admin,OU=UserGroups,DC=domain,DC=local)" 12 78 "(memberOf=CN=Domain Admins,OU=Admin,OU=UserGroups,DC=domain,DC=local)" --title "AD Access Filter" 3>&1 1>&2 2>&3)

# Update package lists and install necessary packages
apt update
apt install -y realmd sssd adcli krb5-user packagekit samba-common-bin oddjob oddjob-mkhomedir sudo
export PATH=$PATH:/usr/sbin

# Check if 'realm' command is available
if ! command -v realm &> /dev/null; then
  echo "'realm' command not found. Make sure the 'realmd' package is installed." >&2
  exit 1
fi

# Join the system to the domain
echo "Joining the system to the domain..."
echo "$DOMAIN_JOIN_PASSWORD" | realm join --user=$DOMAIN_JOIN_USER $DOMAIN

if [ $? -ne 0 ]; then
  echo "Failed to join the domain" >&2
  exit 1
fi

# Add domain group to sudoers
echo "Adding the group $DOMAIN_ADMIN_GROUP to sudoers..."
echo "%$DOMAIN_ADMIN_GROUP ALL=(ALL) ALL" | sudo EDITOR='tee -a' visudo

# Restart SSH service
echo "Restarting the SSH service..."
systemctl restart sshd

# Adjust SSSD configuration
echo "Adjusting SSSD configuration..."
cat << EOF > /etc/sssd/sssd.conf
[sssd]
services = nss, pam
config_file_version = 2
domains = $REALM

[domain/$REALM]
ad_domain = $DOMAIN
krb5_realm = $REALM
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
fallback_homedir = /home/%u@%d
default_shell = /bin/bash
access_provider = ad
ad_access_filter = $AD_ACCESS_FILTER
EOF

# Set permissions for sssd.conf
chmod 600 /etc/sssd/sssd.conf

# Restart SSSD
echo "Restarting the SSSD service..."
systemctl restart sssd

# Clear console
clear

# Display success message using Whiptail
whiptail --title "Installation Complete" --msgbox "The installation and configuration were successfully completed." 8 78

echo "The server has been successfully joined to the domain and the configuration is complete."
