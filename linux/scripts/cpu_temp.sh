#!/bin/bash

# Get CPU temperature using lm-sensors
sensors_output=$(sensors)

# Extract the CPU temperature for "Core 0" (adjust the grep pattern as needed for your system)
cpu_temp=$(echo "$sensors_output" | grep -i 'Tctl' | awk '{print $3}' | tr -d '+°C')

# If the temperature is not found, provide a default value
if [[ -n "$cpu_temp" ]]; then
    echo "$cpu_temp"
else
    echo "Temperature not found. Ensure lm-sensors is installed and sensors-detect has been run."
    exit 1
fi