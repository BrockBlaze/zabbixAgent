#!/bin/bash

# Quick fix script for already installed Zabbix agent
# Fixes configuration issues and restarts the service

echo "Fixing Zabbix agent configuration..."

# Detect which agent is installed
if systemctl list-units --full -all | grep -q "zabbix-agent2.service"; then
    AGENT_SERVICE="zabbix-agent2"
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    echo "Found zabbix-agent2"
elif systemctl list-units --full -all | grep -q "zabbix-agent.service"; then
    AGENT_SERVICE="zabbix-agent"
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    echo "Found zabbix-agent"
else
    echo "No Zabbix agent service found!"
    exit 1
fi

# Stop the service
echo "Stopping $AGENT_SERVICE..."
sudo systemctl stop $AGENT_SERVICE

# Backup current config
echo "Backing up current configuration..."
sudo cp $AGENT_CONFIG ${AGENT_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)

# Fix the configuration file - remove or comment out problematic test line
echo "Fixing configuration file..."

# Remove the test configuration line if it exists
sudo sed -i '/^\[m|ZBX_NOTSUPPORTED\]/d' $AGENT_CONFIG 2>/dev/null

# Ensure proper permissions
sudo chown zabbix:zabbix $AGENT_CONFIG
sudo chmod 640 $AGENT_CONFIG

# Make sure log directory exists with proper permissions
sudo mkdir -p /var/log/zabbix
sudo chown -R zabbix:zabbix /var/log/zabbix
sudo chmod 755 /var/log/zabbix

# Make sure PID directory exists
sudo mkdir -p /var/run/zabbix
sudo chown -R zabbix:zabbix /var/run/zabbix
sudo chmod 755 /var/run/zabbix

# Test the configuration
echo "Testing configuration..."
if [ "$AGENT_SERVICE" = "zabbix-agent2" ]; then
    if sudo -u zabbix zabbix_agent2 -c $AGENT_CONFIG -t "agent.ping" 2>/dev/null | grep -q "\[1\]"; then
        echo "Configuration test passed!"
    else
        echo "Warning: Configuration test showed issues, but continuing..."
    fi
else
    if sudo -u zabbix zabbix_agentd -c $AGENT_CONFIG -t "agent.ping" 2>/dev/null | grep -q "\[1\]"; then
        echo "Configuration test passed!"
    else
        echo "Warning: Configuration test showed issues, but continuing..."
    fi
fi

# Start and enable the service
echo "Starting $AGENT_SERVICE..."
sudo systemctl daemon-reload
sudo systemctl start $AGENT_SERVICE
sudo systemctl enable $AGENT_SERVICE

# Check status
sleep 2
if systemctl is-active --quiet $AGENT_SERVICE; then
    echo "✓ $AGENT_SERVICE is running successfully!"
    echo ""
    echo "You can test the agent with:"
    echo "  zabbix_get -s 127.0.0.1 -k agent.ping"
    echo "  zabbix_get -s 127.0.0.1 -k system.hostname"
    echo ""
    echo "To check disk temperatures:"
    echo "  zabbix_get -s 127.0.0.1 -k disk.temperature.max"
    echo "  zabbix_get -s 127.0.0.1 -k disk.temperature.discovery"
else
    echo "✗ $AGENT_SERVICE failed to start. Check logs:"
    echo "  sudo journalctl -u $AGENT_SERVICE -n 50"
    echo "  sudo tail -50 /var/log/zabbix/zabbix_agent*.log"
    exit 1
fi