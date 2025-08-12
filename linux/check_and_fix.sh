#!/bin/bash

# Comprehensive check and fix script for Zabbix agent
# Diagnoses and repairs common installation issues

echo "=========================================="
echo "Zabbix Agent Diagnostic & Repair Tool"
echo "=========================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check service status
check_service() {
    echo "1. Checking service status..."
    if systemctl is-active --quiet zabbix-agent2; then
        echo -e "${GREEN}✓${NC} zabbix-agent2 service is running"
        AGENT_SERVICE="zabbix-agent2"
        AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
        AGENT_BINARY="zabbix_agent2"
    else
        echo -e "${RED}✗${NC} zabbix-agent2 service is not running"
        echo "  Checking for errors..."
        journalctl -u zabbix-agent2 -n 5 --no-pager | grep -i error || echo "  No recent errors in journal"
        AGENT_SERVICE="zabbix-agent2"
        AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
        AGENT_BINARY="zabbix_agent2"
    fi
    echo
}

# Function to check configuration file
check_config() {
    echo "2. Checking configuration file..."
    if [ -f "$AGENT_CONFIG" ]; then
        echo -e "${GREEN}✓${NC} Configuration file exists: $AGENT_CONFIG"
        
        # Check for server configuration
        if grep -q "^Server=" "$AGENT_CONFIG"; then
            SERVER=$(grep "^Server=" "$AGENT_CONFIG" | cut -d'=' -f2)
            echo -e "${GREEN}✓${NC} Server configured: $SERVER"
        else
            echo -e "${RED}✗${NC} Server not configured"
        fi
        
        # Check for hostname
        if grep -q "^Hostname=" "$AGENT_CONFIG"; then
            HOSTNAME=$(grep "^Hostname=" "$AGENT_CONFIG" | cut -d'=' -f2)
            echo -e "${GREEN}✓${NC} Hostname configured: $HOSTNAME"
        else
            echo -e "${YELLOW}!${NC} Hostname not configured (will use system hostname)"
        fi
    else
        echo -e "${RED}✗${NC} Configuration file not found!"
    fi
    echo
}

# Function to check permissions
check_permissions() {
    echo "3. Checking file permissions..."
    
    # Check config file permissions
    if [ -f "$AGENT_CONFIG" ]; then
        OWNER=$(stat -c '%U:%G' "$AGENT_CONFIG")
        PERMS=$(stat -c '%a' "$AGENT_CONFIG")
        if [ "$OWNER" = "zabbix:zabbix" ] || [ "$OWNER" = "root:root" ]; then
            echo -e "${GREEN}✓${NC} Config ownership: $OWNER"
        else
            echo -e "${RED}✗${NC} Config ownership incorrect: $OWNER (should be zabbix:zabbix)"
        fi
    fi
    
    # Check log directory
    if [ -d "/var/log/zabbix" ]; then
        OWNER=$(stat -c '%U:%G' "/var/log/zabbix")
        if [ "$OWNER" = "zabbix:zabbix" ]; then
            echo -e "${GREEN}✓${NC} Log directory ownership: $OWNER"
        else
            echo -e "${RED}✗${NC} Log directory ownership incorrect: $OWNER"
        fi
    else
        echo -e "${RED}✗${NC} Log directory doesn't exist"
    fi
    echo
}

# Function to test agent connectivity
test_agent() {
    echo "4. Testing agent connectivity..."
    
    # Test with zabbix_get if available
    if command -v zabbix_get >/dev/null 2>&1; then
        if zabbix_get -s 127.0.0.1 -k agent.ping 2>/dev/null | grep -q "1"; then
            echo -e "${GREEN}✓${NC} Agent responds to ping"
        else
            echo -e "${RED}✗${NC} Agent not responding to ping"
        fi
        
        # Test hostname
        HOSTNAME_RESULT=$(zabbix_get -s 127.0.0.1 -k system.hostname 2>/dev/null)
        if [ -n "$HOSTNAME_RESULT" ]; then
            echo -e "${GREEN}✓${NC} Agent hostname: $HOSTNAME_RESULT"
        fi
    else
        # Try using the agent binary directly
        if $AGENT_BINARY -c "$AGENT_CONFIG" -t agent.ping 2>/dev/null | grep -q "\[1\]"; then
            echo -e "${GREEN}✓${NC} Agent configuration test passed"
        else
            echo -e "${YELLOW}!${NC} Direct agent test had issues"
        fi
    fi
    echo
}

# Function to check port
check_port() {
    echo "5. Checking network port..."
    if ss -tuln | grep -q ":10050 "; then
        echo -e "${GREEN}✓${NC} Port 10050 is listening"
        ss -tuln | grep ":10050 " | head -1
    else
        echo -e "${RED}✗${NC} Port 10050 is not listening"
    fi
    echo
}

# Function to fix common issues
fix_issues() {
    echo "6. Attempting to fix issues..."
    
    # Fix permissions
    echo "   Fixing permissions..."
    sudo chown -R zabbix:zabbix /var/log/zabbix 2>/dev/null
    sudo chown -R zabbix:zabbix /var/run/zabbix 2>/dev/null
    sudo chown zabbix:zabbix "$AGENT_CONFIG" 2>/dev/null
    sudo chmod 640 "$AGENT_CONFIG" 2>/dev/null
    
    # Create missing directories
    sudo mkdir -p /var/log/zabbix /var/run/zabbix
    sudo chown -R zabbix:zabbix /var/log/zabbix /var/run/zabbix
    
    # Remove any invalid lines from config
    sudo sed -i '/^\[.*ZBX_NOTSUPPORTED.*\]/d' "$AGENT_CONFIG" 2>/dev/null
    
    # Restart service
    echo "   Restarting service..."
    sudo systemctl daemon-reload
    sudo systemctl restart $AGENT_SERVICE
    
    sleep 3
    
    # Check if fixed
    if systemctl is-active --quiet $AGENT_SERVICE; then
        echo -e "${GREEN}✓${NC} Service is now running!"
    else
        echo -e "${RED}✗${NC} Service still not running. Checking logs..."
        echo
        echo "Recent error logs:"
        sudo journalctl -u $AGENT_SERVICE -p err -n 10 --no-pager
    fi
    echo
}

# Function to show summary
show_summary() {
    echo "=========================================="
    echo "Summary & Recommendations"
    echo "=========================================="
    
    if systemctl is-active --quiet $AGENT_SERVICE; then
        echo -e "${GREEN}✓ Zabbix agent is running${NC}"
        echo
        echo "Test commands you can run:"
        echo "  zabbix_get -s 127.0.0.1 -k agent.ping"
        echo "  zabbix_get -s 127.0.0.1 -k system.hostname"
        echo "  zabbix_get -s 127.0.0.1 -k disk.temperature.max"
        echo "  zabbix_get -s 127.0.0.1 -k disk.temperature.discovery"
        echo
        echo "Monitor logs:"
        echo "  sudo tail -f /var/log/zabbix/zabbix_agent2.log"
    else
        echo -e "${RED}✗ Zabbix agent is not running${NC}"
        echo
        echo "Troubleshooting steps:"
        echo "1. Check the full error log:"
        echo "   sudo journalctl -u $AGENT_SERVICE -n 50"
        echo
        echo "2. Check configuration syntax:"
        echo "   sudo -u zabbix $AGENT_BINARY -c $AGENT_CONFIG -t agent.ping"
        echo
        echo "3. Try starting manually:"
        echo "   sudo -u zabbix $AGENT_BINARY -c $AGENT_CONFIG -f"
        echo
        echo "4. Check if another process is using port 10050:"
        echo "   sudo lsof -i :10050"
    fi
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script with sudo:"
        echo "  sudo $0"
        exit 1
    fi
    
    check_service
    check_config
    check_permissions
    check_port
    test_agent
    
    # Ask if user wants to attempt fixes
    echo -n "Do you want to attempt automatic fixes? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        fix_issues
    fi
    
    show_summary
}

# Run main function
main