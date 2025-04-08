#!/bin/bash

# Check if sensors command exists
if ! command -v sensors >/dev/null 2>&1; then
    echo "ERROR: sensors command not found"
    exit 1
fi

# Get CPU temperature
cpu_temp=$(sensors | grep -E 'Core|Tdie' | awk '{print $2}' | tr -d '+°C')

# Check if we got a valid temperature
if [ -z "$cpu_temp" ]; then
    echo "ERROR: Could not read CPU temperature"
    exit 1
fi

# Output the temperature
echo "$cpu_temp"