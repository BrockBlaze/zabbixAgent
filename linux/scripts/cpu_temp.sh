#!/bin/bash

# Check if sensors command exists
if ! command -v sensors >/dev/null 2>&1; then
    echo "ERROR: sensors command not found"
    exit 1
fi

# Get temperature with timeout
TEMP=$(timeout 5s sensors | awk '
/k10temp/ {found=1}
/Tctl:/ && found {gsub(/\+/,""); gsub(/°C/,""); print $2; exit}
/CPU Package:/ {gsub(/\+/,""); gsub(/°C/,""); print $3; exit}
')

# Check if we got valid output
if [ -z "$TEMP" ]; then
    echo "ERROR: Could not get temperature reading"
    exit 1
fi

echo "$TEMP"