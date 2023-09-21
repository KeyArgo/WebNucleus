#!/bin/bash
# Version: 0.1.5
# Date: 2023-09-16
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
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER="$SUDO_USER"
else
    CURRENT_USER="$(whoami)"
fi

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
if is_installed "docker"; then
  echo "Uninstalling Docker..."
  sudo apt-get purge -y docker docker-engine docker.io containerd runc
  # Remove Docker data directory if it exists
  if [ -d "/var/lib/docker" ]; then
    read -p "Do you want to remove Docker data (containers, images, volumes, etc.)? [y/N]: " docker_data_confirm
    if [[ "$docker_data_confirm" == "y" || "$docker_data_confirm" == "Y" ]]; then
      sudo rm -rf /var/lib/docker
    fi
  fi
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

# After uninstalling k3s, manually check for any remaining files or directories
if [ -d "/var/lib/rancher/k3s" ]; then
  read -p "Do you want to remove remaining k3s data? [y/N]: " k3s_data_confirm
  if [[ "$k3s_data_confirm" == "y" || "$k3s_data_confirm" == "Y" ]]; then
    sudo rm -rf /var/lib/rancher/k3s
  fi
fi

# Stop and disable services
for service in nginx netdata; do
  if systemctl is-active --quiet "$service"; then
    echo "Stopping $service..."
    sudo systemctl stop "$service"
  fi

  if systemctl is-enabled --quiet "$service"; then
    echo "Disabling $service from starting at boot..."
    sudo systemctl disable "$service"
  fi
done

# Remove nginx if installed
if is_installed "nginx"; then
  echo "Removing nginx..."
  sudo apt remove --purge -y nginx
fi

# Remove Netdata if installed
if is_installed "netdata"; then
  echo "Removing Netdata..."
  sudo apt remove --purge -y netdata
fi

# Restore the previous package list
revert_packages

# Delete new files
if [ -f "${SYSTEM_STATE_DIR}/filesystem_before.txt" ] && [ -f "${SYSTEM_STATE_DIR}/filesystem_after.txt" ]; then
  comm -13 "${SYSTEM_STATE_DIR}/filesystem_before.txt" "${SYSTEM_STATE_DIR}/filesystem_after.txt" | while read -r line; do
    if [[ "$line" == ${HOME}* ]]; then  # only delete files in the user's home directory to be safe
      read -p "Delete $line? [y/N]: " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        sudo rm -rf "$line"
      else
        echo "Skipping deletion of $line."
      fi
    fi
  done
else
  echo "Filesystem state files not found. Skipping file deletion."
fi

# Remove tracking and logging directories
echo "Removing tracking and logging directories..."
rm -rf "${SYSTEM_STATE_DIR}"
rm -rf "${LOGS_DIR}"

# Script Termination
echo "Uninstall script executed. Please manually verify that all components were successfully removed."
