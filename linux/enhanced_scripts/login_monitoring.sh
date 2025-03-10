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

# Get successful logins - excluding Zabbix agent activities
successful_logins=$(sudo last -s "$TIMEFRAME" | grep -v "reboot" | grep -v "^$" | grep -v "zabbix" | wc -l)
if [ $? -ne 0 ]; then
    log "Error getting successful logins"
    successful_logins=0
fi

# Get the list of successful login users
successful_users=$(sudo last -s "$TIMEFRAME" | grep -v "reboot" | grep -v "^$" | grep -v "zabbix" | awk '{print $1}' | sort | uniq -c | sort -nr)
successful_users_json=$(echo "$successful_users" | awk '{print "\"" $2 "\": " $1}' | paste -sd "," -)
if [ -z "$successful_users_json" ]; then
    successful_users_json="\"\": 0"
fi

# Get successful login IPs from auth.log - LIMIT TO LAST 10
successful_ips_json=""
if [ -f "$FAILED_LOG" ]; then
    # Get the last 10 successful logins
    successful_events=()
    while IFS= read -r line; do
        timestamp=$(echo "$line" | awk '{print $1" "$2" "$3}')
        user=$(echo "$line" | grep -oP "for \K[^ ]+" | head -1)
        ip=$(echo "$line" | grep -oP "from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        if [ -n "$timestamp" ] && [ -n "$user" ] && [ -n "$ip" ]; then
            event="{\"time\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"status\":\"success\"}"
            successful_events+=("$event")
        fi
    done < <(sudo grep "Accepted password" "$FAILED_LOG" 2>/dev/null | grep -v "zabbix" | 
           awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date' | tail -10)
    
    # Join the events into a JSON array
    if [ ${#successful_events[@]} -gt 0 ]; then
        successful_events_json=$(printf ",%s" "${successful_events[@]}")
        successful_events_json="[${successful_events_json:1}]"  # Remove the leading comma
    else
        successful_events_json="[]"
    fi
fi

# Get failed login attempts - excluding Zabbix agent activities (KEEP ALL FAILED LOGINS)
if [ -f "$FAILED_LOG" ]; then
    failed_logins=$(sudo grep "Failed password" "$FAILED_LOG" 2>/dev/null | grep -v "zabbix" | 
                   awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date' | wc -l)
    
    # Get the list of users with failed logins
    failed_users=$(sudo grep "Failed password" "$FAILED_LOG" 2>/dev/null | grep -v "zabbix" | 
                  awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date' | 
                  grep -oP "for \K[^ ]+" | sort | uniq -c | sort -nr)
    failed_users_json=$(echo "$failed_users" | awk '{print "\"" $2 "\": " $1}' | paste -sd "," -)
    
    # Get failed login IPs - Keep all failed logins
    failed_ips=()
    while IFS= read -r line; do
        timestamp=$(echo "$line" | awk '{print $1" "$2" "$3}')
        user=$(echo "$line" | grep -oP "for \K[^ ]+" | head -1)
        ip=$(echo "$line" | grep -oP "from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        if [ -n "$timestamp" ] && [ -n "$user" ] && [ -n "$ip" ]; then
            event="{\"time\":\"$timestamp\",\"user\":\"$user\",\"ip\":\"$ip\",\"status\":\"failed\"}"
            failed_ips+=("$event")
        fi
    done < <(sudo grep "Failed password" "$FAILED_LOG" 2>/dev/null | grep -v "zabbix" | 
             awk -v date="$(date -d "$TIMEFRAME" '+%b %d %H:%M:%S')" '$0 > date')
    
    # Join the events into a JSON array
    if [ ${#failed_ips[@]} -gt 0 ]; then
        failed_events_json=$(printf ",%s" "${failed_ips[@]}")
        failed_events_json="[${failed_events_json:1}]"  # Remove the leading comma
    else
        failed_events_json="[]"
    fi
    
    if [ -z "$failed_users_json" ]; then
        failed_users_json="\"\": 0"
    fi
    
    if [ $? -ne 0 ]; then
        log "Error getting failed logins"
        failed_logins=0
        failed_users_json="\"\": 0"
        failed_events_json="[]"
    fi
else
    log "Auth log file not found at $FAILED_LOG"
    failed_logins=0
    failed_users_json="\"\": 0"
    failed_events_json="[]"
    successful_events_json="[]"
fi

# Combine all events into a single timeline
all_events="[]"
if [ "$successful_events_json" != "[]" ] || [ "$failed_events_json" != "[]" ]; then
    # Strip the outer brackets
    success_events_content=${successful_events_json:1:${#successful_events_json}-2}
    failed_events_content=${failed_events_json:1:${#failed_events_json}-2}
    
    # Combine with a comma if both have content
    if [ -n "$success_events_content" ] && [ -n "$failed_events_content" ]; then
        all_events="[$success_events_content,$failed_events_content]"
    elif [ -n "$success_events_content" ]; then
        all_events="[$success_events_content]"
    elif [ -n "$failed_events_content" ]; then
        all_events="[$failed_events_content]"
    fi
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
elif [ "$OUTPUT_METRIC" = "user_details" ]; then
    # Output detailed JSON with user information
    echo "{"
    echo "    \"timestamp\": \"$current_time\","
    echo "    \"successful\": { $successful_users_json },"
    echo "    \"failed\": { $failed_users_json },"
    echo "    \"timeframe\": \"past hour\""
    echo "}"
elif [ "$OUTPUT_METRIC" = "login_events" ]; then
    # Output timeline of login events with IP addresses
    echo "{"
    echo "    \"timestamp\": \"$current_time\","
    echo "    \"events\": $all_events,"
    echo "    \"timeframe\": \"past hour\""
    echo "}"
else
    # Default: output JSON with all metrics
    echo "{"
    echo "    \"timestamp\": \"$current_time\","
    echo "    \"successful_logins\": $successful_logins,"
    echo "    \"failed_logins\": $failed_logins,"
    echo "    \"total_attempts\": $total_attempts,"
    echo "    \"successful_users\": { $successful_users_json },"
    echo "    \"failed_users\": { $failed_users_json },"
    echo "    \"login_events\": $all_events,"
    echo "    \"timeframe\": \"past hour\""
    echo "}"
fi 