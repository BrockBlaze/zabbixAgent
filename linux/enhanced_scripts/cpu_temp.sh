#!/bin/bash

# Configuration
MAX_RETRIES=3
SLEEP_BETWEEN_RETRIES=2
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_cpu_temp() {
    local sensors_output
    local cpu_temp
    
    # Try different temperature sources
    for source in "Tctl" "Core 0" "CPU" "Package id 0"; do
        sensors_output=$(sensors 2>/dev/null)
        cpu_temp=$(echo "$sensors_output" | grep -i "$source" | awk '{print $2}' | tr -d '+°C')
        
        if [[ -n "$cpu_temp" ]]; then
            log "Temperature found from source: $source"
            echo "$cpu_temp"
            return 0
        fi
    done
    
    return 1
}

# Ensure log directory exists
mkdir -p "$(dirname $LOG_FILE)"

# Main logic with retries
for ((i=1; i<=MAX_RETRIES; i++)); do
    if temp=$(get_cpu_temp); then
        echo "$temp"
        exit 0
    fi
    
    log "Attempt $i failed to get CPU temperature"
    
    if [ $i -lt $MAX_RETRIES ]; then
        log "Waiting $SLEEP_BETWEEN_RETRIES seconds before retry"
        sleep $SLEEP_BETWEEN_RETRIES
    fi
done

log "Error: Could not retrieve CPU temperature after $MAX_RETRIES attempts"
echo "Error: Could not retrieve CPU temperature after $MAX_RETRIES attempts"
exit 1 