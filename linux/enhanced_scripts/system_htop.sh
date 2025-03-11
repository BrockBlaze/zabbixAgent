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

# Get system resource information in variables
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
memory_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
swap_usage=$(free -m | awk 'NR==3{printf "%.2f", $3*100/$2}')
disk_usage=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
load_average=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

# Extract process information into JSON format
process_json="["
IFS=$'\n'
process_count=0
for line in $(echo "$ps_output" | tail -n +2); do
    if [ $process_count -lt 10 ]; then
        user=$(echo "$line" | awk '{print $1}')
        pid=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $3}')
        mem=$(echo "$line" | awk '{print $4}')
        command=$(echo "$line" | awk '{print $11}' | sed 's/"/\\"/g')
        
        if [ $process_count -gt 0 ]; then
            process_json+=","
        fi
        
        process_json+="{\"user\":\"$user\",\"pid\":$pid,\"cpu\":$cpu,\"mem\":$mem,\"command\":\"$command\"}"
        process_count=$((process_count+1))
    else
        break
    fi
done
process_json+="]"

# Output simple JSON with essential data
echo "{
    \"timestamp\": \"$current_time\",
    \"system\": {
        \"cpu_usage\": $cpu_usage,
        \"memory_usage\": $memory_usage,
        \"swap_usage\": $swap_usage,
        \"disk_usage\": $disk_usage,
        \"load_average\": \"$load_average\"
    },
    \"processes\": $process_json
}" 