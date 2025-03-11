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

# Function to validate IP address format
validate_ip() {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip_array=($ip)
        IFS=$OIFS
        
        # Test values are in range 0-255
        [[ ${ip_array[0]} -le 255 && ${ip_array[1]} -le 255 && ${ip_array[2]} -le 255 && ${ip_array[3]} -le 255 ]]
        stat=$?
    fi
    
    return $stat
}

# Ask for the Zabbix server IP with validation
get_valid_ip() {
    local ip_valid=0
    local ip_address=""
    
    while [ $ip_valid -eq 0 ]; do
        read -p "Enter Zabbix Server IP: " ip_address
        
        if validate_ip "$ip_address"; then
            ip_valid=1
        else
            echo "Invalid IP address format. Please enter a valid IPv4 address."
        fi
    done
    
    echo "$ip_address"
}

# Get the server IP with validation
ZABBIX_SERVER_IP=$(get_valid_ip)

# Get the hostname with validation
get_valid_hostname() {
    local hostname=""
    
    while [ -z "$hostname" ]; do
        read -p "Enter Hostname (this server's name): " hostname
        
        if [ -z "$hostname" ]; then
            echo "Hostname cannot be empty. Please enter a valid hostname."
        fi
    done
    
    echo "$hostname"
}

# Get the hostname with validation
HOSTNAME=$(get_valid_hostname)

# Install the Zabbix agent
log "Installing Zabbix Agent..."
apt update || error "Failed to update package list"
apt install -y zabbix-agent || error "Failed to install Zabbix agent"

log "Installing Sensors..."
# Install lm-sensors
apt install -y lm-sensors || error "Failed to install lm-sensors"

log "Installing htop..."
# Install htop for system monitoring
apt install -y htop || error "Failed to install htop"

log "Automatically Detecting Sensors..."
# Configure sensors (automatic detection)
yes | sensors-detect || log "Warning: sensors-detect may not have completed successfully"

# Clone the repository
log "Cloning repository..."
if [ -d "$SOURCE_DIR" ]; then
    log "Source directory already exists, removing it first..."
    rm -rf "$SOURCE_DIR"
fi
git clone "$REPO_URL" "$SOURCE_DIR" || error "Failed to clone repository"

# Ensuring the target directory exists
log "Ensuring the target directory exists..."
mkdir -p "$SCRIPTS_DIR/enhanced_scripts" || error "Failed to create the target directory"

# Moving scripts to the target directory
log "Moving scripts to the target directory..."
cp -r "$TARGET_DIR"/* "$SCRIPTS_DIR/enhanced_scripts/" || error "Failed to move scripts"

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
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee, /usr/bin/htop, /usr/bin/apt-get
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix || error "Failed to set permissions on sudoers file"

# Backup the original configuration file
log "Backing up original configuration..."
if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
    cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup.$(date +"%Y%m%d%H%M%S") || error "Failed to backup configuration"
fi

# Create a fresh main configuration file
log "Creating a fresh main configuration file..."
cat > /etc/zabbix/zabbix_agentd.conf << EOF
# Basic Zabbix configuration
Server=$ZABBIX_SERVER_IP
ServerActive=$ZABBIX_SERVER_IP
Hostname=$HOSTNAME
LogFile=/var/log/zabbix/zabbix_agentd.log
Include=/etc/zabbix/zabbix_agentd.d/*.conf
EOF

# Create include directory if it doesn't exist
log "Setting up include directory..."
mkdir -p /etc/zabbix/zabbix_agentd.d

# Create a file for basic non-problematic parameters
log "Creating basic parameters file..."
cat > /etc/zabbix/zabbix_agentd.d/basic_params.conf << EOF
# CPU Temperature monitoring
UserParameter=cpu.temperature,/etc/zabbix/enhanced_scripts/cpu_temp.sh

# Login monitoring - full JSON
UserParameter=login.monitoring,/etc/zabbix/enhanced_scripts/login_monitoring.sh

# Login monitoring - individual metrics
UserParameter=login.monitoring.failed_logins,/etc/zabbix/enhanced_scripts/login_monitoring.sh failed_logins
UserParameter=login.monitoring.successful_logins,/etc/zabbix/enhanced_scripts/login_monitoring.sh successful_logins
UserParameter=login.monitoring.total_attempts,/etc/zabbix/enhanced_scripts/login_monitoring.sh total_attempts

# User detailed login information
UserParameter=login.monitoring.user_details,/etc/zabbix/enhanced_scripts/login_monitoring.sh user_details

# Login events with IP addresses
UserParameter=login.monitoring.events,/etc/zabbix/enhanced_scripts/login_monitoring.sh login_events

# System health monitoring
UserParameter=system.health,/etc/zabbix/enhanced_scripts/system_health.sh
EOF

# Create a separate file for the system.htop parameters
log "Creating system monitoring parameters file..."
cat > /etc/zabbix/zabbix_agentd.d/system_htop.conf << EOF
# System htop monitoring
UserParameter=system.htop,/etc/zabbix/enhanced_scripts/system_htop.sh

# System process monitoring with parameters
UserParameter=system.process[*],/etc/zabbix/enhanced_scripts/system_htop.sh \$1 \$2
EOF

# Set proper permissions
log "Setting proper permissions..."
chmod 644 /etc/zabbix/zabbix_agentd.conf
chmod 644 /etc/zabbix/zabbix_agentd.d/*.conf

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
if [ -d "$START_DIR" ]; then
    rm -rf "$START_DIR" || log "Warning: Failed to remove start directory"
fi

log "Installation completed successfully!"
cd ~
echo
echo "Zabbix Agent has been installed and configured successfully!"
echo "Configuration file: /etc/zabbix/zabbix_agentd.conf"
echo "Log file: $LOG_FILE"
echo "Enhanced monitoring scripts are installed in: $SCRIPTS_DIR/enhanced_scripts/"
echo
echo "To uninstall, run: ./uninstall.sh"

