#!/bin/bash

# Setting Variables
REPO_URL="https://github.com/BrockBlaze/zabbixAgent.git"
START_DIR="/home/rithm/zabbixAgent"
SOURCE_DIR="/zabbixAgent"
TARGET_DIR="/zabbixAgent/linux/scripts"
SCRIPTS_DIR="/etc/zabbix/"

# Ask for the Zabbix server IP and hostname
read -p "Enter Zabbix Server IP: " ZABBIX_SERVER_IP
read -p "Enter Hostname (this server's name): " HOSTNAME

# Install the Zabbix agent (Debian-based systems)
echo "Installing Zabbix Agent..."
sudo apt update
sudo apt install -y zabbix-agent

echo "Installing Sensors..."
# Install lm-sensors
sudo apt install -y lm-sensors

echo "Automatically Detecting Sensors..."
# Configure sensors (automatic detection)
yes | sudo sensors-detect

# Clone the repository
echo "Cloning repository..."
git clone "$REPO_URL" "$SOURCE_DIR" || { echo "Failed to clone repository"; exit 1; }

# Ensuring the target directory exists
echo "Ensuring the target directory exists..."
sudo mkdir -p "$SCRIPTS_DIR" || { echo "Failed to create the target directory."; exit 1; }

# Moving scripts to the target directory
echo "Moving scripts to the target directory..."
sudo cp -r "$TARGET_DIR" "$SCRIPTS_DIR" || { echo "Failed to move scripts."; exit 1; }

# Setting permissions
echo "Setting permissions..."
sudo chmod +x "$SCRIPTS_DIR"/scripts/*.sh || { echo "Failed to set permissions."; exit 1; }


# Backup the original configuration file (in case something goes wrong)
cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup

# Modify the zabbix_agentd.conf file to include the user input
echo "Configuring Zabbix agent..."

# Replace placeholders with actual values
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf
sed -i "s/^#Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agentd.conf

# Add custom UserParameter for Zabbix agent
if ! grep -q "UserParameter=cpu.temperature" /etc/zabbix/zabbix_agentd.conf; then
  echo "UserParameter=cpu.temperature,/etc/zabbix/scripts/cpu_temp.sh" | sudo tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Add custom UserParameter for Zabbix agent
if ! grep -q "UserParameter=login.attempts" /etc/zabbix/zabbix_agentd.conf; then
  echo "UserParameter=login.attempts,/etc/zabbix/scripts/login_monitoring.sh" | sudo tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Restart the Zabbix agent service to apply the changes
sudo systemctl restart zabbix-agent

# Enable the Zabbix agent service to start on boot
sudo systemctl enable zabbix-agent

echo "Zabbix Agent installed and configured!"

# Clean up
echo "Cleaning up..."
sudo rm -rf "$SOURCE_DIR"
sudo rm -rf "$START_DIR"

cd ~

echo "Installation completed successfully!"