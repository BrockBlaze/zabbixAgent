#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname $LOG_FILE)"

check_service() {
    systemctl is-active --quiet "$1" && echo "1" || echo "0"
}

get_disk_usage() {
    df -h | grep -vE '^Filesystem|tmpfs|cdrom' | awk '{printf "{\"%s\": \"%s\"}, ", $1, $5}'
}

get_memory_info() {
    free -m | grep Mem | awk '{printf "\"total\": %d, \"used\": %d, \"free\": %d, \"usage_percent\": %.2f", $2, $3, $4, $3/$2 * 100}'
}

get_load_average() {
    uptime | awk -F'load average:' '{print $2}' | awk '{printf "\"1min\": %s, \"5min\": %s, \"15min\": %s", $1, $2, $3}'
}

get_process_count() {
    ps aux | wc -l
}

# Collect all metrics
zabbix_status=$(check_service zabbix-agent)
disk_usage=$(get_disk_usage)
memory_info=$(get_memory_info)
load_avg=$(get_load_average)
process_count=$(get_process_count)
system_uptime=$(uptime -p)
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Log collection completion
log "System health check completed successfully"

# Output in JSON format
cat << EOF
{
    "timestamp": "$current_time",
    "zabbix_agent_status": $zabbix_status,
    "disk_usage": [${disk_usage%,*}],
    "memory": {$memory_info},
    "load_average": {$load_avg},
    "process_count": $process_count,
    "system_uptime": "$system_uptime",
    "last_check": "$current_time"
}
EOF 