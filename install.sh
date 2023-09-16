#!/bin/bash
# Version: 0.1.1
# Date: 2023-09-16
# Dependencies: Assumes Ubuntu or Debian-based system with apt package manager.
# Description: Install and configure services.

# Initialize
CURRENT_USER=$(whoami)

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -q "$1"
}

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
mkdir -p "/home/$CURRENT_USER/system_state_tracking"


# Prompt for Secrets Early
read -sp "Enter Authelia JWT Secret: " AUTHELIA_JWT_SECRET
read -sp "Enter Authelia Session Secret: " AUTHELIA_SESSION_SECRET
export AUTHELIA_JWT_SECRET
export AUTHELIA_SESSION_SECRET

# Create tracking and logging directories under current user
mkdir -p "${HOME}/system_state_tracking"
mkdir -p "${HOME}/logs"

# Enable exit on error and log errors
trap 'echo "An error occurred. Exiting. Reverting Changes..." >&2; revert_changes; echo "An error occurred at $(date)" >> ${HOME}/logs/error.log; exit 1' ERR
set -e

# Update and upgrade packages if not done already
if ! [ -f "${HOME}/system_state_tracking/apt_updated" ]; then
  sudo apt update -y
  sudo apt dist-upgrade -y --allow-remove-essential || true
  touch "${HOME}/system_state_tracking/apt_updated"
fi

# Temporary disable set -e for non-critical section
set +e

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

# Save system state before installation
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_before.txt"
find /etc /usr /var -maxdepth 3 > "${HOME}/system_state_tracking/filesystem_before.txt"

# Install Basic Utilities like curl, wget, and git
for pkg in curl wget git; do
  if ! is_installed "$pkg"; then
    sudo apt install -y "$pkg"
  fi
done

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
      - 'traefik.enable=true'
      - 'traefik.http.routers.authelia.rule=Host(\${YOUR_HOSTNAME_OR_IP})'
      - 'traefik.http.routers.authelia.entrypoints=https'
      - 'traefik.http.routers.authelia.tls=true'
      - 'traefik.http.middlewares.authelia.forwardAuth.address=http://authelia:9091/api/verify?rd=https://\${YOUR_HOSTNAME_OR_IP}'
      - 'traefik.http.middlewares.authelia.forwardAuth.trustForwardHeader=true'
      - 'traefik.http.middlewares.authelia.forwardAuth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email'
      - 'traefik.http.middlewares.authelia-basic.forwardAuth.address=http://authelia:9091/api/verify?auth=basic'
      - 'traefik.http.middlewares.authelia-basic.forwardAuth.trustForwardHeader=true'
      - 'traefik.http.middlewares.authelia-basic.forwardAuth.authResponseHeaders=Remote-User,Remote-Groups,Remote-Name,Remote-Email'
      - 'traefik.http.services.authelia.loadbalancer.server.port=9091'
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

CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

export CURRENT_UID
export CURRENT_GID

docker-compose -f organizr-docker-compose.yml up -d

# Create Organizr Docker Compose File
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

# Start services
docker-compose -f organizr-docker-compose.yml up -d

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
read -p "Enter the CPU warning threshold [default: 70]: " cpu_warn
read -p "Enter the CPU critical threshold [default: 80]: " cpu_crit
echo -e "alarm: high_cpu_use\non: system.cpu\nlookup: average -10s unaligned of user,system\nunits: %\nevery: 1m\nwarn: \$this > ${cpu_warn:-70}\ncrit: \$this > ${cpu_crit:-80}\ninfo: the system's CPU utilization is getting high\nto: sysadmin" > /etc/netdata/health.d/high_cpu.conf

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

# Save system state after installation
dpkg --get-selections > "${HOME}/system_state_tracking/package_list_after.txt"
find / 2>/dev/null > "${HOME}/system_state_tracking/filesystem_after.txt"

# Re-enable set -e
set -e

# Final prompt
echo "Installation and configuration of services have been completed successfully."
echo "Here are some important details and next steps:"
echo "- Authelia JWT Secret and Session Secret have been set."
echo "- Authelia is running at: https://10.1.1.100 (Please update the configuration to use your desired domain or IP address)"
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

