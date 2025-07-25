#!/bin/bash
# ______                              _   
#|  ____|                  /\        | |  
#| |__   __ _ ___ _   _   /  \   _ __| |_ 
#|  __| / _` / __| | | | / /\ \ | '__| __|
#| |___| (_| \__ \ |_| |/ ____ \| |  | |_ 
#|______\__,_|___/\__, /_/    \_\_|   \__|
#                  __/ |                  
#                 |___/                   

# Funktionen definieren
section1() {
	echo "Switching pulseaudio to pipewire"
	sudo add-apt-repository ppa:pipewire-debian/pipewire-upstream -y
	sudo apt update && sudo apt install pipewire pipewire-audio-client-libraries -y
	sudo apt install gstreamer1.0-pipewire libpipewire-0.3-{0,dev,modules} libspa-0.2-{bluetooth,dev,jack,modules} pipewire{,-{audio-client-libraries,pulse,media-session,bin,locales,tests}} -y
	systemctl --user daemon-reload
	systemctl --user --now disable pulseaudio.service pulseaudio.socket
	systemctl --user --now enable pipewire pipewire-pulse
}

section2() {
	echo "Switching wayland to xorg"
	sudo sed -i '7s/#//' /etc/gdm3/custom.conf
	sudo systemctl restart gdm3
}

section3() {
	echo "Installing XRDP and configuring environment variables"
	sudo apt install xrdp -y

	echo "Adding environment variables to /etc/environment"
	echo 'export DESKTOP_SESSION=zorin' | sudo tee -a /etc/environment
	echo 'export GNOME_SHELL_SESSION_MODE=zorin' | sudo tee -a /etc/environment
	echo 'export XDG_CURRENT_DESKTOP=ubuntu:GNOME' | sudo tee -a /etc/environment

    # Die Variablen ganz oben in die Datei /etc/X11/Xsession einfügen
    sudo sed -i '1i DESKTOP_SESSION=zorin' /etc/X11/Xsession
    sudo sed -i '2i GNOME_SHELL_SESSION_MODE=zorin' /etc/X11/Xsession
    sudo sed -i '3i XDG_CURRENT_DESKTOP=zorin:GNOME' /etc/X11/Xsession
    echo "Umgebungsvariablen wurden hinzugefügt."

	echo "Adding color manager policies"
	sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
	echo "[Allow Colord all Users]" | sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
	echo "Identity=unix-user:*" | sudo tee -a /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
	echo "Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile" | sudo tee -a /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
	echo "ResultAny=no" | sudo tee -a /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
	echo "ResultInactive=no" | sudo tee -a /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
	echo "ResultActive=no" | sudo tee -a /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla

	echo "Disabling and stopping colord service"
	sudo systemctl disable colord
	sudo systemctl stop colord
	sed -i 's/access_provider = ad/access_provider = permit/' "/etc/sssd/sssd.conf"
	systemctl restart sssd
	systemctl restart xrdp
}

section4() {
	echo "Active Directory-Integration in Zorin OS"
	# Pakete installieren
	echo "Installiere benötigte Pakete..."
	apt update
	apt install -y realmd sssd adcli krb5-user samba-common-bin packagekit

	# Active Directory-Daten abfragen über whiptail
	DOMAIN=$(whiptail --inputbox "Bitte gib die Domäne ein (z.B. example.com):" 8 78 --title "Domäne eingeben" 3>&1 1>&2 2>&3)
	ADMIN_USER=$(whiptail --inputbox "Bitte gib den Admin-Benutzernamen ein:" 8 78 --title "Admin-Benutzer eingeben" 3>&1 1>&2 2>&3)
	ADMIN_PASS=$(whiptail --passwordbox "Bitte gib das Admin-Passwort ein:" 8 78 --title "Admin-Passwort eingeben" 3>&1 1>&2 2>&3)

	# Kerberos-Konfiguration automatisch erstellen
	echo "Erstelle Kerberos-Konfiguration..."
	cat <<EOF > /etc/krb5.conf
[libdefaults]
    default_realm = ${DOMAIN^^}
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    ${DOMAIN^^} = {
        kdc = ${DOMAIN,,}
        admin_server = ${DOMAIN,,}
    }

[domain_realm]
    .${DOMAIN,,} = ${DOMAIN^^}
    ${DOMAIN,,} = ${DOMAIN^^}
EOF

	# In die Domäne aufnehmen ohne interaktive Abfragen
	echo "Nehme das System in die Domäne auf..."
	echo $ADMIN_PASS | realm join --user=$ADMIN_USER $DOMAIN --install=/

	# Überprüfen, ob der Beitritt erfolgreich war
	if [ $? -eq 0 ]; then
	    echo "System erfolgreich in die Domäne aufgenommen."
	else
	    echo "Fehler beim Beitritt zur Domäne."
	    exit 1
	fi

	# SSSD konfigurieren
	echo "Konfiguriere SSSD..."
	cat <<EOF > /etc/sssd/sssd.conf
[sssd]
services = nss, pam
config_file_version = 2
domains = $DOMAIN

[domain/$DOMAIN]
ad_domain = $DOMAIN
krb5_realm = ${DOMAIN^^}
realmd_tags = manages-system joined-with-samba
cache_credentials = True
id_provider = ad
fallback_homedir = /home/%u
default_shell = /bin/bash
ldap_id_mapping = True
use_fully_qualified_names = False
access_provider = ad
EOF

	chmod 600 /etc/sssd/sssd.conf

	# Start- und Aktivierungsdienste
	echo "Aktiviere und starte SSSD..."
	systemctl enable sssd
	systemctl start sssd

	# PAM konfigurieren, um die AD-Anmeldung zu ermöglichen
	echo "Konfiguriere PAM für AD-Anmeldungen..."
	pam-auth-update --enable mkhomedir

	# Sudo-Rechte für Domain Admins
	echo "Erteile Sudo-Rechte für die Active Directory 'Domänen-Admins'..."
	echo "%domänen-admins ALL=(ALL) ALL" | sudo EDITOR='tee -a' visudo

	# Neustarten, damit alle Änderungen wirksam werden
	RESTART=$(whiptail --yesno "Das System muss neu gestartet werden, um die Änderungen zu übernehmen. Möchtest du jetzt neu starten?" 8 78 --title "Neustart erforderlich" 3>&1 1>&2 2>&3)

	if [ $? -eq 0 ]; then
	    reboot
	else
	    echo "Bitte denke daran, das System später neu zu starten."
	fi
}

# Menü mit Whiptail implementieren
show_menu() {
    CHOICES=$(whiptail --title "Fix options" --checklist \
    "What do you want to fix?" 20 78 4 \
    "1" "Audio reset at reboot" OFF \
    "2" "Screen share (in Discord) not possible" OFF \
    "3" "Install XRDP and configure environment" OFF \
    "4" "Active Directory-Integration" OFF \
    3>&1 1>&2 2>&3)

    if [ -z "$CHOICES" ]; then
        echo "No option selected, exiting."
        exit 1
    fi

    # Führt die ausgewählten Aktionen durch, aber verschiebt Abschnitt 2 ans Ende, falls er ausgewählt wurde.
    for CHOICE in $CHOICES; do
        case $CHOICE in
            "\"1\"")
                section1
                ;;
            "\"3\"")
                section3
                ;;
            "\"4\"")
                section4
                ;;
        esac
    done

    # Führt Abschnitt 2 immer zuletzt aus, falls ausgewählt
    if [[ $CHOICES == *"2"* ]]; then
        section2
    fi
}

show_menu
