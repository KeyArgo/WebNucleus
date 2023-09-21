#!/bin/bash
# Version: 0.2.6
# Date: 09-22-2023
# Description: Uninstall and revert services and packages installed by the install script.

# Warning and confirmation
echo "This script will attempt to uninstall services and revert changes made by the installation."
read -p "Are you sure you want to proceed? [y/N]: " response
if [[ "$response" != "y" && "$response" != "Y" ]]; then
  echo "Exiting uninstallation."
  exit 0
fi

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root or with sudo privileges."
  exit 1
fi

# If running with sudo, get the username of the person who invoked sudo
CURRENT_USER=${SUDO_USER:-$(whoami)}

SYSTEM_STATE_DIR="/home/$CURRENT_USER/system_state_tracking"
LOGS_DIR="/home/$CURRENT_USER/logs"

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -q "$1"
}

# Function to revert package changes
revert_packages() {
  if [ -f "${SYSTEM_STATE_DIR}/package_list_before.txt" ]; then
    read -p "Do you want to revert packages to the initial state? [y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      sudo dpkg --clear-selections
      sudo dpkg --set-selections < "${SYSTEM_STATE_DIR}/package_list_before.txt"
      sudo apt-get dselect-upgrade -y
    fi
  else
    echo "Initial package list not found. Skipping package reversion."
  fi
}

# Remove Docker
if is_installed "docker" || is_installed "docker-ce" || is_installed "docker-engine"; then
  echo "Uninstalling Docker..."
  sudo apt-get purge -y docker docker-ce docker-engine docker.io containerd runc
  # If Docker was installed from get.docker.com or other methods:
  sudo rm -rf /var/lib/docker
fi

# Remove Docker Compose
if [ -f "/usr/local/bin/docker-compose" ]; then
  echo "Removing Docker Compose..."
  sudo rm /usr/local/bin/docker-compose
fi

# Remove k3s
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  echo "Uninstalling k3s..."
  /usr/local/bin/k3s-uninstall.sh
fi

# Stop Nginx if running and installed
if is_installed "nginx"; then
  # Try to stop Nginx if it's running
  if systemctl is-active --quiet nginx; then
    echo "Stopping nginx..."
    sudo systemctl stop nginx
    sudo systemctl disable nginx
  fi

  echo "Removing nginx..."
  sudo apt remove --purge -y nginx
else
  echo "Nginx is not installed. Skipping removal."
fi

# Remove Netdata if installed
if is_installed "netdata"; then
  echo "Removing Netdata..."
  sudo apt remove --purge -y netdata
  
  # Check and prompt for remaining directories
  for dir in /var/log/netdata /var/lib/netdata /var/cache/netdata; do
    if [ -d "$dir" ]; then
      read -p "Do you want to remove remaining data in $dir? [y/N]: " dir_confirm
      if [[ "$dir_confirm" == "y" || "$dir_confirm" == "Y" ]]; then
        sudo rm -rf "$dir"
      fi
    fi
  done
else
  echo "Netdata is not installed. Skipping removal."
fi

# Restore the previous package list
revert_packages

# Remove tracking and logging directories
echo "Removing tracking and logging directories..."
sudo rm -rf "${SYSTEM_STATE_DIR}"
sudo rm -rf "${LOGS_DIR}"

# Script Termination
echo "Uninstall script executed. Please manually verify that all components were successfully removed."
