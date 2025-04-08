#!/bin/bash

# Check if last and who commands exist
if ! command -v last >/dev/null 2>&1 || ! command -v who >/dev/null 2>&1; then
    echo "ERROR: Required commands (last, who) not found"
    exit 1
fi

# Function to handle different types of login information
case "$1" in
    "failed_logins")
        # Get failed login attempts
        output=$(last -x | grep -i "fail" | awk '{print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10}')
        ;;
    "successful_logins")
        # Get successful logins
        output=$(last -x | grep -v "fail" | grep -E 'sshd|login|su' | awk '{print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10}')
        ;;
    "last10")
        # Get last 10 logins
        output=$(last -x | head -n 10 | awk '{print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10}')
        ;;
    *)
        # Get current sessions
        output=$(who | awk '{print $1","$2","$3","$4","$5","$6","$7","$8","$9","$10}')
        ;;
esac

# Check if we got valid output
if [ -z "$output" ]; then
    echo "ERROR: Could not get login information"
    exit 1
fi

# Format and output the data
echo "$output" | tr '\n' ',' | sed 's/,$//'
