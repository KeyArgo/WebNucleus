#!/bin/bash
# Version: 0.1.4
# Date: 2023-09-16
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Uninstall and revert services and packages installed by the install script.

# Enable exit on error and log errors
trap 'echo "An error occurred while uninstalling. Exiting..." >&2; exit 1' ERR
set -e

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
  if [ -n "$SUDO_USER" ]; then
    CURRENT_USER="$SUDO_USER"
  else
    echo "Error: Cannot determine the current user."
    exit 1
  fi
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

# Delete any new files with confirmation
revert_files() {
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
}

# Uninstall Docker
echo "Uninstalling Docker..."
sudo apt-get remove docker docker-engine docker.io containerd runc

# Remove Docker Compose
echo "Removing Docker Compose..."
sudo rm /usr/local/bin/docker-compose

# Remove k3s
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  echo "Uninstalling k3s..."
  /usr/local/bin/k3s-uninstall.sh
else
  echo "k3s uninstall script not found. Skipping..."
fi

# Disable Services from Starting at Boot
echo "Disabling services from starting at boot..."
sudo systemctl disable nginx
sudo systemctl disable netdata

# Remove nginx if installed
if is_installed "nginx"; then
  echo "Removing nginx..."
  sudo apt remove -y nginx
fi

# Remove Netdata if installed
if is_installed "netdata"; then
  echo "Removing Netdata..."
  sudo apt remove -y netdata
fi

# Restore the previous package list and delete new files
revert_packages
revert_files

# Remove tracking and logging directories
echo "Removing tracking and logging directories..."
rm -rf "${HOME}/system_state_tracking"
rm -rf "${HOME}/logs"

# Script Termination
echo "Uninstall script executed. Please manually verify that all components were successfully removed."