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

# Format the output as JSON for Zabbix
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Skip htop entirely and use ps, which is guaranteed to work on all Linux systems
# Sort processes by CPU usage (highest first)
ps_output=$(sudo ps aux --sort=-%cpu | head -n 20)

# Add system resource information 
system_info="=== SYSTEM RESOURCES ===\n"
system_info+="CPU Usage: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')%\n"
system_info+="Memory Usage: $(free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}')\n"
system_info+="Swap Usage: $(free -m | awk 'NR==3{printf "%.2f%%", $3*100/$2}')\n"
system_info+="Disk Usage: $(df -h / | awk 'NR==2{print $5}')\n"
system_info+="Load Average: $(cat /proc/loadavg | awk '{print $1, $2, $3}')\n"
system_info+="=== TOP PROCESSES ===\n"

# Combine system info with process list
full_output="${system_info}${ps_output}"

# Replace special characters to make it valid JSON
output_json=$(echo "$full_output" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/\t/    /g' | sed 's/  / /g')

# Output the JSON
echo "{"
echo "    \"timestamp\": \"$current_time\","
echo "    \"system_info\": \"$output_json\""
echo "}" 