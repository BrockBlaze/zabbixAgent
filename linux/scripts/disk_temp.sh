#!/bin/bash

# Disk Temperature Monitoring Script for Zabbix
# Monitors temperature of SSD/HDD drives using smartctl
# Supports multiple disks and different output formats

# Check if smartctl is installed
if ! command -v smartctl >/dev/null 2>&1; then
    echo "ERROR: smartctl not found. Please install smartmontools package"
    exit 1
fi

# Function to get temperature for a single disk
get_disk_temp() {
    local disk="$1"
    local temp=""
    
    # Check if disk exists
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    # Try to get temperature using smartctl with timeout
    # Different drives report temperature in different ways
    temp=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '
        /^194 Temperature_Celsius/ { print $10; exit }
        /^190 Airflow_Temperature_Cel/ { print $10; exit }
        /^194 Temp/ { print $10; exit }
        /Temperature:/ { gsub(/[^0-9]/, "", $2); print $2; exit }
        /Current Drive Temperature:/ { print $4; exit }
        /Temperature Sensor [0-9]:/ { gsub(/[^0-9]/, "", $3); print $3; exit }
    ')
    
    # If no temperature found, try NVMe specific command
    if [ -z "$temp" ] && [[ "$disk" == *"nvme"* ]]; then
        temp=$(timeout 5s sudo nvme smart-log "$disk" 2>/dev/null | awk '/^temperature/ { gsub(/[^0-9]/, "", $3); print $3; exit }')
    fi
    
    # Return temperature or error
    if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
        echo "$temp"
        return 0
    else
        echo "ERROR: Could not read temperature for $disk"
        return 1
    fi
}

# Function to discover all disks
discover_disks() {
    echo "{"
    echo '  "data": ['
    
    first=1
    # Find all disk devices (sd*, nvme*, hd*)
    for disk in $(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/hd[a-z] 2>/dev/null | sort -u); do
        if [ -e "$disk" ]; then
            if [ $first -eq 0 ]; then
                echo ","
            fi
            echo -n "    { \"{#DISKNAME}\": \"$(basename $disk)\", \"{#DISKPATH}\": \"$disk\" }"
            first=0
        fi
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

# Function to get all disk temperatures
get_all_temps() {
    for disk in $(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/hd[a-z] 2>/dev/null | sort -u); do
        if [ -e "$disk" ]; then
            temp=$(get_disk_temp "$disk" 2>/dev/null)
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                echo "$(basename $disk):$temp"
            fi
        fi
    done
}

# Function to get average temperature
get_average_temp() {
    local sum=0
    local count=0
    
    for disk in $(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/hd[a-z] 2>/dev/null | sort -u); do
        if [ -e "$disk" ]; then
            temp=$(get_disk_temp "$disk" 2>/dev/null)
            if [[ "$temp" =~ ^[0-9]+$ ]]; then
                sum=$((sum + temp))
                count=$((count + 1))
            fi
        fi
    done
    
    if [ $count -gt 0 ]; then
        echo $((sum / count))
    else
        echo "ERROR: No disk temperatures available"
        exit 1
    fi
}

# Function to get hottest disk temperature
get_max_temp() {
    local max=0
    local hottest_disk=""
    
    for disk in $(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/hd[a-z] 2>/dev/null | sort -u); do
        if [ -e "$disk" ]; then
            temp=$(get_disk_temp "$disk" 2>/dev/null)
            if [[ "$temp" =~ ^[0-9]+$ ]] && [ "$temp" -gt "$max" ]; then
                max=$temp
                hottest_disk=$(basename "$disk")
            fi
        fi
    done
    
    if [ $max -gt 0 ]; then
        echo "$max"
    else
        echo "ERROR: No disk temperatures available"
        exit 1
    fi
}

# Main logic - determine what information to return
case "${1:-}" in
    "discover")
        # Return JSON for Zabbix LLD (Low Level Discovery)
        discover_disks
        ;;
    "all")
        # Return all disk temperatures
        get_all_temps
        ;;
    "average")
        # Return average temperature of all disks
        get_average_temp
        ;;
    "max")
        # Return maximum (hottest) temperature
        get_max_temp
        ;;
    "")
        # Default: return max temperature for alerting
        get_max_temp
        ;;
    *)
        # Specific disk temperature
        if [[ "$1" == "/dev/"* ]]; then
            get_disk_temp "$1"
        else
            get_disk_temp "/dev/$1"
        fi
        ;;
esac