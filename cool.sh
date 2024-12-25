#!/bin/bash
## Do not modify this file. You will lose the ability to install and auto-update!

set -e # Exit immediately if a command exits with a non-zero status
set -o pipefail # Cause a pipeline to return the status of the last command that exited with a non-zero status
CDN="https://cdn.coollabs.io/coolify"
DATE=$(date +"%Y%m%d-%H%M%S")

VERSION="1.6"
DOCKER_VERSION="27.0"
CURRENT_USER=$USER

# Add root user configuration
read -p "Enter email for root user: " ROOT_EMAIL
read -s -p "Enter password for root user: " ROOT_PASSWORD
echo "" # new line after password input

if [ $EUID != 0 ]; then
    echo "Please run this script as root or with sudo"
    exit
fi

echo -e "Welcome to Coolify Installer!"
echo -e "This script will install everything for you. Sit back and relax."
echo -e "Source code: https://github.com/coollabsio/coolify/blob/main/scripts/install.sh\n"

TOTAL_SPACE=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_TOTAL_SPACE=30
REQUIRED_AVAILABLE_SPACE=20
WARNING_SPACE=false

if [ "$TOTAL_SPACE" -lt "$REQUIRED_TOTAL_SPACE" ]; then
    WARNING_SPACE=true
    cat << EOF
WARNING: Insufficient total disk space!

Total disk space:     ${TOTAL_SPACE}GB
Required disk space:  ${REQUIRED_TOTAL_SPACE}GB

==================
EOF
fi

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_AVAILABLE_SPACE" ]; then
    cat << EOF
WARNING: Insufficient available disk space!

Available disk space:   ${AVAILABLE_SPACE}GB
Required available space: ${REQUIRED_AVAILABLE_SPACE}GB

==================
EOF
WARNING_SPACE=true
fi

if [ "$WARNING_SPACE" = true ]; then
    echo "Sleeping for 5 seconds."
    sleep 5
fi

mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance,sentinel}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

INSTALLATION_LOG_WITH_DATE="/data/coolify/source/installation-${DATE}.log"

exec > >(tee -a $INSTALLATION_LOG_WITH_DATE) 2>&1

getAJoke() {
    JOKES=$(curl -s --max-time 2 "https://v2.jokeapi.dev/joke/Programming?blacklistFlags=nsfw,religious,political,racist,sexist,explicit&format=txt&type=single" || true)
    if [ "$JOKES" != "" ]; then
        echo -e " - Until then, here's a joke for you:\n"
        echo -e "$JOKES\n"
    fi
}
OS_TYPE=$(grep -w "ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
ENV_FILE="/data/coolify/source/.env"

# Check if the OS is manjaro, if so, change it to arch
if [ "$OS_TYPE" = "manjaro" ] || [ "$OS_TYPE" = "manjaro-arm" ]; then
    OS_TYPE="arch"
fi

# Check if the OS is Endeavour OS, if so, change it to arch
if [ "$OS_TYPE" = "endeavouros" ]; then
    OS_TYPE="arch"
fi

# Check if the OS is Asahi Linux, if so, change it to fedora
if [ "$OS_TYPE" = "fedora-asahi-remix" ]; then
    OS_TYPE="fedora"
fi

# Check if the OS is popOS, if so, change it to ubuntu
if [ "$OS_TYPE" = "pop" ]; then
    OS_TYPE="ubuntu"
fi

# Check if the OS is linuxmint, if so, change it to ubuntu
if [ "$OS_TYPE" = "linuxmint" ]; then
    OS_TYPE="ubuntu"
fi

#Check if the OS is zorin, if so, change it to ubuntu
if [ "$OS_TYPE" = "zorin" ]; then
    OS_TYPE="ubuntu"
fi

if [ "$OS_TYPE" = "arch" ] || [ "$OS_TYPE" = "archarm" ]; then
    OS_VERSION="rolling"
else
    OS_VERSION=$(grep -w "VERSION_ID" /etc/os-release | cut -d "=" -f 2 | tr -d '"')
fi

# Install xargs on Amazon Linux 2023 - lol
if [ "$OS_TYPE" = 'amzn' ]; then
    dnf install -y findutils >/dev/null
fi

LATEST_VERSION=$(curl --silent $CDN/versions.json | grep -i version | xargs | awk '{print $2}' | tr -d ',')
LATEST_HELPER_VERSION=$(curl --silent $CDN/versions.json | grep -i version | xargs | awk '{print $6}' | tr -d ',')
LATEST_REALTIME_VERSION=$(curl --silent $CDN/versions.json | grep -i version | xargs | awk '{print $8}' | tr -d ',')

if [ -z "$LATEST_HELPER_VERSION" ]; then
    LATEST_HELPER_VERSION=latest
fi

if [ -z "$LATEST_REALTIME_VERSION" ]; then
    LATEST_REALTIME_VERSION=latest
fi

case "$OS_TYPE" in
arch | ubuntu | debian | raspbian | centos | fedora | rhel | ol | rocky | sles | opensuse-leap | opensuse-tumbleweed | almalinux | amzn | alpine) ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, Alpine Linux, or SLES based operating systems for now."
    exit
    ;;
esac

# Overwrite LATEST_VERSION if user pass a version number
if [ "$1" != "" ]; then
    LATEST_VERSION=$1
    LATEST_VERSION="${LATEST_VERSION,,}"
    LATEST_VERSION="${LATEST_VERSION#v}"
fi

echo -e "---------------------------------------------"
echo "| Operating System  | $OS_TYPE $OS_VERSION"
echo "| Docker            | $DOCKER_VERSION"
echo "| Coolify           | $LATEST_VERSION"
echo "| Helper            | $LATEST_HELPER_VERSION"
echo "| Realtime          | $LATEST_REALTIME_VERSION"
echo -e "---------------------------------------------\n"
echo -e "1. Installing required packages (curl, wget, git, jq, openssl). "

case "$OS_TYPE" in
arch)
    pacman -Sy --noconfirm --needed curl wget git jq openssl >/dev/null || true
    ;;
alpine)
    sed -i '/^#.*\/community/s/^#//' /etc/apk/repositories
    apk update >/dev/null
    apk add curl wget git jq openssl >/dev/null
    ;;
ubuntu | debian | raspbian)
    apt-get update -y >/dev/null
    apt-get install -y curl wget git jq openssl >/dev/null
    ;;
centos | fedora | rhel | ol | rocky | almalinux | amzn)
    if [ "$OS_TYPE" = "amzn" ]; then
        dnf install -y wget git jq openssl >/dev/null
    else
        if ! command -v dnf >/dev/null; then
            yum install -y dnf >/dev/null
        fi
        if ! command -v curl >/dev/null; then
            dnf install -y curl >/dev/null
        fi
        dnf install -y wget git jq openssl >/dev/null
    fi
    ;;
sles | opensuse-leap | opensuse-tumbleweed)
    zypper refresh >/dev/null
    zypper install -y curl wget git jq openssl >/dev/null
    ;;
*)
    echo "This script only supports Debian, Redhat, Arch Linux, or SLES based operating systems for now."
    exit
    ;;
esac

echo -e "2. Check OpenSSH server configuration. "

# Detect OpenSSH server
SSH_DETECTED=false
if [ -x "$(command -v systemctl)" ]; then
    if systemctl status sshd >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    elif systemctl status ssh >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    fi
elif [ -x "$(command -v service)" ]; then
    if service sshd status >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    elif service ssh status >/dev/null 2>&1; then
        echo " - OpenSSH server is installed."
        SSH_DETECTED=true
    fi
fi

if [ "$SSH_DETECTED" = "false" ]; then
    echo " - OpenSSH server not detected. Installing OpenSSH server."
    case "$OS_TYPE" in
    arch)
        pacman -Sy --noconfirm openssh >/dev/null
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    alpine)
        apk add openssh >/dev/null
        rc-update add sshd default >/dev/null 2>&1
        service sshd start >/dev/null 2>&1
        ;;
    ubuntu | debian | raspbian)
        apt-get update -y >/dev/null
        apt-get install -y openssh-server >/dev/null
        systemctl enable ssh >/dev/null 2>&1
        systemctl start ssh >/dev/null 2>&1
        ;;
    centos | fedora | rhel | ol | rocky | almalinux | amzn)
        if [ "$OS_TYPE" = "amzn" ]; then
            dnf install -y openssh-server >/dev/null
        else
            dnf install -y openssh-server >/dev/null
        fi
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    sles | opensuse-leap | opensuse-tumbleweed)
        zypper install -y openssh >/dev/null
        systemctl enable sshd >/dev/null 2>&1
        systemctl start sshd >/dev/null 2>&1
        ;;
    *)
        echo "###############################################################################"
        echo "WARNING: Could not detect and install OpenSSH server - this does not mean that it is not installed or not running, just that we could not detect it."
        echo -e "Please make sure it is installed and running, otherwise Coolify cannot connect to the host system. \n"
        echo "###############################################################################"
        exit 1
        ;;
    esac
    echo " - OpenSSH server installed successfully."
    SSH_DETECTED=true
fi

# Rest of the original script remains the same until the .env file creation

# Modified .env file creation section
if [ ! -f $ENV_FILE ]; then
    cp /data/coolify/source/.env.production $ENV_FILE-$DATE
    
    # Generate secure values
    sed -i "s|^APP_ID=.*|APP_ID=$(openssl rand -hex 16)|" "$ENV_FILE-$DATE"
    sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(openssl rand -base64 32)|" "$ENV_FILE-$DATE"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(openssl rand -base64 32)|" "$ENV_FILE-$DATE"
    sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -base64 32)|" "$ENV_FILE-$DATE"
    sed -i "s|^PUSHER_APP_ID=.*|PUSHER_APP_ID=$(openssl rand -hex 32)|" "$ENV_FILE-$DATE"
    sed -i "s|^PUSHER_APP_KEY=.*|PUSHER_APP_KEY=$(openssl rand -hex 32)|" "$ENV_FILE-$DATE"
    sed -i "s|^PUSHER_APP_SECRET=.*|PUSHER_APP_SECRET=$(openssl rand -hex 32)|" "$ENV_FILE-$DATE"
    
    # Add root user configuration
    echo "ROOT_EMAIL=$ROOT_EMAIL" >> "$ENV_FILE-$DATE"
    echo "ROOT_PASSWORD=$ROOT_PASSWORD" >> "$ENV_FILE-$DATE"
    echo "IS_FIRST_USER=1" >> "$ENV_FILE-$DATE"
fi

# Rest of the original script remains the same until after installation

# After installation completes, add root user creation
echo "Creating root user..."
docker exec -it coolify php artisan db:seed --class=CreateRootUserSeeder

# Modified success message
echo -e "\033[0;35m
   ____                            _         _       _   _                 _
  / ___|___  _ __   __ _ _ __ __ _| |_ _   _| | __ _| |_(_) ___  _ __  ___| |
 | |   / _ \| '_ \ / _\` | '__/ _\` | __| | | | |/ _\` | __| |/ _ \| '_ \/ __| |
 | |__| (_) | | | | (_| | | | (_| | |_| |_| | | (_| | |_| | (_) | | | \__ \_|
  \____\___/|_| |_|\__, |_|  \__,_|\__|\__,_|_|\__,_|\__|_|\___/|_| |_|___(_)
                   |___/
\033[0m"
echo -e "\nYour instance is ready to use!"
echo -e "You can access Coolify through your Public IP: http://$(curl -4s https://ifconfig.io):8000"
echo -e "\nLogin with:"
echo -e "Email: $ROOT_EMAIL"
echo -e "Password: [your chosen password]"

set +e
DEFAULT_PRIVATE_IP=$(ip route get 1 | sed -n 's/^.*src \([0-9.]*\) .*$/\1/p')
PRIVATE_IPS=$(hostname -I)
set -e

if [ -n "$PRIVATE_IPS" ]; then
    echo -e "\nIf your Public IP is not accessible, you can use the following Private IPs:\n"
    for IP in $PRIVATE_IPS; do
        if [ "$IP" != "$DEFAULT_PRIVATE_IP" ]; then
            echo -e "http://$IP:8000"
        fi
    done
fi

echo -e "\nWARNING: It is highly recommended to backup your Environment variables file (/data/coolify/source/.env) to a safe location, outside of this server (e.g. into a Password Manager).\n"
cp /data/coolify/source/.env /data/coolify/source/.env.backup
