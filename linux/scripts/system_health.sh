#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix/monitoring.log"
PARAM="$1"

log() {
    # Try to write to log file, but don't fail if we can't
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true

# Collect system uptime information
get_uptime() {
    uptime_seconds=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
    uptime_days=$((uptime_seconds / 86400))
    uptime_hours=$(( (uptime_seconds % 86400) / 3600 ))
    uptime_minutes=$(( (uptime_seconds % 3600) / 60 ))
    
    echo "{\"seconds\":$uptime_seconds,\"days\":$uptime_days,\"hours\":$uptime_hours,\"minutes\":$uptime_minutes}"
}

# Collect CPU information
get_cpu_info() {
    # Get CPU load averages
    load_1min=$(cat /proc/loadavg | awk '{print $1}')
    load_5min=$(cat /proc/loadavg | awk '{print $2}')
    load_15min=$(cat /proc/loadavg | awk '{print $3}')
    
    # Get CPU usage percentages
    cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%id,')
    cpu_usage=$(awk "BEGIN {print 100 - $cpu_idle}")
    
    # Get number of cores/processors
    cpu_cores=$(grep -c "processor" /proc/cpuinfo)
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | tr -s ' ')
    
    echo "{\"load\":{\"1min\":$load_1min,\"5min\":$load_5min,\"15min\":$load_15min},\"usage\":$cpu_usage,\"cores\":$cpu_cores,\"model\":\"$cpu_model\"}"
}

# Collect memory information
get_memory_info() {
    # Get memory information from /proc/meminfo
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_free=$(grep MemFree /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_cached=$(grep "^Cached:" /proc/meminfo | awk '{print $2}')
    mem_buffers=$(grep "^Buffers:" /proc/meminfo | awk '{print $2}')
    
    # Calculate used memory (in KB)
    mem_used=$((mem_total - mem_free - mem_buffers - mem_cached))
    
    # Calculate usage percentages
    mem_used_percent=$(awk "BEGIN {print ($mem_used / $mem_total) * 100}")
    mem_used_percent=$(printf "%.2f" $mem_used_percent)
    
    # Convert to MB for readability
    mem_total_mb=$((mem_total / 1024))
    mem_used_mb=$((mem_used / 1024))
    mem_free_mb=$((mem_free / 1024))
    mem_available_mb=$((mem_available / 1024))
    
    echo "{\"total_mb\":$mem_total_mb,\"used_mb\":$mem_used_mb,\"free_mb\":$mem_free_mb,\"available_mb\":$mem_available_mb,\"used_percent\":$mem_used_percent}"
}

# Collect disk information
get_disk_info() {
    # Get disk usage information
    disk_info=$(df -PT | grep -vE '^Filesystem|tmpfs|cdrom|none' | awk '{print "{\"filesystem\":\"" $1 "\",\"type\":\"" $2 "\",\"mount\":\"" $7 "\",\"size_mb\":" $3/1024 ",\"used_mb\":" $4/1024 ",\"available_mb\":" $5/1024 ",\"used_percent\":" $6 "}"}' | tr -d '%')
    
    # Format as JSON array
    echo "[$(echo "$disk_info" | tr '\n' ',' | sed 's/,$//')] "
}

# Collect network information
get_network_info() {
    # Get network interfaces and their stats
    interfaces=()
    while read -r interface; do
        # Skip loopback and virtual interfaces
        if [[ "$interface" == "lo" || "$interface" == *"veth"* || "$interface" == *"docker"* || "$interface" == *"br-"* ]]; then
            continue
        fi
        
        # Get RX/TX bytes
        rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        # Convert to MB
        rx_mb=$(awk "BEGIN {printf \"%.2f\", $rx_bytes/1024/1024}")
        tx_mb=$(awk "BEGIN {printf \"%.2f\", $tx_bytes/1024/1024}")
        
        # Check if interface is up
        if [ -f "/sys/class/net/$interface/operstate" ]; then
            state=$(cat /sys/class/net/$interface/operstate)
        else
            state="unknown"
        fi
        
        # Format as JSON
        interfaces+=("{\"interface\":\"$interface\",\"state\":\"$state\",\"rx_mb\":$rx_mb,\"tx_mb\":$tx_mb}")
    done < <(ls /sys/class/net/)
    
    # Join interfaces into JSON array
    echo "[$(IFS=,; echo "${interfaces[*]}")]"
}

# Collect process information
get_process_info() {
    # Get total number of processes
    total_processes=$(ps aux | wc -l)
    
    # Get number of zombie processes
    zombie_processes=$(ps aux | grep -c "Z")
    
    echo "{\"total\":$total_processes,\"zombie\":$zombie_processes}"
}

# Collect system updates information (if available)
get_updates_info() {
    updates_available=0
    security_updates=0
    
    # Check for apt-based systems
    if command -v apt-get >/dev/null 2>&1; then
        # Try to get updates info non-interactively
        if command -v apt-check >/dev/null 2>&1; then
            updates_info=$(apt-check 2>&1)
            updates_available=$(echo "$updates_info" | cut -d';' -f1)
            security_updates=$(echo "$updates_info" | cut -d';' -f2)
        else
            # Count packages that can be upgraded
            apt-get -qq update >/dev/null 2>&1 || true
            updates_available=$(apt-get -s upgrade | grep -c "^Inst")
            security_updates="N/A"
        fi
    # Check for yum-based systems
    elif command -v yum >/dev/null 2>&1; then
        updates_available=$(yum check-update --quiet | grep -v "^$" | wc -l)
        # Security updates are harder to determine reliably on all systems
        security_updates="N/A"
    # Check for dnf-based systems
    elif command -v dnf >/dev/null 2>&1; then
        updates_available=$(dnf check-update --quiet | grep -v "^$" | wc -l)
        security_updates="N/A"
    fi
    
    echo "{\"available\":$updates_available,\"security\":\"$security_updates\"}"
}

# Check for specific system issues that might indicate problems
get_system_issues() {
    issues=()
    
    # Check for high load average
    load_1min=$(cat /proc/loadavg | awk '{print $1}')
    cpu_cores=$(grep -c "processor" /proc/cpuinfo)
    if (( $(echo "$load_1min > $cpu_cores" | bc -l 2>/dev/null) )); then
        issues+=("{\"type\":\"high_load\",\"message\":\"Load average ($load_1min) exceeds number of CPU cores ($cpu_cores)\"}")
    fi
    
    # Check for low disk space (less than 10% free)
    while read -r line; do
        usage=$(echo $line | awk '{print $5}' | tr -d '%')
        mount=$(echo $line | awk '{print $6}')
        if [ "$usage" -gt 90 ]; then
            issues+=("{\"type\":\"disk_space\",\"message\":\"Low disk space on $mount ($usage% used)\"}")
        fi
    done < <(df -h | grep -vE '^Filesystem|tmpfs|cdrom|none')
    
    # Check for high memory usage (more than 90%)
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used_percent=$(awk "BEGIN {print (($mem_total - $mem_available) / $mem_total) * 100}")
    if (( $(echo "$mem_used_percent > 90" | bc -l 2>/dev/null) )); then
        issues+=("{\"type\":\"memory\",\"message\":\"High memory usage (${mem_used_percent%./*}% used)\"}")
    fi
    
    # Format as JSON array
    if [ ${#issues[@]} -eq 0 ]; then
        echo "[]"
    else
        echo "[$(IFS=,; echo "${issues[*]}")]"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Make sure bc is installed for floating point comparisons
if ! command_exists bc; then
    log "bc is not installed. Some system issue checks may not work properly."
fi

# Parse parameters and return specific information if requested
if [ -n "$PARAM" ]; then
    case "$PARAM" in
        "uptime")
            get_uptime
            ;;
        "cpu")
            get_cpu_info
            ;;
        "memory")
            get_memory_info
            ;;
        "disk")
            get_disk_info
            ;;
        "network")
            get_network_info
            ;;
        "processes")
            get_process_info
            ;;
        "updates")
            get_updates_info
            ;;
        "issues")
            get_system_issues
            ;;
        *)
            echo "Unknown parameter: $PARAM"
            exit 1
            ;;
    esac
    exit 0
fi

# If no parameter specified, return complete system health information
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
hostname=$(hostname)

# Collect all system health information
uptime_info=$(get_uptime)
cpu_info=$(get_cpu_info)
memory_info=$(get_memory_info)
disk_info=$(get_disk_info)
network_info=$(get_network_info)
process_info=$(get_process_info)
updates_info=$(get_updates_info)
issues_info=$(get_system_issues)

# Log that we're gathering health information
log "Collecting system health information"

# Create JSON output with all collected information
echo "{
    \"timestamp\": \"$timestamp\",
    \"hostname\": \"$hostname\",
    \"uptime\": $uptime_info,
    \"cpu\": $cpu_info,
    \"memory\": $memory_info,
    \"disk\": $disk_info,
    \"network\": $network_info,
    \"processes\": $process_info,
    \"updates\": $updates_info,
    \"issues\": $issues_info
}" 