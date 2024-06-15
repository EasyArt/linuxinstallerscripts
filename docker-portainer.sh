#!/bin/sh
# _____             _             
#|  __ \           | |            
#| |  | | ___   ___| | _____ _ __ 
#| |  | |/ _ \ / __| |/ / _ \ '__|
#| |__| | (_) | (__|   <  __/ |   
#|_____/ \___/ \___|_|\_\___|_|   
#Raphael Jäger

apt install sudo
apt install curl -y

clear

sudo apt-get update
sudo apt-get install \
   ca-certificates \
   curl \
   gnupg \
   lsb-release -y

clear

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

clear

echo \
 "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
 $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
 sudo apt-get update
 sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y

clear

 docker volume create portainer_data
 docker run -d -p 9443:9443 --name portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest

clear
echo "Docker und Portainer wurden installiert."
echo "Du kannst die Portainer Oberfläche über den Port 9443 erreichen."