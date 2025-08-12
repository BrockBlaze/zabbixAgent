#!/bin/bash

# Disk Health Monitoring Script for Zabbix
# Monitors SMART attributes and health status of SSD/HDD drives
# Provides comprehensive disk health information

# Check if smartctl is installed
if ! command -v smartctl >/dev/null 2>&1; then
    echo "ERROR: smartctl not found. Please install smartmontools package"
    exit 1
fi

# Function to get disk SMART health status
get_disk_health() {
    local disk="$1"
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    # Get overall health status
    health=$(timeout 5s sudo smartctl -H "$disk" 2>/dev/null | awk '/^SMART overall-health self-assessment test result:/ { print $NF }')
    
    if [ "$health" = "PASSED" ]; then
        echo "OK"
    elif [ "$health" = "FAILED" ] || [ "$health" = "FAILED!" ]; then
        echo "CRITICAL"
    else
        echo "UNKNOWN"
    fi
}

# Function to get disk wear level (for SSDs)
get_ssd_wear() {
    local disk="$1"
    local wear=""
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    # Different SSDs report wear level differently
    wear=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '
        /^231 SSD_Life_Left/ { print 100-$4; exit }
        /^233 Media_Wearout_Indicator/ { print 100-$4; exit }
        /^177 Wear_Leveling_Count/ { print 100-$4; exit }
        /Percentage Used:/ { gsub(/%/, "", $3); print $3; exit }
    ')
    
    if [ -n "$wear" ] && [ "$wear" -ge 0 ] 2>/dev/null; then
        echo "$wear"
    else
        echo "N/A"
    fi
}

# Function to get reallocated sectors count
get_reallocated_sectors() {
    local disk="$1"
    local sectors=""
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    sectors=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '
        /^  5 Reallocated_Sector_Ct/ { print $10; exit }
        /^  5 Reallocated_Event_Count/ { print $10; exit }
    ')
    
    if [ -n "$sectors" ]; then
        echo "$sectors"
    else
        echo "0"
    fi
}

# Function to get pending sectors count
get_pending_sectors() {
    local disk="$1"
    local sectors=""
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    sectors=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '
        /^197 Current_Pending_Sector/ { print $10; exit }
    ')
    
    if [ -n "$sectors" ]; then
        echo "$sectors"
    else
        echo "0"
    fi
}

# Function to get power on hours
get_power_on_hours() {
    local disk="$1"
    local hours=""
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    hours=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '
        /^  9 Power_On_Hours/ { print $10; exit }
        /^  9 Power_On_Time/ { print $10; exit }
    ')
    
    if [ -n "$hours" ]; then
        echo "$hours"
    else
        echo "0"
    fi
}

# Function to get disk model and serial
get_disk_info() {
    local disk="$1"
    
    if [ ! -e "$disk" ]; then
        echo "ERROR: Disk $disk not found"
        return 1
    fi
    
    timeout 5s sudo smartctl -i "$disk" 2>/dev/null | awk '
        /^Device Model:/ { model=$0; gsub(/^Device Model: */, "", model) }
        /^Model Number:/ { model=$0; gsub(/^Model Number: */, "", model) }
        /^Serial Number:/ { serial=$0; gsub(/^Serial Number: */, "", serial) }
        END { 
            if (model != "") print "Model: " model
            if (serial != "") print "Serial: " serial
        }
    '
}

# Function to get all disk stats in JSON format
get_disk_stats_json() {
    local disk="$1"
    
    if [ ! -e "$disk" ]; then
        echo "{\"error\": \"Disk $disk not found\"}"
        return 1
    fi
    
    local health=$(get_disk_health "$disk")
    local temp=$(timeout 5s sudo smartctl -A "$disk" 2>/dev/null | awk '/^194 Temperature_Celsius/ { print $10; exit }')
    local wear=$(get_ssd_wear "$disk")
    local reallocated=$(get_reallocated_sectors "$disk")
    local pending=$(get_pending_sectors "$disk")
    local hours=$(get_power_on_hours "$disk")
    
    cat <<EOF
{
  "disk": "$(basename $disk)",
  "health": "$health",
  "temperature": "${temp:-0}",
  "wear_level": "$wear",
  "reallocated_sectors": "$reallocated",
  "pending_sectors": "$pending",
  "power_on_hours": "$hours"
}
EOF
}

# Main logic
case "${1:-}" in
    "health")
        # Get health status for specific disk or all disks
        if [ -n "$2" ]; then
            if [[ "$2" == "/dev/"* ]]; then
                get_disk_health "$2"
            else
                get_disk_health "/dev/$2"
            fi
        else
            # Return worst health status
            worst="OK"
            for disk in $(ls /dev/sd[a-z] /dev/nvme[0-9]n[0-9] 2>/dev/null); do
                health=$(get_disk_health "$disk" 2>/dev/null)
                if [ "$health" = "CRITICAL" ]; then
                    worst="CRITICAL"
                    break
                elif [ "$health" = "UNKNOWN" ] && [ "$worst" = "OK" ]; then
                    worst="UNKNOWN"
                fi
            done
            echo "$worst"
        fi
        ;;
    "wear")
        # Get wear level for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_ssd_wear "$2"
        else
            get_ssd_wear "/dev/$2"
        fi
        ;;
    "reallocated")
        # Get reallocated sectors for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_reallocated_sectors "$2"
        else
            get_reallocated_sectors "/dev/$2"
        fi
        ;;
    "pending")
        # Get pending sectors for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_pending_sectors "$2"
        else
            get_pending_sectors "/dev/$2"
        fi
        ;;
    "hours")
        # Get power on hours for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_power_on_hours "$2"
        else
            get_power_on_hours "/dev/$2"
        fi
        ;;
    "info")
        # Get disk info for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_disk_info "$2"
        else
            get_disk_info "/dev/$2"
        fi
        ;;
    "json")
        # Get all stats in JSON for specific disk
        if [[ "$2" == "/dev/"* ]]; then
            get_disk_stats_json "$2"
        else
            get_disk_stats_json "/dev/$2"
        fi
        ;;
    *)
        echo "Usage: $0 {health|wear|reallocated|pending|hours|info|json} [disk]"
        echo "Example: $0 health sda"
        echo "         $0 wear /dev/nvme0n1"
        echo "         $0 json sdb"
        exit 1
        ;;
esac