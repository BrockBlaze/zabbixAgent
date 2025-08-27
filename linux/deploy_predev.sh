#!/bin/bash

# Quick deployment script for your predev servers
# Zabbix Server: 192.168.70.2

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration for your environment
ZABBIX_SERVER="192.168.70.2"
SERVERS=(
    "192.168.68.146:Arc"
    "192.168.70.35:Cobalt"
)
SERVER_IPS=(
    "192.168.68.146"
    "192.168.70.35"
)
SERVER_NAMES=(
    "Arc"
    "Cobalt"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Zabbix Agent Deployment for Predev${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Zabbix Server: ${GREEN}$ZABBIX_SERVER${NC}"
echo -e "Target Servers:"
for server in "${SERVERS[@]}"; do
    echo -e "  - ${GREEN}$server${NC}"
done
echo ""

# Method selection
echo "Select deployment method:"
echo "  1) Deploy using SSH (requires root/sudo access)"
echo "  2) Generate install commands to run manually on each server"
echo "  3) Test connectivity first"
echo ""
read -p "Choice [1-3]: " choice

case $choice in
    1)
        # SSH deployment
        echo ""
        read -p "SSH username (default: root): " SSH_USER
        SSH_USER="${SSH_USER:-root}"
        
        for server in "${SERVERS[@]}"; do
            echo ""
            echo -e "${BLUE}Deploying to $server...${NC}"
            
            # Test SSH connection
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$server" "echo 'Connected'" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ SSH connection successful${NC}"
                
                # Copy installer script
                echo "Copying installer script..."
                scp -o StrictHostKeyChecking=no install_auto.sh "$SSH_USER@$server:/tmp/" 2>/dev/null || {
                    echo -e "${YELLOW}Could not copy installer, will download directly${NC}"
                    
                    # Upload installer content directly
                    ssh "$SSH_USER@$server" "cat > /tmp/install_auto.sh" < install_auto.sh
                }
                
                # Run installer
                echo "Running installer (this may take a few minutes)..."
                ssh "$SSH_USER@$server" "chmod +x /tmp/install_auto.sh && echo '1' | sudo ZABBIX_SERVER=$ZABBIX_SERVER /tmp/install_auto.sh"
                
                # Verify installation
                if ssh "$SSH_USER@$server" "systemctl is-active --quiet zabbix-agent2 || systemctl is-active --quiet zabbix-agent"; then
                    echo -e "${GREEN}✓ Zabbix agent installed and running on $server${NC}"
                    
                    # Get agent version
                    ssh "$SSH_USER@$server" "zabbix_agent2 --version 2>/dev/null | head -1 || zabbix_agentd --version 2>/dev/null | head -1"
                    
                    # Download the generated template
                    echo "Downloading generated template..."
                    scp "$SSH_USER@$server:/tmp/zabbix_template_*.json" "./zabbix_template_${server}.json" 2>/dev/null && \
                        echo -e "${GREEN}Template saved: zabbix_template_${server}.json${NC}"
                else
                    echo -e "${RED}✗ Installation may have failed on $server${NC}"
                fi
            else
                echo -e "${RED}✗ Cannot connect to $server via SSH${NC}"
                echo "  Please check SSH access or run manual installation (option 2)"
            fi
        done
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN} Next Steps:${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo "1. Import the generated templates into Zabbix:"
        echo "   - Go to Configuration → Templates → Import"
        echo "   - Select the JSON files generated"
        echo ""
        echo "2. Add hosts in Zabbix:"
        echo "   - Go to Configuration → Hosts → Create Host"
        echo "   - For 192.168.68.146:"
        echo "     Host name: predev-server-1"
        echo "     Groups: Linux servers"
        echo "     Interface: Agent, 192.168.68.146, port 10050"
        echo "   - For 192.168.70.35:"
        echo "     Host name: predev-server-2"
        echo "     Groups: Linux servers" 
        echo "     Interface: Agent, 192.168.70.35, port 10050"
        echo ""
        echo "3. Link templates:"
        echo "   - Template Linux Auto Custom"
        echo "   - Linux by Zabbix agent"
        ;;
        
    2)
        # Manual commands
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE} Manual Installation Commands${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo "Run these commands on each server:"
        echo ""
        
        for server in "${SERVERS[@]}"; do
            echo -e "${GREEN}For server $server:${NC}"
            echo "----------------------------------------"
            echo "# SSH into the server"
            echo "ssh root@$server"
            echo ""
            echo "# Download and run installer"
            echo "wget https://raw.githubusercontent.com/yourusername/zabbix-agent/main/install_auto.sh"
            echo "# Or if no internet access, copy the install_auto.sh file manually"
            echo ""
            echo "# Run the installer"
            echo "chmod +x install_auto.sh"
            echo "echo '1' | sudo ZABBIX_SERVER=$ZABBIX_SERVER ./install_auto.sh"
            echo ""
            echo "# Verify installation"
            echo "systemctl status zabbix-agent2"
            echo "zabbix_get -s localhost -k agent.ping"
            echo ""
            echo "# Get the template file for import"
            echo "cat /tmp/zabbix_template_*.json"
            echo "----------------------------------------"
            echo ""
        done
        
        echo -e "${YELLOW}Alternative one-liner for each server:${NC}"
        echo ""
        for server in "${SERVERS[@]}"; do
            echo "# For $server:"
            echo "curl -sSL https://yourserver/install_auto.sh | ssh root@$server 'ZABBIX_SERVER=$ZABBIX_SERVER sudo bash'"
            echo ""
        done
        ;;
        
    3)
        # Test connectivity
        echo ""
        echo -e "${BLUE}Testing connectivity...${NC}"
        echo ""
        
        # Test Zabbix server
        echo -e "Testing Zabbix Server ($ZABBIX_SERVER):"
        if ping -c 1 -W 2 $ZABBIX_SERVER >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ Ping successful${NC}"
            if nc -zv -w 2 $ZABBIX_SERVER 10051 2>/dev/null; then
                echo -e "  ${GREEN}✓ Port 10051 (Zabbix server) is open${NC}"
            else
                echo -e "  ${YELLOW}⚠ Port 10051 might be closed or filtered${NC}"
            fi
        else
            echo -e "  ${RED}✗ Cannot ping Zabbix server${NC}"
        fi
        
        echo ""
        
        # Test target servers
        for server in "${SERVERS[@]}"; do
            echo -e "Testing $server:"
            
            # Ping test
            if ping -c 1 -W 2 $server >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓ Ping successful${NC}"
            else
                echo -e "  ${RED}✗ Cannot ping server${NC}"
                continue
            fi
            
            # SSH test
            if nc -zv -w 2 $server 22 2>/dev/null; then
                echo -e "  ${GREEN}✓ SSH port 22 is open${NC}"
                
                # Try SSH connection
                read -p "  Test SSH login? (y/n): " test_ssh
                if [ "$test_ssh" = "y" ]; then
                    read -p "  SSH username: " ssh_user
                    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$ssh_user@$server" "echo 'SSH OK'" 2>/dev/null; then
                        echo -e "  ${GREEN}✓ SSH login successful${NC}"
                        
                        # Check if agent already installed
                        if ssh "$ssh_user@$server" "systemctl is-active --quiet zabbix-agent2 || systemctl is-active --quiet zabbix-agent" 2>/dev/null; then
                            echo -e "  ${YELLOW}⚠ Zabbix agent already installed and running${NC}"
                        else
                            echo -e "  ${BLUE}ℹ Zabbix agent not installed${NC}"
                        fi
                    else
                        echo -e "  ${RED}✗ SSH login failed${NC}"
                    fi
                fi
            else
                echo -e "  ${YELLOW}⚠ SSH port 22 might be closed${NC}"
            fi
            
            echo ""
        done
        
        echo -e "${BLUE}Network routes from this machine:${NC}"
        echo "To 192.168.68.0/24:"
        ip route get 192.168.68.146 2>/dev/null | head -1 || echo "  No route found"
        echo "To 192.168.70.0/24:"
        ip route get 192.168.70.35 2>/dev/null | head -1 || echo "  No route found"
        ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Testing Commands (after installation)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "From the Zabbix server ($ZABBIX_SERVER), test with:"
echo "  zabbix_get -s 192.168.68.146 -k agent.ping"
echo "  zabbix_get -s 192.168.70.35 -k agent.ping"
echo ""
echo "On each agent server, test with:"
echo "  zabbix_get -s localhost -k agent.ping"
echo "  zabbix_get -s localhost -k custom.cpu.temp"
echo "  systemctl status zabbix-agent2"