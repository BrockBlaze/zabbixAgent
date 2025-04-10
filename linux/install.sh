#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Basic configuration
LOG_FILE="/var/log/zabbix/install.log"
VERSION="2.0.1"

# Create log directory and start logging
mkdir -p "$(dirname $LOG_FILE)" || { echo "Failed to create log directory" >&2; exit 1; }
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Zabbix Agent installation (Version $VERSION)..." | tee -a "$LOG_FILE"

# Check system compatibility
if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
    echo "ERROR: This script only supports Ubuntu/Debian systems" | tee -a "$LOG_FILE"
    exit 1
fi

# Get Zabbix server IP
echo "Enter Zabbix Server IP [default: 192.168.1.30]: "
read ZABBIX_SERVER_IP
if [ -z "$ZABBIX_SERVER_IP" ]; then
    ZABBIX_SERVER_IP="192.168.1.30"
fi

# Get hostname
echo "Enter Hostname for this server [default: $(hostname)]: "
read HOSTNAME
if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

# Add Zabbix repository
echo "Adding Zabbix repository..." | tee -a "$LOG_FILE"
wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu$(lsb_release -rs)_all.deb || { echo "Failed to download Zabbix repository package" >&2; exit 1; }
dpkg -i zabbix-release_6.4-1+ubuntu$(lsb_release -rs)_all.deb || { echo "Failed to install Zabbix repository" >&2; exit 1; }
# rm zabbix-release_6.4-1+ubuntu$(lsb_release -rs)_all.deb

# Update package list
echo "Updating package list..." | tee -a "$LOG_FILE"
apt update || { echo "Failed to update package list" >&2; exit 1; }


# Install required packages
echo "Installing required packages..." | tee -a "$LOG_FILE"
apt install -y zabbix-agent2 lm-sensors || { echo "Failed to install required packages" >&2; exit 1; }

# Configure sensors (with error handling)
echo "Configuring sensors..." | tee -a "$LOG_FILE"
if command -v sensors-detect >/dev/null 2>&1; then
    yes | sensors-detect >/dev/null 2>&1 || echo "Warning: sensors-detect may not have completed successfully" | tee -a "$LOG_FILE"
else
    echo "Warning: sensors-detect not found, skipping sensor configuration" | tee -a "$LOG_FILE"
fi

# Create necessary directories
echo "Creating required directories..." | tee -a "$LOG_FILE"
mkdir -p /etc/zabbix/scripts || { echo "Failed to create scripts directory" >&2; exit 1; }
mkdir -p /etc/zabbix/zabbix_agent2.d || { echo "Failed to create agent2.d directory" >&2; exit 1; }
mkdir -p /var/log/zabbix || { echo "Failed to create log directory" >&2; exit 1; }
mkdir -p /var/run/zabbix || { echo "Failed to create run directory" >&2; exit 1; }

# Copy monitoring scripts
echo "Installing monitoring scripts..." | tee -a "$LOG_FILE"
if [ ! -d "$(dirname "$0")/scripts" ]; then
    echo "Error: Scripts directory not found" >&2
    exit 1
fi
cp -r "$(dirname "$0")/scripts"/*.sh /etc/zabbix/scripts/ || { echo "Failed to copy scripts" >&2; exit 1; }
chmod +x /etc/zabbix/scripts/*.sh || { echo "Failed to set script permissions" >&2; exit 1; }

# Create Zabbix agent configuration
echo "Creating Zabbix agent configuration..." | tee -a "$LOG_FILE"
if [ ! -f /etc/zabbix/zabbix_agent2.conf ]; then
    cat > /etc/zabbix/zabbix_agent2.conf << EOF
Server=$ZABBIX_SERVER_IP
ServerActive=$ZABBIX_SERVER_IP
Hostname=$HOSTNAME
PidFile=/var/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=0
EnableRemoteCommands=1
LogRemoteCommands=1
Timeout=30
Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOF
else
    # Only update specific lines if they exist, otherwise append them
    if ! grep -q "^Server=" /etc/zabbix/zabbix_agent2.conf; then
        echo "Server=$ZABBIX_SERVER_IP" >> /etc/zabbix/zabbix_agent2.conf
    else
        sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    fi

    if ! grep -q "^ServerActive=" /etc/zabbix/zabbix_agent2.conf; then
        echo "ServerActive=$ZABBIX_SERVER_IP" >> /etc/zabbix/zabbix_agent2.conf
    else
        sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
    fi

    if ! grep -q "^Hostname=" /etc/zabbix/zabbix_agent2.conf; then
        echo "Hostname=$HOSTNAME" >> /etc/zabbix/zabbix_agent2.conf
    else
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agent2.conf
    fi

    # Ensure Include directive exists
    if ! grep -q "^Include=" /etc/zabbix/zabbix_agent2.conf; then
        echo "Include=/etc/zabbix/zabbix_agent2.d/*.conf" >> /etc/zabbix/zabbix_agent2.conf
    fi
fi

# Create UserParameters file if it doesn't exist
if [ ! -f /etc/zabbix/zabbix_agent2.d/userparameters.conf ]; then
    cat > /etc/zabbix/zabbix_agent2.d/userparameters.conf << EOF
# Custom script parameters
UserParameter=system.temperature,/etc/zabbix/scripts/cpu_temp.sh
UserParameter=system.processes,/etc/zabbix/scripts/top_processes.sh
UserParameter=system.login.failed,/etc/zabbix/scripts/login_monitoring.sh failed_logins
UserParameter=system.login.successful,/etc/zabbix/scripts/login_monitoring.sh successful_logins
UserParameter=system.login.last10,/etc/zabbix/scripts/login_monitoring.sh last10
EOF
fi

# Set proper permissions on configuration files
chown zabbix:zabbix /etc/zabbix/zabbix_agent2.conf
chmod 640 /etc/zabbix/zabbix_agent2.conf
chown zabbix:zabbix /etc/zabbix/zabbix_agent2.d/userparameters.conf
chmod 640 /etc/zabbix/zabbix_agent2.d/userparameters.conf

# Configure sudo permissions for Zabbix user
echo "Configuring sudo permissions..." | tee -a "$LOG_FILE"
cat > /etc/sudoers.d/zabbix << EOF
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee, /usr/bin/top
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix || { echo "Failed to set sudo permissions" >&2; exit 1; }

# Set proper permissions on directories
echo "Setting directory permissions..." | tee -a "$LOG_FILE"
chown -R zabbix:zabbix /var/log/zabbix
chmod 755 /var/log/zabbix
chown -R zabbix:zabbix /var/run/zabbix
chmod 755 /var/run/zabbix
chown -R zabbix:zabbix /etc/zabbix/scripts
chmod 755 /etc/zabbix/scripts

# Test configuration before starting service
echo "Testing configuration..." | tee -a "$LOG_FILE"
if ! sudo -u zabbix zabbix_agent2 -t /etc/zabbix/zabbix_agent2.conf; then
    echo "Configuration test failed. Please check the configuration file." | tee -a "$LOG_FILE"
    exit 1
fi

# Restart Zabbix agent
echo "Restarting Zabbix agent..." | tee -a "$LOG_FILE"
systemctl daemon-reload
systemctl stop zabbix-agent2 2>/dev/null
sleep 2
systemctl start zabbix-agent2 || { 
    echo "Failed to start zabbix-agent2, checking logs..." | tee -a "$LOG_FILE"
    journalctl -u zabbix-agent2 --no-pager -n 50 | tee -a "$LOG_FILE"
    exit 1
}
systemctl enable zabbix-agent2 || { echo "Failed to enable zabbix-agent2" >&2; exit 1; }

# Verify installation
if systemctl is-active --quiet zabbix-agent2; then
    echo "Installation completed successfully!" | tee -a "$LOG_FILE"
    echo
    echo "Zabbix Agent has been installed and configured successfully!"
    echo "Configuration file: /etc/zabbix/zabbix_agent2.conf"
    echo "Log file: $LOG_FILE"
    echo "Monitoring scripts are installed in: /etc/zabbix/scripts/"
    echo
    echo "To test a UserParameter: zabbix_get -s 127.0.0.1 -k \"parameter_name\""
else
    echo "Installation completed with warnings. Zabbix agent service may not be running correctly." | tee -a "$LOG_FILE"
    echo "Please check the log file for details: $LOG_FILE"
    echo "Try running: systemctl status zabbix-agent2"
    echo "Check logs with: journalctl -u zabbix-agent2"
    exit 1
fi