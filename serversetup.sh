#!/bin/bash
#  _____                          
# / ____|                         
#| (___   ___ _ ____   _____ _ __ 
# \___ \ / _ \ '__\ \ / / _ \ '__|
# ____) |  __/ |   \ V /  __/ |   
#|_____/ \___|_|    \_/ \___|_|   
# Serversetup by Raphael Jäger 04.03.2025                                 
                                 
# Pakete installieren
apt update && apt install -y neofetch figlet sudo htop curl

# /etc/profile bearbeiten, aber nur, wenn die Einträge noch nicht vorhanden sind
PROFILE_CONTENT="\nclear\nfiglet -f big \"\$(hostname)\"\necho \"==============================\"\necho \"Support: shquick@jaeger-raphael.de\"\necho \"==============================\"\nneofetch\n"

if ! grep -q "Support: shquick@jaeger-raphael.de" /etc/profile; then
    echo -e "# Die folgenden Einträge wurden von diesem Skript hinzugefügt. Bitte nicht erneut einfügen.\n$PROFILE_CONTENT" >> /etc/profile
fi

# /etc/bash.bashrc bearbeiten
cat > /etc/bash.bashrc << 'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Using color prompt
if [[ ${EUID} == 0 ]] ; then
    PS1='\[\033[48;2;221;75;57;38;2;255;255;255m\] \$ \[\033[48;2;0;135;175;38;2;221;75;57m\]\[\033[48;2;0;135;175;38;2;255;255;255m\] \h \[\033[48;2;83;85;85;38;2;0;135;175m\]\[\033[48;2;83;85;85;38;2;255;255;255m\] \w \[\033[49;38;2;83;85;85m\]\[\033[00m\] '
else
    PS1='\[\033[48;2;105;121;16;38;2;255;255;255m\] \$ \[\033[48;2;0;135;175;38;2;105;121;16m\]\[\033[48;2;0;135;175;38;2;255;255;255m\] \u@\h \[\033[48;2;83;85;85;38;2;0;135;175m\]\[\033[48;2;83;85;85;38;2;255;255;255m\] \w \[\033[49;38;2;83;85;85m\]\[\033[00m\] '
fi

# some better definitions
alias cp="cp -i"
alias df='df -h'
alias free='free -m'
alias more=less

ex () {
  if [ -f "$1" ] ; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"   ;;
      *.tar.gz)    tar xzf "$1"   ;;
      *.bz2)       bunzip2 "$1"   ;;
      *.rar)       unrar x "$1"   ;;
      *.gz)        gunzip "$1"    ;;
      *.tar)       tar xf "$1"    ;;
      *.tbz2)      tar xjf "$1"   ;;
      *.tgz)       tar xzf "$1"   ;;
      *.zip)       unzip "$1"     ;;
      *.Z)         uncompress "$1";;
      *.7z)        7z x "$1"      ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

if [ -x /opt/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

if [ -f /opt/etc/bash_completion ] && ! shopt -oq posix; then
    . /opt/etc/bash_completion
fi
EOF

# /root/.bashrc ebenfalls anpassen
cp /etc/bash.bashrc /root/.bashrc

# Skript beenden
echo "Setup abgeschlossen. Bitte einmal aus- und wieder einloggen, um die Änderungen zu sehen."
