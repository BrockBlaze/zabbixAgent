#!/bin/bash

# Check if ps command exists
if ! command -v ps >/dev/null 2>&1; then
    echo "ERROR: ps command not found"
    exit 1
fi

# Get top 10 processes by CPU usage
output=$(ps -eo pid,comm,%mem,%cpu --sort=-%cpu | head -n 11)

# Check if we got valid output
if [ -z "$output" ]; then
    echo "ERROR: Could not get process information"
    exit 1
fi

# Format and output the data
echo "$output" | awk 'NR>1 {print $1","$2","$3","$4}'

