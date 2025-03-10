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
# Using more compatible parameters
htop_output=$(sudo htop -C -d 1 --delay=0 -b 2>&1 | head -n 25)

# If batch mode fails, try just piping the output (more compatible approach)
if [[ $? -ne 0 ]]; then
    log "Htop failed with specific parameters, trying simpler approach"
    # Fall back to ps command which is more reliable
    htop_output=$(sudo ps aux --sort=-%cpu | head -n 20)
fi

# Format the output as JSON for Zabbix
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Replace special characters to make it valid JSON
htop_json=$(echo "$htop_output" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\n/\\n/g' | tr '\n' ' ' | sed 's/\t/    /g')

# Output the JSON
echo "{"
echo "    \"timestamp\": \"$current_time\","
echo "    \"htop_output\": \"$htop_json\""
echo "}" 