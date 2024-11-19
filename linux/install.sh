#!/bin/bash

# Ask for the Zabbix server IP and hostname
read -p "Enter Zabbix Server IP: " ZABBIX_SERVER_IP
read -p "Enter Hostname (this server's name): " HOSTNAME

# Install the Zabbix agent (Debian-based systems)
echo "Installing Zabbix Agent..."
sudo apt update
sudo apt install -y zabbix-agent

echo "Installing Sensors..."
# Install lm-sensors
sudo apt install -y lm-sensors

echo "Automatically Detecting Sensors..."
# Configure sensors (automatic detection)
yes | sudo sensors-detect

# Create CPU temperature script
echo "Creating CPU temperature script..."
sudo mkdir -p /etc/zabbix/scripts
cat << 'EOF' | sudo tee /etc/zabbix/scripts/cpu_temp.sh
#!/bin/bash

# Get CPU temperature using lm-sensors
sensors_output=$(sensors)

# Extract the CPU temperature for "Core 0" (adjust the grep pattern as needed for your system)
cpu_temp=$(echo "$sensors_output" | grep -i 'Sensor 1' | awk '{print $3}' | tr -d '+°C')

# If the temperature is not found, provide a default value
if [[ -n "$cpu_temp" ]]; then
    echo "$cpu_temp"
else
    echo "Temperature not found. Ensure lm-sensors is installed and sensors-detect has been run."
    exit 1
fi
EOF

sudo chmod +x /etc/zabbix/scripts/cpu_temp.sh

# Create Login monitoring script
echo "Creating Login monitoring script..."
sudo mkdir -p /etc/zabbix/scripts
sudo bash -c 'cat << EOF > /etc/zabbix/scripts/login_monitoring.sh
#!/bin/bash
# Get login attempts using last command
last -n 10
EOF'

sudo chmod +x /etc/zabbix/scripts/login_monitoring.sh

# Backup the original configuration file (in case something goes wrong)
cp /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.backup

# Modify the zabbix_agentd.conf file to include the user input
echo "Configuring Zabbix agent..."

# Replace placeholders with actual values
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf
sed -i "s/^#Hostname=.*/Hostname=$HOSTNAME/" /etc/zabbix/zabbix_agentd.conf

# Add custom UserParameter for Zabbix agent
if ! grep -q "UserParameter=cpu.temperature" /etc/zabbix/zabbix_agentd.conf; then
  echo "UserParameter=cpu.temperature,/etc/zabbix/scripts/cpu_temp.sh" | sudo tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Add custom UserParameter for Zabbix agent
if ! grep -q "UserParameter=login.attempts" /etc/zabbix/zabbix_agentd.conf; then
  echo "UserParameter=login.attempts,/etc/zabbix/scripts/login_monitoring.sh" | sudo tee -a /etc/zabbix/zabbix_agentd.conf
fi

# Restart the Zabbix agent service to apply the changes
sudo systemctl restart zabbix-agent

# Enable the Zabbix agent service to start on boot
sudo systemctl enable zabbix-agent

echo "Zabbix Agent installed and configured!"
