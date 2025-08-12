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
echo "Enter Zabbix Server IP [default: 192.168.70.2]: "
read ZABBIX_SERVER_IP
if [ -z "$ZABBIX_SERVER_IP" ]; then
    ZABBIX_SERVER_IP="192.168.70.2"
fi

# Get hostname
echo "Enter Hostname for this server [default: $(hostname)]: "
read HOSTNAME
if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

# Determine Ubuntu version for Zabbix repo
UBUNTU_VERSION=$(lsb_release -rs)
case "$UBUNTU_VERSION" in
    "24.04")
        ZABBIX_REPO_VERSION="22.04"
        ZABBIX_VERSION="7.0"
        ;;
    "22.04")
        ZABBIX_REPO_VERSION="22.04"
        ZABBIX_VERSION="6.0"
        ;;
    "20.04")
        ZABBIX_REPO_VERSION="20.04"
        ZABBIX_VERSION="6.0"
        ;;
    *)
        echo "WARNING: Unsupported Ubuntu version $UBUNTU_VERSION, attempting with 6.0" | tee -a "$LOG_FILE"
        ZABBIX_REPO_VERSION="$UBUNTU_VERSION"
        ZABBIX_VERSION="6.0"
        ;;
esac

# Add Zabbix repository
echo "Adding Zabbix repository version $ZABBIX_VERSION for Ubuntu $ZABBIX_REPO_VERSION..." | tee -a "$LOG_FILE"

# Clean up any previous repository files
rm -f /tmp/zabbix-release*.deb 2>/dev/null

# Determine correct repository package version
if [ "$ZABBIX_VERSION" = "7.0" ]; then
    REPO_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu${ZABBIX_REPO_VERSION}_all.deb"
else
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${ZABBIX_REPO_VERSION}_all.deb"
fi

echo "Downloading from: $REPO_URL" | tee -a "$LOG_FILE"
wget -O /tmp/zabbix-release.deb "$REPO_URL" || { echo "Failed to download Zabbix repository package" >&2; exit 1; }
dpkg -i /tmp/zabbix-release.deb || { echo "Failed to install Zabbix repository" >&2; exit 1; }
rm -f /tmp/zabbix-release.deb || echo "Warning: Failed to remove repository package" | tee -a "$LOG_FILE"

# Update package list
echo "Updating package list..." | tee -a "$LOG_FILE"
apt update || { echo "Failed to update package list" >&2; exit 1; }

# Install required packages
echo "Installing required packages..." | tee -a "$LOG_FILE"

# Check Ubuntu version and handle dependencies accordingly
case "$(lsb_release -rs)" in
    "24.04")
        echo "Detected Ubuntu 24.04, installing required dependencies..." | tee -a "$LOG_FILE"
        # Install required dependencies for Ubuntu 24.04
        apt install -y libldap2-dev libssl-dev || { echo "Failed to install required development packages" >&2; exit 1; }
        
        # Create symbolic link for libldap if needed
        if [ ! -f /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0 ]; then
            echo "Creating symbolic link for libldap compatibility..." | tee -a "$LOG_FILE"
            ln -sf /usr/lib/x86_64-linux-gnu/libldap-2.6.so.0 /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0 || echo "Warning: Could not create libldap symlink" | tee -a "$LOG_FILE"
        fi
        ;;
    "22.04")
        echo "Detected Ubuntu 22.04, checking dependencies..." | tee -a "$LOG_FILE"
        # Ubuntu 22.04 usually has compatible libraries
        ;;
    "20.04")
        echo "Detected Ubuntu 20.04, checking dependencies..." | tee -a "$LOG_FILE"
        # Install any specific dependencies for 20.04 if needed
        apt install -y libssl1.1 2>/dev/null || echo "Note: libssl1.1 may not be needed" | tee -a "$LOG_FILE"
        ;;
esac

# Install Zabbix agent and other required packages
echo "Installing Zabbix agent2 and dependencies..." | tee -a "$LOG_FILE"
if ! apt install -y zabbix-agent2 lm-sensors smartmontools nvme-cli; then
    echo "Failed to install zabbix-agent2, trying fallback to zabbix-agent..." | tee -a "$LOG_FILE"
    apt install -y zabbix-agent lm-sensors smartmontools nvme-cli || { echo "Failed to install Zabbix agent packages" >&2; exit 1; }
    AGENT_TYPE="zabbix-agent"
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
else
    AGENT_TYPE="zabbix-agent2"
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
fi
echo "Installed: $AGENT_TYPE" | tee -a "$LOG_FILE"

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
if [ ! -f "$AGENT_CONFIG" ]; then
    cat > "$AGENT_CONFIG" << EOF
Server=$ZABBIX_SERVER_IP
ServerActive=$ZABBIX_SERVER_IP
Hostname=$HOSTNAME
PidFile=/var/run/zabbix/zabbix_agent2.pid
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=0
EnableRemoteCommands=1
LogRemoteCommands=1
Timeout=30

# Custom script parameters
UserParameter=system.temperature,/etc/zabbix/scripts/cpu_temp.sh
UserParameter=system.processes,/etc/zabbix/scripts/top_processes.sh
UserParameter=system.login.failed,/etc/zabbix/scripts/login_monitoring.sh failed_logins
UserParameter=system.login.successful,/etc/zabbix/scripts/login_monitoring.sh successful_logins
UserParameter=system.login.last10,/etc/zabbix/scripts/login_monitoring.sh last10

# Disk temperature monitoring
UserParameter=disk.temperature[*],/etc/zabbix/scripts/disk_temp.sh $1
UserParameter=disk.temperature.discovery,/etc/zabbix/scripts/disk_temp.sh discover
UserParameter=disk.temperature.all,/etc/zabbix/scripts/disk_temp.sh all
UserParameter=disk.temperature.average,/etc/zabbix/scripts/disk_temp.sh average
UserParameter=disk.temperature.max,/etc/zabbix/scripts/disk_temp.sh max

# Disk health monitoring
UserParameter=disk.health[*],/etc/zabbix/scripts/disk_health.sh health $1
UserParameter=disk.wear[*],/etc/zabbix/scripts/disk_health.sh wear $1
UserParameter=disk.reallocated[*],/etc/zabbix/scripts/disk_health.sh reallocated $1
UserParameter=disk.pending[*],/etc/zabbix/scripts/disk_health.sh pending $1
UserParameter=disk.power_hours[*],/etc/zabbix/scripts/disk_health.sh hours $1
UserParameter=disk.info[*],/etc/zabbix/scripts/disk_health.sh info $1
UserParameter=disk.stats[*],/etc/zabbix/scripts/disk_health.sh json $1
EOF
else
    # Only update specific lines if they exist, otherwise append them
    if ! grep -q "^Server=" "$AGENT_CONFIG"; then
        echo "Server=$ZABBIX_SERVER_IP" >> "$AGENT_CONFIG"
    else
        sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" "$AGENT_CONFIG"
    fi

    if ! grep -q "^ServerActive=" "$AGENT_CONFIG"; then
        echo "ServerActive=$ZABBIX_SERVER_IP" >> "$AGENT_CONFIG"
    else
        sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/" "$AGENT_CONFIG"
    fi

    if ! grep -q "^Hostname=" "$AGENT_CONFIG"; then
        echo "Hostname=$HOSTNAME" >> "$AGENT_CONFIG"
    else
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" "$AGENT_CONFIG"
    fi

    # Add UserParameters if they don't exist
    if ! grep -q "^UserParameter=system.temperature" "$AGENT_CONFIG"; then
        echo -e "\n# Custom script parameters" >> "$AGENT_CONFIG"
        echo "UserParameter=system.temperature,/etc/zabbix/scripts/cpu_temp.sh" >> "$AGENT_CONFIG"
        echo "UserParameter=system.processes,/etc/zabbix/scripts/top_processes.sh" >> "$AGENT_CONFIG"
        echo "UserParameter=system.login.failed,/etc/zabbix/scripts/login_monitoring.sh failed_logins" >> "$AGENT_CONFIG"
        echo "UserParameter=system.login.successful,/etc/zabbix/scripts/login_monitoring.sh successful_logins" >> "$AGENT_CONFIG"
        echo "UserParameter=system.login.last10,/etc/zabbix/scripts/login_monitoring.sh last10" >> "$AGENT_CONFIG"
        echo "" >> "$AGENT_CONFIG"
        echo "# Disk temperature monitoring" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.temperature[*],/etc/zabbix/scripts/disk_temp.sh \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.temperature.discovery,/etc/zabbix/scripts/disk_temp.sh discover" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.temperature.all,/etc/zabbix/scripts/disk_temp.sh all" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.temperature.average,/etc/zabbix/scripts/disk_temp.sh average" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.temperature.max,/etc/zabbix/scripts/disk_temp.sh max" >> "$AGENT_CONFIG"
        echo "" >> "$AGENT_CONFIG"
        echo "# Disk health monitoring" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.health[*],/etc/zabbix/scripts/disk_health.sh health \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.wear[*],/etc/zabbix/scripts/disk_health.sh wear \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.reallocated[*],/etc/zabbix/scripts/disk_health.sh reallocated \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.pending[*],/etc/zabbix/scripts/disk_health.sh pending \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.power_hours[*],/etc/zabbix/scripts/disk_health.sh hours \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.info[*],/etc/zabbix/scripts/disk_health.sh info \$1" >> "$AGENT_CONFIG"
        echo "UserParameter=disk.stats[*],/etc/zabbix/scripts/disk_health.sh json \$1" >> "$AGENT_CONFIG"
    fi
fi

# Set proper permissions on configuration files
chown zabbix:zabbix "$AGENT_CONFIG"
chmod 640 "$AGENT_CONFIG"

# Configure sudo permissions for Zabbix user
echo "Configuring sudo permissions..." | tee -a "$LOG_FILE"
cat > /etc/sudoers.d/zabbix << EOF
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee, /usr/bin/top, /usr/sbin/smartctl, /usr/sbin/nvme
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
if [ "$AGENT_TYPE" = "zabbix-agent2" ]; then
    if ! zabbix_agent2 -c "$AGENT_CONFIG" -t "agent.ping" 2>/dev/null | grep -q "\[1\]"; then
        echo "Warning: Configuration test had issues, but continuing..." | tee -a "$LOG_FILE"
    else
        echo "Configuration test passed" | tee -a "$LOG_FILE"
    fi
else
    if ! zabbix_agentd -c "$AGENT_CONFIG" -t "agent.ping" 2>/dev/null | grep -q "\[1\]"; then
        echo "Warning: Configuration test had issues, but continuing..." | tee -a "$LOG_FILE"
    else
        echo "Configuration test passed" | tee -a "$LOG_FILE"
    fi
fi

# Restart Zabbix agent
echo "Restarting Zabbix agent service: $AGENT_SERVICE..." | tee -a "$LOG_FILE"
systemctl daemon-reload
systemctl stop "$AGENT_SERVICE" 2>/dev/null
sleep 2
systemctl start "$AGENT_SERVICE" || { 
    echo "Failed to start $AGENT_SERVICE, checking logs..." | tee -a "$LOG_FILE"
    journalctl -u "$AGENT_SERVICE" --no-pager -n 50 | tee -a "$LOG_FILE"
    exit 1
}
systemctl enable "$AGENT_SERVICE" || { echo "Failed to enable $AGENT_SERVICE" >&2; exit 1; }

# Verify installation
if systemctl is-active --quiet "$AGENT_SERVICE"; then
    echo "Installation completed successfully!" | tee -a "$LOG_FILE"
    echo
    echo "========================================"
    echo "Zabbix Agent Installation Summary:"
    echo "========================================"
    echo "Agent Type: $AGENT_TYPE"
    echo "Ubuntu Version: $UBUNTU_VERSION"
    echo "Zabbix Version: $ZABBIX_VERSION"
    echo "Configuration file: $AGENT_CONFIG"
    echo "Log file: $LOG_FILE"
    echo "Server IP: $ZABBIX_SERVER_IP"
    echo "Hostname: $HOSTNAME"
    echo "Monitoring scripts: /etc/zabbix/scripts/"
    echo "========================================"
    echo
    echo "To test a UserParameter: zabbix_get -s 127.0.0.1 -k \"parameter_name\""
    echo "To check agent status: systemctl status $AGENT_SERVICE"
else
    echo "Installation completed with warnings. Zabbix agent service may not be running correctly." | tee -a "$LOG_FILE"
    echo "Please check the log file for details: $LOG_FILE"
    echo "Try running: systemctl status $AGENT_SERVICE"
    echo "Check logs with: journalctl -u $AGENT_SERVICE"
    exit 1
fi