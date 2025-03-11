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

# Get process information without using sudo
ps_output=$(ps aux --sort=-%cpu | head -n 11 2>/dev/null || echo "Failed to get process list")

# Parse parameters
param_type="$1"
param_index="$2"

# Extract process information into arrays
declare -a process_names
declare -a process_cpus

process_count=0
while read -r line; do
    if [ $process_count -lt 10 ]; then
        process_names[$process_count]=$(echo "$line" | awk '{print $11}')
        process_cpus[$process_count]=$(echo "$line" | awk '{print $3}')
        process_count=$((process_count+1))
    else
        break
    fi
done < <(echo "$ps_output" | tail -n +2)

# Handle parameters
if [ -n "$param_type" ]; then
    case "$param_type" in
        "name")
            if [ -n "$param_index" ] && [ "$param_index" -lt 10 ]; then
                echo "${process_names[$param_index]}"
            else
                echo "Unknown"
            fi
            exit 0
            ;;
        "cpu")
            if [ -n "$param_index" ] && [ "$param_index" -lt 10 ]; then
                echo "${process_cpus[$param_index]}"
            else
                echo "0"
            fi
            exit 0
            ;;
    esac
fi

# If no parameters or unrecognized parameters, output full JSON
process_json="["
for i in $(seq 0 $((process_count-1))); do
    if [ $i -gt 0 ]; then
        process_json+=","
    fi
    process_json+="{\"name\":\"${process_names[$i]}\",\"cpu\":${process_cpus[$i]}}"
done
process_json+="]"

echo "{
    \"top_processes\": $process_json
}" 