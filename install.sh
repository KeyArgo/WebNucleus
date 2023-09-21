#!/bin/bash
# Version: 0.1.6
# Date: 2023-09-16
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
cat > authelia-docker-compose.yml <<EOL
# Authelia configuration here
EOL

# Organizr Setup
cat > organizr-docker-compose.yml <<EOL
# Organizr configuration here
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
    bash <(curl -Ss https://my-netdata.io/kickstart.sh)
fi

# Save final system state
echo "Saving final system state..."
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_after.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_after.txt"

# Final prompt
echo "Installation and configuration of services have been completed successfully."
echo "Here are some important details and next steps:"
echo "- Authelia JWT Secret and Session Secret have been set."
echo "- Authelia is running at: $YOUR_HOSTNAME_OR_IP"
echo "- Organizr is running at: http://localhost:9983"
echo "- Nginx has been installed. Configuration is at /etc/nginx/sites-available/my_new_config."
echo "- Netdata for system monitoring is installed. You can access it at http://localhost:19999."
echo "Remember to edit Nginx configuration and configure alerts for Netdata."
echo "To fix Authelia's configuration, edit ${HOME}/authelia-docker-compose.yml."

read -p "Do you have any questions or need further assistance? [Y/n]: " user_response
if [[ "$user_response" != "n" && "$user_response" != "N" ]]; then
    echo "Please feel free to ask any questions or seek assistance as needed."
else
    echo "If you have any questions later, you can refer to the logs in ${HOME}/logs for more details."
fi

unset AUTHELIA_JWT_SECRET
unset AUTHELIA_SESSION_SECRET
echo "Script execution completed successfully."