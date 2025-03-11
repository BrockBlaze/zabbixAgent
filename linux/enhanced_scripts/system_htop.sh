#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    # Try to write to log file, but don't fail if we can't
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true

# Format the output as JSON for Zabbix
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Get process information without using sudo (ps doesn't need sudo)
ps_output=$(ps aux --sort=-%cpu | head -n 11 2>/dev/null || echo "Failed to get process list")

# Extract just the process names and CPU usage into JSON format
process_json="["
IFS=$'\n'
process_count=0
for line in $(echo "$ps_output" | tail -n +2); do
    if [ $process_count -lt 10 ]; then
        name=$(echo "$line" | awk '{print $11}' | sed 's/"/\\"/g')
        cpu=$(echo "$line" | awk '{print $3}')
        
        if [ $process_count -gt 0 ]; then
            process_json+=","
        fi
        
        process_json+="{\"name\":\"$name\",\"cpu\":$cpu}"
        process_count=$((process_count+1))
    else
        break
    fi
done
process_json+="]"

# Output only the processes in simple JSON
echo "{
    \"top_processes\": $process_json
}" 