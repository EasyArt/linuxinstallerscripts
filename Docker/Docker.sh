#!/bin/bash
# _____             _                _        _                            
#|  __ \           | |              | |      | |                           
#| |__) |__ _ _ __ | |__   __ _  ___| |      | | __ _  ___  __ _  ___ _ __ 
#|  _  // _` | '_ \| '_ \ / _` |/ _ \ |  _   | |/ _` |/ _ \/ _` |/ _ \ '__|
#| | \ \ (_| | |_) | | | | (_| |  __/ | | |__| | (_| |  __/ (_| |  __/ |   
#|_|  \_\__,_| .__/|_| |_|\__,_|\___|_|  \____/ \__,_|\___|\__, |\___|_|   
#            | |                                            __/ |          
#            |_|                                           |___/           

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

#Install whiptail
apt install whiptail -y

# Variables to store generated passwords
mysql_root_password=""

# Functions for installing different options

install_docker() {
    echo "Installing Docker..."
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Debian and Ubuntu have similar setups
    if [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/lsb-release ]; then
        DISTRO="ubuntu"
    else
        echo "This script only supports Debian and Ubuntu."
        exit 1
    fi

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${DISTRO}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Creating 'productive' Docker network..."
    docker network create produktiv
	clear
}

install_portainer() {
    echo "Installing Portainer..."
    docker run -d --name portainer --network produktiv --restart always \
      -p 9443:9443 -h portainer \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest
	clear
}

install_nginx_rpm() {
    echo "Installing NGINX Proxy Manager..."
    docker volume create npm_data
    docker volume create npm_ssl

    docker run -d --name npm --network produktiv --restart always \
      -p 80:80 -p 443:443 -p 81:81 -h npm \
      -v npm_data:/data \
      -v npm_ssl:/etc/letsencrypt \
      jc21/nginx-proxy-manager:latest
	clear
}

install_zoraxy() {
    echo "Installing Zoraxy..."
    docker volume create zoraxy_config
    docker volume create zoraxy_zerotier

    docker run -d --name zoraxy --network produktiv --restart always \
      -p 80:80 -p 443:443 -p 8000:8000 \
      -v zoraxy_config:/opt/zoraxy/config \
      -v zoraxy_zerotier:/var/lib/zerotier-one \
      -v /etc/localtime:/etc/localtime:ro \
      -e FASTGEOIP=true \
      -e ZEROTIER=false \
      zoraxydocker/zoraxy:latest
	clear
}

install_mysql() {
    echo "Installing MySQL..."
    mysql_root_password=$(openssl rand -base64 12)

    docker run -d --name mysql --network produktiv --restart always \
      -e MYSQL_ROOT_PASSWORD="$mysql_root_password" \
      -p 3306:3306 -h mysql \
      mysql:latest
	clear
}

install_portaineragent() {
	docker run -d \
	  -p 9001:9001 \
	  --name portainer_agent \
	  --restart=always \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v /var/lib/docker/volumes:/var/lib/docker/volumes \
	  -v /:/host \
	  portainer/agent:2.27.9
	clear
}

install_watchtower() {
    echo "Installing Watchtower..."
    timezone=$(whiptail --inputbox "Enter your timezone (e.g. Europe/Berlin):" 8 39 --title "Watchtower Installation" 3>&1 1>&2 2>&3)
    hour=$(whiptail --inputbox "Enter the hour for Watchtower to run (0-23):" 8 39 --title "Watchtower Installation" 3>&1 1>&2 2>&3)
    cron_time="0 $hour * * *"

    docker run -d --name watchtower --network produktiv --restart always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e TZ="$timezone" \
      -e WATCHTOWER_SCHEDULE="$cron_time" \
      containrrr/watchtower
	clear
}

remove_docker_deb12() {
    echo "Removing Old Deb12 Repo..."
    FILE="/etc/apt/sources.list.d/docker.list"
    if [[ -f "$FILE" ]]; then
        sed -i '/bookworm/d' "$FILE"
    fi
}

# Function for GUI multi-selection
show_service_selection() {
    services=$(whiptail --checklist "Select the services to install:" 20 78 10 \
    "1" "Remove old Deb12 Repository" off \
    "2" "Install Portainer" off \
    "3" "Install Portainer Agent" off \
    "4" "Install NGINX Proxy Manager" off \
    "5" "Install Zoraxy" off \
    "6" "Install MySQL" off \
    "7" "Install Watchtower" off 3>&1 1>&2 2>&3)

    for service in $services; do
        case $service in
	    "\"1\"") remove_docker_deb12 ;;
            "\"2\"") install_portainer ;;
            "\"3\"") install_portaineragent ;;
            "\"4\"") install_nginx_rpm ;;
	    "\"5\"") install_zoraxy ;;
            "\"6\"") install_mysql ;;
            "\"7\"") install_watchtower ;;
        esac
    done

    # After all installations, display the credentials
    display_credentials
}

# Function to display collected passwords
display_credentials() {
    credentials=""

    if [[ -n "$mysql_root_password" ]]; then
        credentials+="MySQL Root Password: $mysql_root_password\n"
    fi

    if [[ -n "$credentials" ]]; then
        whiptail --msgbox "Installation complete!\n\n$credentials" 12 78 --title "Required Credentials"
    else
        whiptail --msgbox "Installation complete! No additional credentials required." 8 78 --title "Required Credentials"
    fi
}

# Check if Docker is installed and the productive network exists
if ! docker network inspect produktiv &>/dev/null; then
    if (whiptail --yesno "Docker and the productive network are not present. Would you like to install Docker?" 8 78); then
        install_docker
    fi
fi

# Show the service selection
show_service_selection
