#!/bin/bash

# Setting Variables
REPO_URL="https://github.com/BrockBlaze/zabbixAgent.git"
USERNAME=$(logname)
START_DIR="/home/$USERNAME/zabbixAgent"
SOURCE_DIR="/zabbixAgent"
TARGET_DIR="/zabbixAgent/linux/enhanced_scripts"
SCRIPTS_DIR="/etc/zabbix/"
LOG_FILE="/var/log/zabbix/install.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

# Create log directory
mkdir -p "$(dirname $LOG_FILE)"
log "Starting Zabbix Agent installation..."

# Check system compatibility
if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
    error "This script only supports Ubuntu/Debian systems"
fi

# Ask for the Zabbix server IP and hostname
read -p "Enter Zabbix Server IP: " ZABBIX_SERVER_IP
read -p "Enter Hostname (this server's name): " HOSTNAME

if [ -z "$ZABBIX_SERVER_IP" ] || [ -z "$HOSTNAME" ]; then
    error "Zabbix Server IP and Hostname are required"
fi

# Install the Zabbix agent
log "Installing Zabbix Agent..."
apt update || error "Failed to update package list"
apt install -y zabbix-agent || error "Failed to install Zabbix agent"

log "Installing Sensors..."
# Install lm-sensors
apt install -y lm-sensors || error "Failed to install lm-sensors"

log "Automatically Detecting Sensors..."
# Configure sensors (automatic detection)
yes | sensors-detect || log "Warning: sensors-detect may not have completed successfully"

# Clone the repository
log "Cloning repository..."
git clone "$REPO_URL" "$SOURCE_DIR" || error "Failed to clone repository"

# Ensuring the target directory exists
log "Ensuring the target directory exists..."
mkdir -p "$SCRIPTS_DIR" || error "Failed to create the target directory"

# Moving scripts to the target directory
log "Moving scripts to the target directory..."
cp -r "$TARGET_DIR" "$SCRIPTS_DIR" || error "Failed to move scripts"

# Setting permissions
log "Setting permissions..."
chmod +x "$SCRIPTS_DIR"/enhanced_scripts/*.sh || error "Failed to set permissions"

# Create dedicated log directory with proper permissions
log "Creating log directory with proper permissions..."
mkdir -p /var/log/zabbix || error "Failed to create log directory"
chown -R zabbix:zabbix /var/log/zabbix || error "Failed to set permissions on log directory"

# Configure sudo permissions for the zabbix user
log "Configuring sudo permissions for Zabbix user..."
# Create a sudoers file for zabbix
cat > /etc/sudoers.d/zabbix << EOF
# Allow zabbix user to access system logs and run specific commands without password
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix || error "Failed to set permissions on sudoers file"

# Backup the original configuration file
log "Backing up original configuration..."
cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup || error "Failed to backup configuration"

# Modify the zabbix_agentd.conf file
log "Configuring Zabbix agent..."

# Replace placeholders with actual values
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf || error "Failed to set Server IP"
sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agentd.conf || error "Failed to set Hostname"

# Add custom UserParameters
log "Adding custom UserParameters..."

# CPU Temperature monitoring
if ! grep -q "UserParameter=cpu.temperature" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=cpu.temperature,/etc/zabbix/enhanced_scripts/cpu_temp.sh" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Login monitoring - full JSON
if ! grep -q "UserParameter=login.monitoring" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=login.monitoring,/etc/zabbix/enhanced_scripts/login_monitoring.sh" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Login monitoring - individual metrics
if ! grep -q "UserParameter=login.monitoring.failed_logins" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=login.monitoring.failed_logins,/etc/zabbix/enhanced_scripts/login_monitoring.sh failed_logins" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

if ! grep -q "UserParameter=login.monitoring.successful_logins" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=login.monitoring.successful_logins,/etc/zabbix/enhanced_scripts/login_monitoring.sh successful_logins" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

if ! grep -q "UserParameter=login.monitoring.total_attempts" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=login.monitoring.total_attempts,/etc/zabbix/enhanced_scripts/login_monitoring.sh total_attempts" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

# System health monitoring
if ! grep -q "UserParameter=system.health" /etc/zabbix/zabbix_agentd.conf; then
    echo "UserParameter=system.health,/etc/zabbix/enhanced_scripts/system_health.sh" | tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Validate configuration
log "Validating configuration..."
zabbix_agentd -t /etc/zabbix/zabbix_agentd.conf || error "Configuration validation failed"

# Restart the Zabbix agent service
log "Restarting Zabbix agent..."
systemctl restart zabbix-agent || error "Failed to restart Zabbix agent"

# Enable the Zabbix agent service
log "Enabling Zabbix agent service..."
systemctl enable zabbix-agent || error "Failed to enable Zabbix agent"

# Verify service status
log "Verifying service status..."
if ! systemctl is-active --quiet zabbix-agent; then
    error "Zabbix agent service is not running"
fi

# Clean up
log "Cleaning up..."
rm -rf "$SOURCE_DIR" || log "Warning: Failed to remove source directory"
rm -rf "$START_DIR" || log "Warning: Failed to remove start directory"

log "Installation completed successfully!"
echo
echo "Zabbix Agent has been installed and configured successfully!"
echo "Configuration file: /etc/zabbix/zabbix_agentd.conf"
echo "Log file: $LOG_FILE"
echo "Enhanced monitoring scripts are installed in: $SCRIPTS_DIR/enhanced_scripts/"
echo
echo "To uninstall, run: ./uninstall.sh"

