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

# Get the top 10 processes by CPU usage
get_top_processes() {
    # Use top in batch mode to get process info
    # -b: batch mode
    # -n1: one iteration only
    # -o %CPU: sort by CPU usage
    processes=$(top -b -n1 -o %CPU | head -n 17 | tail -n 10)
    
    # Format output as JSON
    local result="["
    local first=true
    
    while read -r line; do
        # Extract PID, user, CPU, memory, command
        pid=$(echo "$line" | awk '{print $1}')
        user=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $9}')
        mem=$(echo "$line" | awk '{print $10}')
        # Get command (fields 12 and beyond)
        cmd=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=$9=$10=$11=""; print $0}' | sed 's/^ *//')
        
        # Truncate command if too long
        if [ ${#cmd} -gt 50 ]; then
            cmd="${cmd:0:47}..."
        fi
        
        # Escape JSON special characters
        cmd=$(echo "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
        
        # Add comma if not the first item
        if [ "$first" = true ]; then
            first=false
        else
            result="$result,"
        fi
        
        # Add this process to the JSON array
        result="$result{\"pid\":$pid,\"user\":\"$user\",\"cpu\":$cpu,\"memory\":$mem,\"command\":\"$cmd\"}"
    done <<< "$processes"
    
    result="$result]"
    echo "$result"
}

# Log that we're collecting information
log "Collecting top processes information"

# Format the output as JSON with timestamp
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
processes=$(get_top_processes)

echo "{
    \"timestamp\": \"$timestamp\",
    \"processes\": $processes
}" 