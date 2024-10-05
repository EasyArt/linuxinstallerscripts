#!/bin/bash
# _____             _                _        _                            
#|  __ \           | |              | |      | |                           
#| |__) |__ _ _ __ | |__   __ _  ___| |      | | __ _  ___  __ _  ___ _ __ 
#|  _  // _` | '_ \| '_ \ / _` |/ _ \ |  _   | |/ _` |/ _ \/ _` |/ _ \ '__|
#| | \ \ (_| | |_) | | | | (_| |  __/ | | |__| | (_| |  __/ (_| |  __/ |   
#|_|  \_\__,_| .__/|_| |_|\__,_|\___|_|  \____/ \__,_|\___|\__, |\___|_|   
#            | |                                            __/ |          
#            |_|                                           |___/           
#	11.09.2024

# Variablen zur Speicherung der generierten Passwörter
mysql_root_password=""
vaultwarden_admin_token=""

# Funktionen zur Installation der verschiedenen Optionen

install_docker() {
    echo "Docker wird installiert..."
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Debian und Ubuntu haben ähnliche Setups
    if [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/lsb-release ]; then
        DISTRO="ubuntu"
    else
        echo "Dieses Skript unterstützt nur Debian und Ubuntu."
        exit 1
    fi

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${DISTRO}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Erstelle 'produktives' Docker-Netzwerk..."
    docker network create produktiv
	clear
}



install_portainer() {
    echo "Portainer wird installiert..."
    docker run -d --name portainer --network produktiv --restart always \
      -p 9443:9443 -h portainer \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest
	clear
}

install_nginx_rpm() {
    echo "NGINX Proxy Manager wird installiert..."
    docker volume create npm_data
    docker volume create npm_ssl

    docker run -d --name npm --network produktiv --restart always \
      -p 80:80 -p 443:443 -p 81:81 -h npm \
      -v npm_data:/data \
      -v npm_ssl:/etc/letsencrypt \
      jc21/nginx-proxy-manager:latest
	clear
}

install_mysql() {
    echo "MySQL wird installiert..."
    mysql_root_password=$(openssl rand -base64 12)

    docker run -d --name mysql --network produktiv --restart always \
      -e MYSQL_ROOT_PASSWORD="$mysql_root_password" \
      -p 3306:3306 -h mysql \
      mysql:latest
	clear
}

install_guacamole() {
    echo "Apache Guacamole wird installiert..."
    docker volume create guacamole

    docker run -d --name guacamole --network produktiv --restart always \
      -v guacamole:/config -h guacamole \
      oznu/guacamole:latest
	clear
}

install_vaultwarden() {
	docker volume create vaultwarden
	vaultwarden_admin_token=$(openssl rand -base64 30 | tr -d /=+ | cut -c -30)

	docker run -d \
	  --name vaultwarden \
	  --network produktiv \
	  --hostname vaultwarden \
	  -v vaultwarden:/data \
	  -e ADMIN_TOKEN=$vaultwarden_admin_token \
	  vaultwarden/server:latest
	clear
}

install_watchtower() {
    echo "Watchtower wird installiert..."
    timezone=$(whiptail --inputbox "Geben Sie Ihre Zeitzone an (z.B. Europe/Berlin):" 8 39 --title "Watchtower Installation" 3>&1 1>&2 2>&3)
    hour=$(whiptail --inputbox "Geben Sie die Stunde an, zu der Watchtower laufen soll (0-23):" 8 39 --title "Watchtower Installation" 3>&1 1>&2 2>&3)
    cron_time="0 $hour * * *"

    docker run -d --name watchtower --network produktiv --restart always \
      -e TZ="$timezone" \
      -e WATCHTOWER_SCHEDULE="$cron_time" \
      containrrr/watchtower
	clear
}

# Funktion zur GUI für Mehrfachauswahl
show_service_selection() {
    services=$(whiptail --checklist "Wählen Sie die zu installierenden Dienste:" 20 78 10 \
    "1" "Portainer installieren" off \
    "2" "NGINX Proxy Manager installieren" off \
    "3" "MySQL installieren" off \
    "4" "Apache Guacamole installieren" off \
    "5" "Vaultwarden installieren" off \
    "6" "Watchtower installieren" off 3>&1 1>&2 2>&3)

    for service in $services; do
        case $service in
            "\"1\"") install_portainer ;;
            "\"2\"") install_nginx_rpm ;;
            "\"3\"") install_mysql ;;
            "\"4\"") install_guacamole ;;
            "\"5\"") install_vaultwarden ;;
            "\"6\"") install_watchtower ;;
        esac
    done

    # Nach allen Installationen die Passwörter anzeigen
    display_credentials
}

# Funktion zur Anzeige der gesammelten Passwörter
display_credentials() {
    credentials=""

    if [[ -n "$mysql_root_password" ]]; then
        credentials+="MySQL Root Passwort: $mysql_root_password\n"
    fi

    if [[ -n "$vaultwarden_admin_token" ]]; then
        credentials+="Vaultwarden Admin Token: $vaultwarden_admin_token\n"
    fi

    if [[ -n "$credentials" ]]; then
        whiptail --msgbox "Installation abgeschlossen!\n\n$credentials" 12 78 --title "Erforderliche Anmeldeinformationen"
    else
        whiptail --msgbox "Installation abgeschlossen! Keine zusätzlichen Anmeldeinformationen erforderlich." 8 78 --title "Erforderliche Anmeldeinformationen"
    fi
}

# Prüfen, ob Docker installiert ist und produktives Netzwerk existiert
if ! docker network inspect produktiv &>/dev/null; then
    if (whiptail --yesno "Docker und das produktive Netzwerk sind nicht vorhanden. Möchten Sie Docker installieren?" 8 78); then
        install_docker
    fi
fi

# Liste der Dienste anzeigen
show_service_selection
