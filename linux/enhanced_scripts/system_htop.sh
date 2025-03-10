#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    # Try to write to log file, but don't fail if we can't
    # Redirect to /dev/null to prevent output to stdout
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true

# Check if htop is installed
if ! command -v htop &> /dev/null; then
    log "htop not installed, trying to install it"
    # Try to install htop
    sudo apt-get update > /dev/null 2>&1
    sudo apt-get install -y htop > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "Failed to install htop"
        echo "ERROR: htop not installed and failed to install it"
        exit 1
    fi
fi

# Capture htop output in batch mode (non-interactive)
# We'll capture the first 20 processes
htop_output=$(sudo htop -d 1 -n 1 -C --delay=0 2>&1 | head -n 25)

# Format the output as JSON for Zabbix
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Replace special characters to make it valid JSON
htop_json=$(echo "$htop_output" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\n/\\n/g' | tr '\n' ' ' | sed 's/\t/    /g')

# Output the JSON
echo "{"
echo "    \"timestamp\": \"$current_time\","
echo "    \"htop_output\": \"$htop_json\""
echo "}" 