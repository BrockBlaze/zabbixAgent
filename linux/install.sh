#!/bin/bash

# Setting Variables
REPO_URL="https://github.com/BrockBlaze/zabbixAgent.git"
USERNAME=$(logname)
START_DIR="/home/$USERNAME/zabbixAgent"
SOURCE_DIR="/zabbixAgent"
TARGET_DIR="/zabbixAgent/linux/scripts"
SCRIPTS_DIR="/etc/zabbix/"
LOG_FILE="/var/log/zabbix/install.log"
VERSION="1.1.0"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create log directory
mkdir -p "$(dirname $LOG_FILE)"
log "Starting Zabbix Agent installation (Version $VERSION)..."

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

# Check for environment variables first
use_env_vars=0
if [ -n "$ZABBIX_SERVER_IP" ] && [ -n "$HOSTNAME" ]; then
    use_env_vars=1
    echo "Using environment variables for configuration:"
    echo "Zabbix Server IP: $ZABBIX_SERVER_IP"
    echo "Hostname: $HOSTNAME"
    
    # Validate IP from environment variable
    if ! validate_ip "$ZABBIX_SERVER_IP"; then
        error "Invalid IP address format in ZABBIX_SERVER_IP environment variable. Please use a valid IPv4 address."
    fi
fi

# Improved function to get Zabbix server IP with better input handling
get_valid_ip() {
    # Try to automatically detect the server IP
    local default_ip=""
    if command_exists hostname; then
        default_ip=$(hostname -I | awk '{print $1}')
    fi
    
    while true; do
        # Make the prompt very visible
        echo ""
        echo "=============================================="
        echo "WAITING FOR INPUT: Zabbix Server IP Address"
        echo "=============================================="
        echo "Enter Zabbix Server IP (or press Enter for $default_ip, or type 'exit' to quit): "
        # Force flush the output buffer to ensure prompt is displayed
        stty -icanon
        read -e ip_address  # -e enables readline for line editing (allows backspace)
        stty icanon
        echo "You entered: \"$ip_address\""
        
        # Check if user wants to exit
        if [[ "$ip_address" == "exit" ]]; then
            echo "Installation canceled by user."
            exit 0
        fi
        
        # Use default if empty
        if [ -z "$ip_address" ] && [ -n "$default_ip" ]; then
            ip_address="$default_ip"
            echo "Using default IP: $ip_address"
        fi
        
        # Validate IP
        if validate_ip "$ip_address"; then
            echo "IP address $ip_address is valid."
            break
        else
            echo "Invalid IP address format. Please enter a valid IPv4 address."
        fi
    done
    
    echo "$ip_address"
}

# Improved function to get hostname with better input handling
get_valid_hostname() {
    # Try to get the current hostname as default
    local default_hostname=""
    if command_exists hostname; then
        default_hostname=$(hostname)
    fi
    
    while true; do
        # Make the prompt very visible
        echo ""
        echo "=============================================="
        echo "WAITING FOR INPUT: Hostname for this server"
        echo "=============================================="
        echo "Enter Hostname for this server (or press Enter for $default_hostname, or type 'exit' to quit): "
        # Force flush the output buffer to ensure prompt is displayed
        stty -icanon
        read -e hostname  # -e enables readline for line editing
        stty icanon
        echo "You entered: \"$hostname\""
        
        # Check if user wants to exit
        if [[ "$hostname" == "exit" ]]; then
            echo "Installation canceled by user."
            exit 0
        fi
        
        # Use default if empty
        if [ -z "$hostname" ] && [ -n "$default_hostname" ]; then
            hostname="$default_hostname"
            echo "Using default hostname: $hostname"
            break
        elif [ -n "$hostname" ]; then
            echo "Using hostname: $hostname"
            break
        else
            echo "Hostname cannot be empty. Please enter a valid hostname."
        fi
    done
    
    echo "$hostname"
}

# Ask for the Zabbix server IP and hostname with improved validation
echo "Starting Zabbix agent configuration..."

# Use environment variables if available, otherwise prompt for input
if [ $use_env_vars -eq 1 ]; then
    # Variables are already set from environment
    echo "Using pre-configured values:"
    echo "Zabbix Server IP: $ZABBIX_SERVER_IP"
    echo "Hostname: $HOSTNAME"
else
    ZABBIX_SERVER_IP=$(get_valid_ip)
    HOSTNAME=$(get_valid_hostname)
fi

if [ -z "$ZABBIX_SERVER_IP" ] || [ -z "$HOSTNAME" ]; then
    error "Zabbix Server IP and Hostname are required"
fi

# Confirmation before proceeding
if [ $use_env_vars -eq 0 ]; then
    echo "You have entered:"
    echo "Zabbix Server IP: $ZABBIX_SERVER_IP"
    echo "Hostname: $HOSTNAME"
    echo ""
    read -p "Is this correct? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Let's try again..."
        ZABBIX_SERVER_IP=$(get_valid_ip)
        HOSTNAME=$(get_valid_hostname)
        echo "You have entered:"
        echo "Zabbix Server IP: $ZABBIX_SERVER_IP"
        echo "Hostname: $HOSTNAME"
        read -p "Is this correct? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Installation aborted by user"
            exit 0
        fi
    fi
fi

# Check if Zabbix agent is already installed
log "Checking for existing Zabbix agent installation..."
if command_exists zabbix_agentd; then
    log "Zabbix agent is already installed. Checking version..."
    CURRENT_VERSION=$(zabbix_agentd -V | head -n 1 | awk '{print $3}')
    log "Current Zabbix agent version: $CURRENT_VERSION"
    
    # Ask user if they want to reinstall
    read -p "Zabbix agent is already installed. Do you want to reinstall? (y/N): " REINSTALL
    if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
        log "Installation aborted by user"
        exit 0
    fi
    log "Proceeding with reinstallation..."
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
yes | sensors-detect || warning "Warning: sensors-detect may not have completed successfully"

# Clone the repository
log "Cloning repository..."
if [ -d "$SOURCE_DIR" ]; then
    log "Source directory already exists, removing it first..."
    rm -rf "$SOURCE_DIR"
fi

git clone "$REPO_URL" "$SOURCE_DIR" || error "Failed to clone repository"

# Ensuring the target directory exists
log "Ensuring the target directory exists..."
mkdir -p "$SCRIPTS_DIR" || error "Failed to create the target directory"

# Create scripts directory if it doesn't exist
log "Creating scripts directory..."
mkdir -p "${SCRIPTS_DIR}scripts" || error "Failed to create the scripts directory"

# Moving scripts to the target directory
log "Moving scripts to the target directory..."
if [ -d "$SOURCE_DIR/linux/scripts" ]; then
    cp -r "$SOURCE_DIR"/linux/scripts/*.sh "${SCRIPTS_DIR}scripts/" || error "Failed to move scripts"
else
    error "Could not find scripts directory in the repository"
fi

# Setting permissions
log "Setting permissions..."
chmod +x "${SCRIPTS_DIR}scripts"/*.sh || error "Failed to set permissions"

# Create dedicated log directory with proper permissions
log "Creating log directory with proper permissions..."
mkdir -p /var/log/zabbix || error "Failed to create log directory"
chown -R zabbix:zabbix /var/log/zabbix || error "Failed to set permissions on log directory"

# Configure sudo permissions for the zabbix user
log "Configuring sudo permissions for Zabbix user..."
# Create a sudoers file for zabbix
cat > /etc/sudoers.d/zabbix << EOF
# Allow zabbix user to access system logs and run specific commands without password
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /bin/mkdir, /bin/chown, /bin/chmod, /usr/bin/tee, /usr/bin/top
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix || error "Failed to set permissions on sudoers file"

# Backup the original configuration file
log "Backing up original configuration..."
if [ -f /etc/zabbix/zabbix_agentd.conf ]; then
    BACKUP_TIME=$(date +"%Y%m%d%H%M%S")
    cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup.$BACKUP_TIME || error "Failed to backup configuration"
    log "Original configuration backed up to /etc/zabbix/zabbix_agentd.conf.backup.$BACKUP_TIME"
fi

# Modify the zabbix_agentd.conf file
log "Configuring Zabbix agent..."

# Replace placeholders with actual values
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf || error "Failed to set Server IP"
log "Set Server IP to $ZABBIX_SERVER_IP"

sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf || log "Note: ServerActive not set (line might not exist)"
log "Set ServerActive to $ZABBIX_SERVER_IP"

sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agentd.conf || error "Failed to set Hostname"
log "Set Hostname to $HOSTNAME"

# Remove any existing custom UserParameters
log "Removing any existing custom UserParameters..."
sed -i '/^UserParameter=/d' /etc/zabbix/zabbix_agentd.conf

# Add custom UserParameters with extremely simple format
log "Adding extremely simplified UserParameters for maximum compatibility..."

# Minimal format: basic key name, simple command, no quotation marks
# Test a few basic parameters first
echo "UserParameter=cputemp,/etc/zabbix/scripts/cpu_temp.sh" >> /etc/zabbix/zabbix_agentd.conf
log "Added CPU temperature monitoring with simplified key"

echo "UserParameter=topproc,/etc/zabbix/scripts/top_processes.sh" >> /etc/zabbix/zabbix_agentd.conf
log "Added top processes monitoring with simplified key"

# Add some ultra-simple built-in commands
echo "UserParameter=cpuload,cat /proc/loadavg | cut -d' ' -f1" >> /etc/zabbix/zabbix_agentd.conf
log "Added CPU load monitoring with simplified key"

echo "UserParameter=ramfree,free -m | grep Mem | awk '{print \$4}'" >> /etc/zabbix/zabbix_agentd.conf
log "Added free memory monitoring with simplified key"

echo "UserParameter=diskfree,df -h / | grep -v Filesystem | awk '{print \$4}'" >> /etc/zabbix/zabbix_agentd.conf
log "Added free disk space monitoring with simplified key"

# Test scripts directly to ensure they work
log "Testing scripts directly..."

# Test top_processes.sh script
log "Testing top_processes.sh script directly..."
sudo -u zabbix "${SCRIPTS_DIR}scripts/top_processes.sh" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log "top_processes.sh script failed when executed directly, trying to fix..."
    
    # Check for shebang line
    if ! grep -q "^#!/bin/bash" "${SCRIPTS_DIR}scripts/top_processes.sh"; then
        log "Adding missing shebang line to top_processes.sh"
        sed -i '1i#!/bin/bash' "${SCRIPTS_DIR}scripts/top_processes.sh"
    fi
    
    # Make script executable
    chmod +x "${SCRIPTS_DIR}scripts/top_processes.sh"
    
    # Test again
    sudo -u zabbix "${SCRIPTS_DIR}scripts/top_processes.sh" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        warning "top_processes.sh script still fails when executed directly. Some UserParameters may not work."
    else
        log "top_processes.sh script now executes successfully"
    fi
else
    log "top_processes.sh script executes successfully"
fi

# Test other scripts
for script in cpu_temp.sh login_monitoring.sh; do
    if [ -f "${SCRIPTS_DIR}scripts/$script" ]; then
        log "Testing $script directly..."
        sudo -u zabbix "${SCRIPTS_DIR}scripts/$script" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            log "$script failed when executed directly, trying to fix..."
            
            # Check for shebang line
            if ! grep -q "^#!/bin/bash" "${SCRIPTS_DIR}scripts/$script"; then
                log "Adding missing shebang line to $script"
                sed -i '1i#!/bin/bash' "${SCRIPTS_DIR}scripts/$script"
            fi
            
            # Make script executable
            chmod +x "${SCRIPTS_DIR}scripts/$script"
        else
            log "$script executes successfully"
        fi
    fi
done

# Validate configuration with custom error detection
log "Validating configuration..."
validation_output=$(zabbix_agentd -t /etc/zabbix/zabbix_agentd.conf 2>&1)
validation_status=$?

# Check for errors in the validation output
if [[ $validation_status -ne 0 ]] || echo "$validation_output" | grep -q "ZBX_NOTSUPPORTED\|invalid\|failed\|error"; then
    log "Configuration validation errors detected:"
    log "$validation_output"
    
    # Find which parameters are causing issues
    log "Identifying problematic parameters with simplified approach..."
    
    # Try just one parameter to ensure at least something works
    sed -i '/^UserParameter=/d' /etc/zabbix/zabbix_agentd.conf
    echo "UserParameter=topproc,/etc/zabbix/scripts/top_processes.sh" >> /etc/zabbix/zabbix_agentd.conf
    
    # Test if it works
    validation_output=$(zabbix_agentd -t /etc/zabbix/zabbix_agentd.conf 2>&1)
    if echo "$validation_output" | grep -q "ZBX_NOTSUPPORTED\|invalid\|failed\|error"; then
        log "Simplified parameter still has validation issues. Using most basic format."
        sed -i '/^UserParameter=/d' /etc/zabbix/zabbix_agentd.conf
        echo "UserParameter=proclist,ps aux" >> /etc/zabbix/zabbix_agentd.conf
    else
        log "Parameter 'topproc' is valid, keeping it"
        # Try adding one more
        echo "UserParameter=cputemp,/etc/zabbix/scripts/cpu_temp.sh" >> /etc/zabbix/zabbix_agentd.conf
    fi
else
    log "Configuration validation successful"
fi

# Restart the Zabbix agent service
log "Restarting Zabbix agent..."
systemctl stop zabbix-agent
sleep 2  # Give it time to fully stop
systemctl start zabbix-agent || {
    warning "Failed to restart Zabbix agent, trying one more time with debug..."
    systemctl status zabbix-agent >> "$LOG_FILE" 2>&1
    journalctl -u zabbix-agent --no-pager -n 50 >> "$LOG_FILE" 2>&1
    
    # Try one more time with absolute minimal config
    log "Trying with absolute minimal configuration..."
    sed -i '/^UserParameter=/d' /etc/zabbix/zabbix_agentd.conf
    echo "UserParameter=uptime,uptime" >> /etc/zabbix/zabbix_agentd.conf
    systemctl restart zabbix-agent || error "Failed to restart Zabbix agent after multiple attempts"
}

# Enable the Zabbix agent service
log "Enabling Zabbix agent service..."
systemctl enable zabbix-agent || warning "Failed to enable Zabbix agent, you may need to enable it manually"

# Verify service status with more detailed error reporting
log "Verifying service status..."
if ! systemctl is-active --quiet zabbix-agent; then
    systemctl status zabbix-agent >> "$LOG_FILE" 2>&1
    journalctl -u zabbix-agent --no-pager -n 50 >> "$LOG_FILE" 2>&1
    warning "Zabbix agent service is not running. Check the logs for details."
    warning "You may need to manually fix the configuration and restart the service."
else
    log "Zabbix agent service is running correctly"
fi

# Create a help file with information about the UserParameters
log "Creating help documentation for UserParameters..."
cat > /etc/zabbix/zabbix_userparameters.txt << EOF
Zabbix Agent Custom UserParameters
=================================

The following custom UserParameters provide clean, simple output:

CPU Temperature:
- Key: cputemp
- Command: /etc/zabbix/scripts/cpu_temp.sh
- Description: Returns CPU temperature in Celsius as a plain number

CPU Load:
- Key: cpuload
- Command: cat /proc/loadavg | cut -d' ' -f1
- Description: Returns the 1-minute CPU load average

Free Memory:
- Key: ramfree
- Command: free -m | grep Mem | awk '{print \$4}'
- Description: Returns free memory in MB

Free Disk Space:
- Key: diskfree
- Command: df -h / | grep -v Filesystem | awk '{print \$4}'
- Description: Returns free disk space on the root partition

Top Processes:
- Key: topproc
- Command: /etc/zabbix/scripts/top_processes.sh
- Description: Returns top 10 processes by CPU usage in a clean tabular format

Testing UserParameters:
To test if a UserParameter is working, use:
  zabbix_get -s 127.0.0.1 -k "parameter_name"

Example:
  zabbix_get -s 127.0.0.1 -k "topproc"
  zabbix_get -s 127.0.0.1 -k "cputemp"

Note: This agent has been configured with ultra-simple parameter names for
maximum compatibility with all Zabbix agent versions.
EOF

log "UserParameters documentation created at /etc/zabbix/zabbix_userparameters.txt"

# Verify connection to Zabbix server
log "Verifying connection to Zabbix server..."
if command_exists nc; then
    if nc -z -w5 "$ZABBIX_SERVER_IP" 10050 >/dev/null 2>&1; then
        log "Successfully connected to Zabbix server at $ZABBIX_SERVER_IP:10050"
    else
        warning "Could not connect to Zabbix server at $ZABBIX_SERVER_IP:10050"
    fi
else
    log "nc command not available, skipping server connection check"
fi

# Clean up
log "Cleaning up..."
rm -rf "$SOURCE_DIR" || warning "Warning: Failed to remove source directory"
if [ -d "$START_DIR" ]; then
    rm -rf "$START_DIR" || warning "Warning: Failed to remove start directory"
fi

# Final status check
if systemctl is-active --quiet zabbix-agent; then
    log "Installation completed successfully!"
    echo
    echo "Zabbix Agent has been installed and configured successfully!"
    echo "Configuration file: /etc/zabbix/zabbix_agentd.conf"
    echo "Log file: $LOG_FILE"
    echo "Monitoring scripts are installed in: ${SCRIPTS_DIR}scripts/"
    echo "UserParameters documentation: /etc/zabbix/zabbix_userparameters.txt"
    echo
    # List the enabled UserParameters
    echo "Enabled UserParameters (all with clean, simple output):"
    grep "^UserParameter=" /etc/zabbix/zabbix_agentd.conf | sed 's/UserParameter=/- /'
    echo
    echo "To test a UserParameter: zabbix_get -s 127.0.0.1 -k \"parameter_name\""
    echo "To uninstall, run: ./uninstall.sh"
else
    log "Installation completed with warnings. Zabbix agent service may not be running correctly."
    echo
    echo "Zabbix Agent has been installed but the service may not be running correctly."
    echo "Please check the log file for details: $LOG_FILE"
    echo "You may need to manually fix the configuration and restart the service."
    echo
    echo "Common issues:"
    echo "1. Invalid UserParameter syntax"
    echo "2. Scripts not executable"
    echo "3. Missing dependencies"
    echo
    echo "To troubleshoot:"
    echo "- Check /var/log/zabbix/zabbix_agentd.log"
    echo "- Run: systemctl status zabbix-agent"
    echo "- Test parameters: zabbix_agentd -t /etc/zabbix/zabbix_agentd.conf"
fi