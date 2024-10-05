#!/bin/bash
# _      _                            _____       _       _       
#| |    (_)                     /\   |  __ \     | |     (_)      
#| |     _ _ __  _   ___  __   /  \  | |  | |    | | ___  _ _ __  
#| |    | | '_ \| | | \ \/ /  / /\ \ | |  | |_   | |/ _ \| | '_ \ 
#| |____| | | | | |_| |>  <  / ____ \| |__| | |__| | (_) | | | | |
#|______|_|_| |_|\__,_/_/\_\/_/    \_\_____/ \____/ \___/|_|_| |_|
                                                                 
# Prüfen, ob das Skript als root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  echo "Dieses Skript muss als root ausgeführt werden." >&2
  exit 1
fi

# Whiptail für Eingaben
DOMAIN=$(whiptail --inputbox "Bitte die Domäne eingeben" 8 78 --title "Domäne" 3>&1 1>&2 2>&3)
DOMAIN_ADMIN_GROUP=$(whiptail --inputbox "Bitte die Admin-Gruppe der Domäne eingeben" 8 78 --title "Domänen-Admin-Gruppe" 3>&1 1>&2 2>&3)
DOMAIN_JOIN_USER=$(whiptail --inputbox "Bitte den Benutzer für den Domain-Beitritt eingeben" 8 78 --title "Domain-Beitrittsbenutzer" 3>&1 1>&2 2>&3)
DOMAIN_JOIN_PASSWORD=$(whiptail --passwordbox "Bitte das Passwort für den Domain-Beitrittsbenutzer eingeben" 8 78 --title "Domain-Beitrittspasswort" 3>&1 1>&2 2>&3)
REALM="${DOMAIN^^}"  # Konvertiere die Domäne in Großbuchstaben für den Realm
AD_ACCESS_FILTER=$(whiptail --inputbox "Bitte den AD Access Filter eingeben\nBeispiel: (memberOf=CN=Domänen-Administratoren,OU=Admin,OU=UserGroups,DC=domain,DC=local)" 12 78 "(memberOf=CN=Domänen-Administratoren,OU=Admin,OU=UserGroups,DC=domain,DC=local)" --title "AD Access Filter" 3>&1 1>&2 2>&3)

# Paketlisten aktualisieren und notwendige Pakete installieren
apt update
apt install -y realmd sssd adcli krb5-user packagekit samba-common-bin oddjob oddjob-mkhomedir sudo
export PATH=$PATH:/usr/sbin

# Überprüfe, ob der Befehl 'realm' verfügbar ist
if ! command -v realm &> /dev/null; then
  echo "'realm' Kommando nicht gefunden. Stelle sicher, dass das Paket 'realmd' installiert ist." >&2
  exit 1
fi

# System in die Domäne aufnehmen
echo "System wird in die Domäne aufgenommen..."
echo "$DOMAIN_JOIN_PASSWORD" | realm join --user=$DOMAIN_JOIN_USER $DOMAIN

if [ $? -ne 0 ]; then
  echo "Fehler beim Beitritt zur Domäne" >&2
  exit 1
fi

# Hinzufügen der Domänengruppe zu den Sudoers
echo "Hinzufügen der Gruppe $DOMAIN_ADMIN_GROUP zu den Sudoers..."
echo "%$DOMAIN_ADMIN_GROUP ALL=(ALL) ALL" | sudo EDITOR='tee -a' visudo

# SSH-Dienst neu starten
echo "Neustart des SSH-Dienstes..."
systemctl restart sshd

# Konfiguration von SSSD anpassen
echo "Anpassen der SSSD-Konfiguration..."
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

# Berechtigungen für sssd.conf setzen
chmod 600 /etc/sssd/sssd.conf

# Neustart von SSSD
echo "Neustart des SSSD-Dienstes..."
systemctl restart sssd

# Konsole leeren
clear

# Anzeige eines Whiptail-Fensters zur Erfolgsmeldung
whiptail --title "Installation abgeschlossen" --msgbox "Die Installation und Konfiguration wurden erfolgreich abgeschlossen." 8 78

echo "Der Server wurde erfolgreich in die Domäne eingebunden und die Konfiguration abgeschlossen."
