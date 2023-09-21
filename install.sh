#!/bin/bash
# Version: 0.1.9
# Date: 09-21-2023
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Install and configure services.

repair_package_system() {
    # Recreate missing directories
    sudo mkdir -p /var/cache/apt/archives/partial

    # Clear APT cache
    sudo apt clean

    # Update APT package list
    sudo apt update

    # Reconfigure dpkg database
    sudo dpkg --configure -a

    # Fix broken dependencies
    sudo apt-get -f install

    # Update and upgrade
    sudo apt update && sudo apt upgrade

    # Update dpkg available database
    sudo mv /var/lib/dpkg/available /var/lib/dpkg/available.backup
    sudo touch /var/lib/dpkg/available
    sudo sh -c 'for i in /var/lib/apt/lists/*_Packages; do dpkg --merge-avail "$i"; done'
}

is_installed() {
    dpkg -l | grep -q "$1"
}

revert_changes() {
    # Restore package list
    sudo dpkg --clear-selections
    sudo dpkg --set-selections < "${HOME}/system_state_tracking/package_list_before.txt"
    sudo apt-get dselect-upgrade -y
}

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Initialize locale
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"

# Initialize variables and error handling
trap 'echo "An error occurred. Exiting. Reverting Changes..." >&2; revert_changes; echo "An error occurred at $(date)" >> ${HOME}/logs/error.log; exit 1' ERR
set -e

echo "This script will attempt to install and configure services."
read -p "Are you sure you want to proceed? [y/N]: " response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Exiting installation."
    exit 0
fi

# Debugging and Directory Setup
echo "Starting script..."
mkdir -p "${HOME}/system_state_tracking"
mkdir -p "${HOME}/logs"

# Save initial system state
echo "Saving initial system state..."
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_before.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_before.txt"

# Repair the package management system
repair_package_system

# Prompt for Secrets Early
echo "Prompting for secrets..."
read -s -p "Enter Authelia JWT Secret: " AUTHELIA_JWT_SECRET
echo
read -s -p "Enter Authelia Session Secret: " AUTHELIA_SESSION_SECRET
echo

# Install Basic Utilities like curl, wget, and git
for pkg in curl wget git; do
  if ! is_installed "$pkg"; then
    sudo apt install -y "$pkg"
  fi
done

# Docker Installation
read -p "Do you want to proceed with Docker installation? [y/N]: " proceed
if [[ "$proceed" == "y" || "$proceed" == "Y" ]]; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    chmod +x get-docker.sh
    sh get-docker.sh -q
    rm get-docker.sh
fi

# Docker-Compose Installation
if ! [ -x "$(command -v docker-compose)" ]; then
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# k3s Installation
read -p "Do you want to proceed with k3s installation? [y/N]: " proceed
if [[ "$proceed" == "y" || "$proceed" == "Y" ]]; then
    curl -sfL https://get.k3s.io | sh -
fi

# Fetch UID and GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Authelia Setup
read -p "Enter the hostname or IP address for Authelia (e.g., 10.1.1.100): " YOUR_HOSTNAME_OR_IP
YOUR_HOSTNAME_OR_IP_VALUE=$(echo $YOUR_HOSTNAME_OR_IP)
cat > authelia-docker-compose.yml <<EOL
version: '3'
services:
  authelia:
    image: authelia/authelia
    container_name: authelia
    volumes:
      - ${HOME}/docker/authelia/config:/config
    networks:
      - proxy
    security_opt:
      - no-new-privileges:true
    labels:
      - traefik.enable=true
      - traefik.http.routers.authelia.rule=Host(${YOUR_HOSTNAME_OR_IP_VALUE})
      - traefik.http.routers.authelia.entrypoints=https
      - traefik.http.routers.authelia.tls=true
      - traefik.http.middlewares.authelia.forwardAuth.address=http://authelia:9091/api/verify?rd=https://${YOUR_HOSTNAME_OR_IP_VALUE}
      - traefik.http.middlewares.authelia.forwardAuth.trustForwardHeader=true
      - traefik.http.middlewares.authelia.forwardAuth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email
      - traefik.http.middlewares.authelia-basic.forwardAuth.address=http://authelia:9091/api/verify?auth=basic
      - traefik.http.middlewares.authelia-basic.forwardAuth.trustForwardHeader=true
      - traefik.http.middlewares.authelia-basic.forwardAuth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email
      - traefik.http.services.authelia.loadbalancer.server.port=9091
    ports:
      - 9091:9091
    restart: unless-stopped
    environment:
      - AUTHELIA_JWT_SECRET=${AUTHELIA_JWT_SECRET}
      - AUTHELIA_SESSION_SECRET=${AUTHELIA_SESSION_SECRET}
      - TZ=Europe/London
    healthcheck:
      disable: true

  redis:
    image: redis:alpine
    container_name: redis
    volumes:
      - ${HOME}/docker/redis:/data
    networks:
      - proxy
    expose:
      - 6379
    restart: unless-stopped
    environment:
      - TZ=America/Denver

networks:
  proxy:
    external: true
EOL

# Organizr Setup
cat > organizr-docker-compose.yml <<EOL
version: '3.3'
services:
  organizr:
    image: organizr/organizr
    container_name: organizr
    environment:
      - PUID=${CURRENT_UID}
      - PGID=${CURRENT_GID}
    volumes:
      - ${HOME}/organizr/config:/config
    ports:
      - 9983:80
    restart: unless-stopped
EOL

# Nginx Setup
if ! is_installed 'nginx'; then
    sudo apt install -y nginx
fi
sudo bash -c "cat > /etc/nginx/sites-available/my_new_config <<EOL
server {
  listen 80;
  # more configuration
}
EOL"
sudo nginx -s reload

# Netdata Installation
if ! [ -x "$(command -v netdata)" ]; then
    sudo -u _apt bash <(curl -Ss https://my-netdata.io/kickstart.sh)
fi

# Save final system state
echo "Saving final system state..."
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_after.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_after.txt"

# Start Authelia and Organizr containers
docker-compose -f authelia-docker-compose.yml up -d
docker-compose up -d organizr

# Final prompt
echo "Installation and configuration of services have been completed successfully."
echo "Here are some important details and next steps:"
echo "----------------------------------------------"
echo "Authelia:"
echo "- JWT Secret: ${AUTHELIA_JWT_SECRET}"
echo "- Session Secret: ${AUTHELIA_SESSION_SECRET}"
echo "- Running at: http://${YOUR_HOSTNAME_OR_IP}:9091"  # Assuming 9091 is the port for Authelia, change if different
echo
echo "Organizr:"
echo "- Running at: http://localhost:9983"
echo
echo "Nginx:"
echo "- Installed and configured."
echo "- Configuration is at /etc/nginx/sites-available/my_new_config."
echo
echo "Netdata:"
echo "- For system monitoring, access it at http://localhost:19999."
echo
echo "NOTES:"
echo "1. Remember to edit Nginx configuration and configure alerts for Netdata."
echo "2. To fix Authelia's configuration, edit ${HOME}/authelia-docker-compose.yml."
echo "----------------------------------------------"

read -p "Do you have any questions or need further assistance? [Y/n]: " user_response
if [[ "$user_response" != "n" && "$user_response" != "N" ]]; then
    echo "Please feel free to ask any questions or seek assistance as needed."
else
    echo "If you have any questions later, you can refer to the logs in ${HOME}/logs for more details."
fi

unset AUTHELIA_JWT_SECRET
unset AUTHELIA_SESSION_SECRET
echo "Script execution completed successfully."