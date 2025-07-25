#!/bin/sh
#__          ___           _____                     _ 
#\ \        / (_)         / ____|                   | |
# \ \  /\  / / _ _ __ ___| |  __ _   _  __ _ _ __ __| |
#  \ \/  \/ / | | '__/ _ \ | |_ | | | |/ _` | '__/ _` |
#   \  /\  /  | | | |  __/ |__| | |_| | (_| | | | (_| |
#    \/  \/   |_|_|  \___|\_____|\__,_|\__,_|_|  \__,_|
#Raphael Jäger                                                      

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

#Install whiptail
apt install whiptail -y

# Variables
eth="$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1 }')"

# Asking Questions with Whiptail
wg_subnet=$(whiptail --inputbox "Please enter the Wireguard Subnet (eg. 172.0.0.1/24):" 8 78 --title "Wireguard Subnet" 3>&1 1>&2 2>&3)
wg_interface_id=$(whiptail --inputbox "Please enter the Interface ID Name (eg. wg0):" 8 78 --title "Interface ID" 3>&1 1>&2 2>&3)
wg_port=$(whiptail --inputbox "Please enter the Wireguard UDP-Port (eg. 51820):" 8 78 --title "Wireguard Port" 3>&1 1>&2 2>&3)
wg_dashboard_port=$(whiptail --inputbox "Please enter the WG-Dashboard Web-Port (eg. 81):" 8 78 --title "WG-Dashboard Web-Port" 3>&1 1>&2 2>&3)

# Installing Wireguard
{
    echo 10
    echo "Installing Wireguard..." >/dev/null 2>&1
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf >/dev/null 2>&1
    
    echo 20
    echo "Installing sudo..." >/dev/null 2>&1
    apt install sudo -y >/dev/null 2>&1
    
    echo 30
    echo "Installing iptables..." >/dev/null 2>&1
    apt install iptables -y >/dev/null 2>&1
    
    echo 40
    echo "Installing resolvconf..." >/dev/null 2>&1
    apt install resolvconf -y >/dev/null 2>&1
    sudo rm -r /etc/resolv.conf >/dev/null 2>&1
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    
    echo 50
    echo "Installing Wireguard..." >/dev/null 2>&1
    apt install wireguard -y >/dev/null 2>&1
    
    cd /etc/wireguard
    umask 077; wg genkey | tee privatekey | wg pubkey > publickey
    chmod 600 /etc/wireguard/privatekey >/dev/null 2>&1
    privkey="$(cat /etc/wireguard/privatekey)"
    pubkey="$(cat /etc/wireguard/publickey)"
    
    touch $wg_interface_id.conf
    echo "[Interface]" >> $wg_interface_id.conf
    echo "PrivateKey = $privkey" >> $wg_interface_id.conf
    echo "Address = $wg_subnet" >> $wg_interface_id.conf
    echo "SaveConfig = true" >> $wg_interface_id.conf
    echo "PostUp = iptables -A FORWARD -i $wg_interface_id -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE" >> $wg_interface_id.conf
    echo "PostDown = iptables -D FORWARD -i $wg_interface_id -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE" >> $wg_interface_id.conf
    echo "ListenPort = $wg_port" >> $wg_interface_id.conf
    
    wg-quick up $wg_interface_id >/dev/null 2>&1
    systemctl enable wg-quick@$wg_interface_id >/dev/null 2>&1
    
    echo 70
    echo "Installing WG-Dashboard..." >/dev/null 2>&1
    
    apt install git -y >/dev/null 2>&1
    apt install python -y >/dev/null 2>&1
    apt install pip3 -y >/dev/null 2>&1
    apt install pip -y >/dev/null 2>&1
    pip install ifcfg --break-system-packages >/dev/null 2>&1
    pip install flask --break-system-packages >/dev/null 2>&1
    pip install flask_qrcode --break-system-packages >/dev/null 2>&1
    pip install icmplib --break-system-packages >/dev/null 2>&1
    
    cd /root/
    git clone -b v3.0.6 https://github.com/donaldzou/WGDashboard.git wgdashboard >/dev/null 2>&1
    cd wgdashboard/src
    sudo chmod u+x wgd.sh >/dev/null 2>&1
    sudo ./wgd.sh install >/dev/null 2>&1
    sudo chmod -R 755 /etc/wireguard >/dev/null 2>&1
    
    touch /etc/systemd/system/wg-dashboard.service
    cd /etc/systemd/system
    echo "[Unit]" >> wg-dashboard.service
    echo "After=network.service" >> wg-dashboard.service
    echo "" >> wg-dashboard.service
    echo "[Service]" >> wg-dashboard.service
    echo "WorkingDirectory=/root/wgdashboard/src" >> wg-dashboard.service
    echo "ExecStart=/usr/bin/python3 /root/wgdashboard/src/dashboard.py" >> wg-dashboard.service
    echo "Restart=always" >> wg-dashboard.service
    echo "" >> wg-dashboard.service
    echo "[Install]" >> wg-dashboard.service
    echo "WantedBy=default.target" >> wg-dashboard.service
    
    sudo chmod 664 /etc/systemd/system/wg-dashboard.service >/dev/null 2>&1
    sudo systemctl daemon-reload >/dev/null 2>&1
    sudo systemctl enable wg-dashboard.service >/dev/null 2>&1
    sudo systemctl start wg-dashboard.service >/dev/null 2>&1
    
    cd /root/wgdashboard/src
    sleep 1s
    sudo systemctl stop wg-dashboard.service >/dev/null 2>&1
    sudo sed -i "8s/10086/$wg_dashboard_port/" ./wg-dashboard.ini >/dev/null 2>&1
    sudo systemctl start wg-dashboard.service >/dev/null 2>&1
    
    echo 100
} | whiptail --gauge "Installing Wireguard and WG-Dashboard..." 6 60 0

whiptail --msgbox "Installation Complete" 8 78 --title "Installation Complete"
