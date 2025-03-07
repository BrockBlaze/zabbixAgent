#!/bin/bash

# Configuration
MAX_RETRIES=3
SLEEP_BETWEEN_RETRIES=2
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    # Try to write to log file, but don't fail if we can't
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" 2>/dev/null || true
}

get_cpu_temp() {
    local sensors_output
    local cpu_temp
    
    # Try different temperature sources
    for source in "Tctl" "Core 0" "CPU" "Package id 0" "Composite"; do
        sensors_output=$(sudo sensors 2>/dev/null)
        
        if [[ "$source" == "Composite" ]]; then
            # Special handling for NVMe Composite temperature
            cpu_temp=$(echo "$sensors_output" | grep -i "Composite:" | head -n 1 | awk '{print $2}' | tr -d '+°C')
        else
            cpu_temp=$(echo "$sensors_output" | grep -i "$source" | awk '{print $2}' | tr -d '+°C')
        fi
        
        if [[ -n "$cpu_temp" ]]; then
            log "Temperature found from source: $source"
            echo "$cpu_temp"
            return 0
        fi
    done
    
    # If we get here, try any temperature value as a last resort
    cpu_temp=$(echo "$sensors_output" | grep -E '[-+][0-9.]+°C' | head -n 1 | awk '{print $2}' | tr -d '+°C')
    if [[ -n "$cpu_temp" ]]; then
        log "Temperature found from generic source"
        echo "$cpu_temp"
        return 0
    fi
    
    return 1
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" 2>/dev/null || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" 2>/dev/null || true

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