#!/bin/bash
# Version: 0.1.5
# Date: 2023-09-16
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Install and configure services.

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Initialize locale
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -q "$1"
}

# Function to revert changes
revert_changes() {
  # Restore package list
  sudo dpkg --clear-selections
  sudo dpkg --set-selections < "${HOME}/system_state_tracking/package_list_before.txt"
  sudo apt-get dselect-upgrade -y
  # Delete any new files
  comm -13 "${HOME}/system_state_tracking/filesystem_before.txt" "${HOME}/system_state_tracking/filesystem_after.txt" | while read -r line; do
    rm -rf "$line"
  done
}

# Initialize variables and error handling
# ... (same as before)

# Enable exit on error and log errors
trap 'echo "An error occurred. Exiting. Reverting Changes..." >&2; revert_changes; echo "An error occurred at $(date)" >> ${HOME}/logs/error.log; exit 1' ERR
set -e

# Update package list and fix broken packages
sudo apt-get update -y
sudo apt-get -f install

# Enable exit on error and log errors
trap 'echo "An error occurred. Exiting. Reverting Changes..." >&2; revert_changes; echo "An error occurred at $(date)" >> ${HOME}/logs/error.log; exit 1' ERR
set -e

# Debugging and Directory Setup
echo "Starting script..."
mkdir -p "${HOME}/system_state_tracking"
mkdir -p "${HOME}/logs"

# Prompt for Secrets Early
echo "Prompting for secrets..."
read -s -p "Enter Authelia JWT Secret: " AUTHELIA_JWT_SECRET
echo
read -s -p "Enter Authelia Session Secret: " AUTHELIA_SESSION_SECRET
echo

# Save initial system state
echo "Saving initial system state..."
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_before.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_before.txt"

# Install Basic Utilities like curl, wget, and git
for pkg in curl wget git; do
  if ! is_installed "$pkg"; then
    sudo apt install -y "$pkg"
  fi
done

# Check before Docker installation
read -p "Do you want to proceed with Docker installation? [y/N]: " proceed

# Docker
curl -fsSL https://get.docker.com -o get-docker.sh
chmod +x get-docker.sh

# Use -q option to suppress help message and perform quiet installation
if [[ "$proceed" == "y" || "$proceed" == "Y" ]]; then
  sh get-docker.sh -q
  rm get-docker.sh
fi

# Docker-Compose
if ! [ -x "$(command -v docker-compose)" ]; then
  sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

# k3s
read -p "Do you want to proceed with k3s installation? [y/N]: " proceed
if [[ "$proceed" == "y" || "$proceed" == "Y" ]]; then
  curl -sfL https://get.k3s.io | sh -
fi

# Fetch UID and GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Prompt for the desired hostname or IP address
read -p "Enter the hostname or IP address for Authelia (e.g., 10.1.1.100): " YOUR_HOSTNAME_OR_IP

# Create Authelia Docker Compose file
cat > authelia-docker-compose.yml <<EOL
# Authelia configuration here
EOL

# Create Organizr Docker Compose File
cat > organizr-docker-compose.yml <<EOL
# Organizr configuration here
EOL

# Start Organizr services
if [ -f "$HOME/organizr-docker-compose.yml" ]; then
  docker-compose -f "$HOME/organizr-docker-compose.yml" up -d
else
  echo "Warning: $HOME/organizr-docker-compose.yml not found. Skipping Docker Compose for Organizr."
fi

# Nginx
if ! is_installed 'nginx'; then
  sudo apt install -y nginx
fi

# Sample Nginx config
sudo bash -c "cat > /etc/nginx/sites-available/my_new_config <<EOL
server {
  listen 80;
  # more configuration
}
EOL"

# Reload Nginx to apply new settings
sudo nginx -s reload

# Install Netdata for Monitoring
if ! [ -x "$(command -v netdata)" ]; then
  bash <(curl -Ss https://my-netdata.io/kickstart.sh)
fi

# Create a simple alert for Netdata
# Code for Netdata alerts here

# Restart Netdata to apply the configuration
service netdata restart

echo "Netdata installed. You may want to configure alerts."

# Enable services to start at boot
sudo systemctl enable nginx
sudo systemctl enable netdata

# Alert: modify /etc/nginx/sites-available/my_new_config
echo "Remember to edit the Nginx configuration file located at /etc/nginx/sites-available/my_new_config."

# Prompt user to revert changes if they wish to
read -p 'Do you want to revert changes? [y/N]: ' revert
if [[ "$revert" == "y" || "$revert" == "Y" ]]; then
  revert_changes
  echo "Changes reverted."
fi

# Script Termination
echo "Script execution completed successfully. You may need to configure some services manually as indicated above. Please refer to the logs in ${HOME}/logs for more details."
echo "Remember to test this thoroughly before running it on a production system."

# Save final system state
echo "Saving final system state..."
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_after.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_after.txt"

# Compare initial and final system state and remove any newly created files
if [ -f "${HOME}/system_state_tracking/filesystem_before.txt" ] && [ -f "${HOME}/system_state_tracking/filesystem_after.txt" ]; then
  echo "Comparing initial and final system state..."
  comm -13 "${HOME}/system_state_tracking/filesystem_before.txt" "${HOME}/system_state_tracking/filesystem_after.txt" | while read -r line; do
    rm -rf "$line"
  done
else
  echo "Warning: filesystem_before.txt or filesystem_after.txt not found. Skipping comm command."
fi

# Re-enable set -e
set -e

# Final prompt
echo "Installation and configuration of services have been completed successfully."
echo "Here are some important details and next steps:"
echo "- Authelia JWT Secret and Session Secret have been set."
echo "- Authelia is running at: $YOUR_HOSTNAME_OR_IP (Please update the configuration to use your desired domain or IP address)"
echo "- Organizr is running at: http://localhost:9983 (you can configure it further)"
echo "- Nginx has been installed, and you can configure it at /etc/nginx/sites-available/my_new_config."
echo "- Netdata for system monitoring is installed. You can access it at http://localhost:19999."
echo "Remember to edit Nginx configuration to suit your needs and configure alerts for Netdata."
echo "To fix Authelia's configuration, edit ${HOME}/authelia-docker-compose.yml and update the necessary parameters."

read -p "Do you have any questions or need further assistance? [Y/n]: " user_response
if [[ "$user_response" != "n" && "$user_response" != "N" ]]; then
  echo "Please feel free to ask any questions or seek assistance as needed."
else
  echo "If you have any questions later, you can refer to the logs in ${HOME}/logs for more details."
fi

unset AUTHELIA_JWT_SECRET
unset AUTHELIA_SESSION_SECRET

echo "Script execution completed successfully."
