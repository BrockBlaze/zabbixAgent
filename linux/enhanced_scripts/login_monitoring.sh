#!/bin/bash

# Configuration
FAILED_LOG="/var/log/auth.log"
TIMEFRAME="1hour ago"
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname $LOG_FILE)"

# Get successful logins
successful_logins=$(last -s "$TIMEFRAME" | grep -v "reboot" | grep -v "^$" | wc -l)
if [ $? -ne 0 ]; then
    log "Error getting successful logins"
    successful_logins=0
fi

# Get failed login attempts
if [ -f "$FAILED_LOG" ]; then
    failed_logins=$(grep "Failed password" "$FAILED_LOG" | awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date' | wc -l)
    if [ $? -ne 0 ]; then
        log "Error getting failed logins"
        failed_logins=0
    fi
else
    log "Auth log file not found at $FAILED_LOG"
    failed_logins=0
fi

# Calculate statistics
total_attempts=$((successful_logins + failed_logins))
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Log the results
log "Login statistics for past hour: Success=$successful_logins Failed=$failed_logins Total=$total_attempts"

# Output in JSON format for better Zabbix integration
cat << EOF
{
    "timestamp": "$current_time",
    "successful_logins": $successful_logins,
    "failed_logins": $failed_logins,
    "total_attempts": $total_attempts,
    "timeframe": "past hour"
}
EOF 