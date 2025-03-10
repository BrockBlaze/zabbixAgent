#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix/monitoring.log"

log() {
    # Try to write to log file, but don't fail if we can't
    # Redirect to /dev/null to prevent output to stdout
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | sudo tee -a "$LOG_FILE" > /dev/null 2>&1 || true
}

# Ensure log directory exists with proper permissions
sudo mkdir -p "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true
sudo chown -R zabbix:zabbix "$(dirname $LOG_FILE)" > /dev/null 2>&1 || true

# Format the output as JSON for Zabbix
current_time=$(date '+%Y-%m-%d %H:%M:%S')

# Get process information without using sudo (ps doesn't need sudo)
ps_output=$(ps aux --sort=-%cpu | head -n 20 2>/dev/null || echo "Failed to get process list")

# Get system resource information in variables
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
memory_usage=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2}')
swap_usage=$(free -m | awk 'NR==3{printf "%.2f", $3*100/$2}')
disk_usage=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
load_average=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

# Generate HTML-formatted output
html_output="<html>
<head>
<style>
  body { font-family: Arial, sans-serif; padding: 10px; }
  h2 { color: #333366; margin-top: 15px; }
  .resource-section { margin-bottom: 20px; }
  .progress-bar-container { 
    width: 100%; 
    background-color: #e0e0e0; 
    border-radius: 5px;
    margin-bottom: 10px;
  }
  .progress-bar { 
    height: 20px; 
    border-radius: 5px; 
    text-align: center;
    color: white;
    font-weight: bold;
  }
  .green { background-color: #4CAF50; }
  .yellow { background-color: #FFEB3B; color: black; }
  .orange { background-color: #FF9800; }
  .red { background-color: #F44336; }
  table { border-collapse: collapse; width: 100%; }
  th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
  th { background-color: #f2f2f2; }
  tr:hover {background-color: #f5f5f5;}
</style>
</head>
<body>
  <h2>System Resources</h2>
  <div class='resource-section'>
    <div><strong>CPU Usage:</strong></div>
    <div class='progress-bar-container'>
      <div class='progress-bar ${cpu_usage < 50 ? "green" : cpu_usage < 70 ? "yellow" : cpu_usage < 90 ? "orange" : "red"}' 
           style='width: ${cpu_usage}%;'>
        ${cpu_usage}%
      </div>
    </div>
    
    <div><strong>Memory Usage:</strong></div>
    <div class='progress-bar-container'>
      <div class='progress-bar ${memory_usage < 50 ? "green" : memory_usage < 70 ? "yellow" : memory_usage < 90 ? "orange" : "red"}' 
           style='width: ${memory_usage}%;'>
        ${memory_usage}%
      </div>
    </div>
    
    <div><strong>Disk Usage:</strong></div>
    <div class='progress-bar-container'>
      <div class='progress-bar ${disk_usage < 50 ? "green" : disk_usage < 70 ? "yellow" : disk_usage < 90 ? "orange" : "red"}' 
           style='width: ${disk_usage}%;'>
        ${disk_usage}%
      </div>
    </div>
    
    <div><strong>Load Average:</strong> ${load_average}</div>
  </div>
  
  <h2>Top Processes</h2>
  <table>
    <tr>
      <th>USER</th>
      <th>PID</th>
      <th>%CPU</th>
      <th>%MEM</th>
      <th>COMMAND</th>
    </tr>"

# Add each process to the HTML table
IFS=$'\n'
process_lines=0
for line in $(echo "$ps_output" | tail -n +2); do
    # Skip header line
    if [ $process_lines -lt 10 ]; then
        user=$(echo "$line" | awk '{print $1}')
        pid=$(echo "$line" | awk '{print $2}')
        cpu=$(echo "$line" | awk '{print $3}')
        mem=$(echo "$line" | awk '{print $4}')
        command=$(echo "$line" | awk '{print $11}' | xargs)
        
        html_output+="
    <tr>
      <td>${user}</td>
      <td>${pid}</td>
      <td>${cpu}</td>
      <td>${mem}</td>
      <td>${command}</td>
    </tr>"
        process_lines=$((process_lines+1))
    else
        break
    fi
done

# Close the HTML
html_output+="
  </table>
  <div style='font-size: 0.8em; color: #666; margin-top: 10px;'>Last updated: ${current_time}</div>
</body>
</html>"

# Replace any double quotes in HTML with escaped quotes for JSON
html_json=$(echo "$html_output" | sed 's/"/\\"/g')

# Output the JSON with HTML content
echo "{"
echo "    \"timestamp\": \"$current_time\","
echo "    \"html_output\": \"$html_json\""
echo "}" 