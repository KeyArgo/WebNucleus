#!/bin/bash
# Version: 0.1.3
# Date: 2023-09-16
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Uninstall and revert services and packages installed by the install script.

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
  # Switch to the current user's context
  if [ -n "$SUDO_USER" ]; then
    CURRENT_USER="$SUDO_USER"
  else
    echo "Error: Cannot determine the current user."
    exit 1
  fi
fi

# Now you can use $CURRENT_USER as the current user
# For example:
rm -rf "/home/$CURRENT_USER/system_state_tracking"

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -q "$1"
}

# Function to revert changes
revert_packages() {
  # Restore package list
  sudo dpkg --clear-selections
  sudo dpkg --set-selections < "${HOME}/system_state_tracking/package_list_before.txt"
  sudo apt-get dselect-upgrade -y
}

# Delete any new files with confirmation
revert_files() {
  comm -13 "${HOME}/system_state_tracking/filesystem_before.txt" "${HOME}/system_state_tracking/filesystem_after.txt" | while read -r line; do
    if [[ "$line" == ${HOME}* ]]; then  # only delete files in the user's home directory to be safe
      read -p "Delete $line? [y/N]: " confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        sudo rm -rf "$line"
      else
        echo "Skipping deletion of $line."
      fi
    fi
  done
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
