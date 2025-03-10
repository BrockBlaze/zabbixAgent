#!/bin/bash

# Configuration
FAILED_LOG="/var/log/auth.log"
TIMEFRAME="1hour ago"
LOG_FILE="/var/log/zabbix/monitoring.log"

# Check if a specific metric was requested
OUTPUT_METRIC="$1"

log() {
    # Try to write to log file, but don't fail if we can't
    # Redirect to /dev/null to prevent output to stdout
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true

# Get successful logins
successful_logins=$(sudo last -s "$TIMEFRAME" | grep -v "reboot" | grep -v "^$" | wc -l)
if [ $? -ne 0 ]; then
    log "Error getting successful logins"
    successful_logins=0
fi

# Get failed login attempts
if [ -f "$FAILED_LOG" ]; then
    failed_logins=$(sudo grep "Failed password" "$FAILED_LOG" 2>/dev/null | awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date' | wc -l)
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

# Output based on the requested metric
if [ "$OUTPUT_METRIC" = "failed_logins" ]; then
    echo "$failed_logins"
elif [ "$OUTPUT_METRIC" = "successful_logins" ]; then
    echo "$successful_logins"
elif [ "$OUTPUT_METRIC" = "total_attempts" ]; then
    echo "$total_attempts"
else
    # Default: output JSON with all metrics
    echo "{"
    echo "    \"timestamp\": \"$current_time\","
    echo "    \"successful_logins\": $successful_logins,"
    echo "    \"failed_logins\": $failed_logins,"
    echo "    \"total_attempts\": $total_attempts,"
    echo "    \"timeframe\": \"past hour\""
    echo "}"
fi 