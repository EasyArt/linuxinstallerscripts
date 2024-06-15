#!/bin/sh
#__          ___           _____                     _ 
#\ \        / (_)         / ____|                   | |
# \ \  /\  / / _ _ __ ___| |  __ _   _  __ _ _ __ __| |
#  \ \/  \/ / | | '__/ _ \ | |_ | | | |/ _` | '__/ _` |
#   \  /\  /  | | | |  __/ |__| | |_| | (_| | | | (_| |
#    \/  \/   |_|_|  \___|\_____|\__,_|\__,_|_|  \__,_|
#Raphael Jäger                                                      
                                                      
#Variables
eth="$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}')"
#wg_subnet="172.0.0.1/24"
#wg_interface_id="wg0"
#wg_port="51820"
#wg_dashboard_port="81"

#Asking Questions
clear
echo "Please enter the Wireguard Subnet (eg. 172.0.0.1/24):"
read wg_subnet
clear

echo "Please enter the Interface ID Name (eg. wg0):"
read wg_interface_id
clear

echo "Please enter the the Wireguard UDP-Port (eg. 51820):"
read wg_port
clear

echo "Please enter the WG-Dashboard Web-Port (eg. 81):"
read wg_dashboard_port
clear


#Installing Wireguard
echo "Installing Wireguard..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
clear
echo "Installing Sudo..."
apt install sudo
clear
echo "Installing iptables..."
apt install iptables -y
clear
echo "Installing resolvconf..."
apt install resolvconf
sudo rm -r /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf
apt install wireguard -y
cd /etc/wireguard
umask 077; wg genkey | tee privatekey | wg pubkey > publickey
chmod 600 /etc/wireguard/privatekey
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
wg-quick up $wg_interface_id
systemctl enable wg-quick@$wg_interface_id

#Installing WG-Dashboard
clear
echo "Installing WG-Dashboard..."
echo "Installing git..."
apt install git -y
echo "Installing python..."
apt install python -y
apt install pip3 -y
apt install pip -y
pip install ifcfg --break-system-packages
pip install flask --break-system-packages
pip install flask_qrcode --break-system-packages
pip install icmplib --break-system-packages
cd /root/
git clone -b v3.0.6 https://github.com/donaldzou/WGDashboard.git wgdashboard
cd wgdashboard/src
sudo chmod u+x wgd.sh
sudo ./wgd.sh install
sudo chmod -R 755 /etc/wireguard
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
sudo chmod 664 /etc/systemd/system/wg-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable wg-dashboard.service
sudo systemctl start wg-dashboard.service
cd /root/wgdashboard/src
sleep 1s
sudo systemctl stop wg-dashboard.service
sudo sed -i "8s/10086/$wg_dashboard_port/" ./wg-dashboard.ini
sudo systemctl start wg-dashboard.service
clear
echo "Installation abgeschlossen."