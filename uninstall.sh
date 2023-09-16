#!/bin/bash
# Version: 0.1.1
# Date: 2023-09-16
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Uninstall and revert services and packages installed by the install script.

# List of packages installed by the installation script
PACKAGES_INSTALLED=("docker" "docker-engine" "docker.io" "containerd" "runc" "nginx" "netdata")

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
  for pkg in "${PACKAGES_INSTALLED[@]}"; do
    sudo dpkg --set-selections < "${HOME}/system_state_tracking/package_list_before.txt"
  done
  sudo apt-get dselect-upgrade -y
}

# Delete any new files
revert_files() {
  comm -13 "${HOME}/system_state_tracking/filesystem_before.txt" "${HOME}/system_state_tracking/filesystem_after.txt" | while read -r line; do
    if [[ "$line" == ${HOME}* ]]; then  # only delete files in the user's home directory to be safe
      sudo rm -rf "$line"
    fi
  done
}

# Uninstall Docker
for pkg in "${PACKAGES_INSTALLED[@]}"; do
  if [[ "$pkg" == "docker" || "$pkg" == "docker-engine" || "$pkg" == "docker.io" || "$pkg" == "containerd" || "$pkg" == "runc" ]]; then
    sudo apt-get remove "$pkg"
  fi
done

# Remove Docker Compose
sudo rm /usr/local/bin/docker-compose

# Remove k3s
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  /usr/local/bin/k3s-uninstall.sh
else
  echo "k3s uninstall script not found. Skipping..."
fi

#Disable Services from Starting at Boot
sudo systemctl disable nginx
sudo systemctl disable netdata

# Remove nginx
if is_installed "nginx"; then
  sudo apt remove -y nginx
fi

# Remove Netdata
if is_installed "netdata"; then
  sudo apt remove -y netdata
fi

# Restore the previous package list and delete new files
revert_packages
revert_files

# Remove tracking and logging directories
rm -rf "${HOME}/system_state_tracking"
rm -rf "${HOME}/logs"

# Script Termination
echo "Uninstall script executed. Please manually verify that all components were successfully removed."
