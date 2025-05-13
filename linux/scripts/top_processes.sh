#!/bin/bash

# Check if required commands exist
if ! command -v ps >/dev/null 2>&1; then
    echo "ERROR: ps command not found"
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "ERROR: timeout command not found"
    exit 1
fi

# Get top 10 processes by CPU usage with timeout
output=$(timeout 5s ps -eo pid,comm,%mem,%cpu --sort=-%cpu | head -n 11)

# Check if we got valid output
if [ -z "$output" ]; then
    echo "ERROR: Could not get process information"
    exit 1
fi

# Check if we got the header and at least one process
if [ $(echo "$output" | wc -l) -lt 2 ]; then
    echo "ERROR: No process information available"
    exit 1
fi

# Format and output the data
echo "$output" | awk 'NR>1 {print $1","$2","$3","$4}'

