#!/bin/bash

# Zabbix Agent Deployment Script - Shared Template Version
# For Arc and Cobalt servers using shared Ubuntu template

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ZABBIX_SERVER="192.168.70.2"
SERVERS=(
    "Arc:192.168.68.146"
    "Cobalt:192.168.70.35"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Zabbix Agent Deployment (Shared Template)${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Zabbix Server: ${GREEN}$ZABBIX_SERVER${NC}"
echo -e "Using: ${GREEN}Shared Ubuntu Template${NC}"
echo ""
echo -e "Target Servers:"
for server in "${SERVERS[@]}"; do
    name="${server%%:*}"
    ip="${server##*:}"
    echo -e "  - ${GREEN}$name ($ip)${NC}"
done
echo ""

# Deployment method selection
echo "Select deployment method:"
echo "  1) Deploy to all servers via SSH"
echo "  2) Generate manual installation commands"
echo "  3) Deploy to single server"
echo ""
read -p "Choice [1-3]: " choice

case $choice in
    1)
        # Deploy to all servers
        echo ""
        read -p "SSH username (default: root): " SSH_USER
        SSH_USER="${SSH_USER:-root}"
        
        TEMPLATE_DEPLOYED=false
        
        for server_info in "${SERVERS[@]}"; do
            name="${server_info%%:*}"
            ip="${server_info##*:}"
            
            echo ""
            echo -e "${BLUE}========================================${NC}"
            echo -e "${BLUE} Deploying to $name ($ip)${NC}"
            echo -e "${BLUE}========================================${NC}"
            
            # Test connection
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$ip" "echo 'Connected'" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ SSH connection successful${NC}"
                
                # Copy shared installer
                echo "Uploading shared installer..."
                if [ -f "install_auto_shared.sh" ]; then
                    scp -q -o StrictHostKeyChecking=no install_auto_shared.sh "$SSH_USER@$ip:/tmp/" || {
                        echo "Creating installer remotely..."
                        ssh "$SSH_USER@$ip" "cat > /tmp/install_auto_shared.sh" < install_auto_shared.sh
                    }
                else
                    echo -e "${YELLOW}Local installer not found, creating remote script${NC}"
                    ssh "$SSH_USER@$ip" 'cat > /tmp/install_auto_shared.sh' << 'INSTALLER_EOF'
#!/bin/bash
# Minimal installer for shared template setup
set -e

# Install Zabbix repository
OS_VERSION=$(lsb_release -rs)
case "$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="$OS_VERSION" ;;
esac

wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${REPO_VERSION}_all.deb"
dpkg -i /tmp/zabbix-release.deb
apt-get update -q

# Install agent
apt-get install -qq -y zabbix-agent2 || apt-get install -qq -y zabbix-agent
apt-get install -qq -y lm-sensors smartmontools

# Configure
AGENT_CONFIG=$(find /etc/zabbix -name "zabbix_agent*.conf" | head -1)
cat > "$AGENT_CONFIG" << EOF
Server=${ZABBIX_SERVER:-192.168.70.2}
ServerActive=${ZABBIX_SERVER:-192.168.70.2}:10051
Hostname=${HOSTNAME:-$(hostname)}
LogFile=/var/log/zabbix/zabbix_agent.log
Include=/etc/zabbix/zabbix_agent*.d/*.conf
EOF

# Add custom parameters
mkdir -p /etc/zabbix/zabbix_agent2.d /etc/zabbix/zabbix_agentd.d
cat > /etc/zabbix/zabbix_agent2.d/custom_ubuntu.conf << 'CUSTOM_EOF'
# Shared Ubuntu metrics
UserParameter=ubuntu.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=ubuntu.mem.available,free -b | awk '/^Mem:/{print $7}'
UserParameter=ubuntu.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=ubuntu.service.status[*],systemctl is-active $1 2>/dev/null || echo "inactive"
UserParameter=ubuntu.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=ubuntu.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=ubuntu.updates.security,apt list --upgradable 2>/dev/null | grep -c security || echo 0
UserParameter=ubuntu.net.established,ss -tan | grep ESTABLISHED | wc -l
UserParameter=ubuntu.net.listening,ss -tln | grep LISTEN | wc -l
UserParameter=ubuntu.disk.temp[*],smartctl -A /dev/$1 2>/dev/null | grep Temperature_Celsius | awk '{print $10}' || echo 0
UserParameter=ubuntu.disk.smart[*],smartctl -H /dev/$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
CUSTOM_EOF

cp /etc/zabbix/zabbix_agent2.d/custom_ubuntu.conf /etc/zabbix/zabbix_agentd.d/ 2>/dev/null || true

# Configure sudo
cat > /etc/sudoers.d/zabbix << EOF
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix

# Restart agent
systemctl restart zabbix-agent2 2>/dev/null || systemctl restart zabbix-agent
systemctl enable zabbix-agent2 2>/dev/null || systemctl enable zabbix-agent

echo "Installation completed"
INSTALLER_EOF
                fi
                
                # Run installer
                echo "Installing Zabbix agent..."
                ssh "$SSH_USER@$ip" "chmod +x /tmp/install_auto_shared.sh && sudo ZABBIX_SERVER=$ZABBIX_SERVER HOSTNAME=$name /tmp/install_auto_shared.sh"
                
                # Verify
                if ssh "$SSH_USER@$ip" "systemctl is-active --quiet zabbix-agent2 || systemctl is-active --quiet zabbix-agent"; then
                    echo -e "${GREEN}✓ Agent installed and running${NC}"
                    
                    # Test a custom metric
                    echo "Testing custom metrics..."
                    ssh "$SSH_USER@$ip" "zabbix_get -s localhost -k ubuntu.cpu.temp 2>/dev/null || echo 'Metric will be available shortly'"
                    
                    if [ "$TEMPLATE_DEPLOYED" = false ]; then
                        echo ""
                        echo -e "${YELLOW}IMPORTANT: Import the shared template to Zabbix:${NC}"
                        echo "  File: Template_Ubuntu_Shared.json"
                        echo "  This template works for ALL Ubuntu servers"
                        TEMPLATE_DEPLOYED=true
                    fi
                else
                    echo -e "${RED}✗ Installation may have issues${NC}"
                fi
            else
                echo -e "${RED}✗ Cannot connect to $ip${NC}"
            fi
        done
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN} Deployment Complete${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Import Template_Ubuntu_Shared.json to Zabbix (only once!)"
        echo "2. Add hosts in Zabbix:"
        echo "   - Arc: IP 192.168.68.146, Template 'Template Ubuntu Shared'"
        echo "   - Cobalt: IP 192.168.70.35, Template 'Template Ubuntu Shared'"
        echo "3. Both servers will share the same template and metrics"
        ;;
        
    2)
        # Manual commands
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE} Manual Installation Commands${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${YELLOW}Step 1: Import shared template (ONCE only):${NC}"
        echo "  - Import Template_Ubuntu_Shared.json to Zabbix"
        echo ""
        echo -e "${YELLOW}Step 2: Install agent on each server:${NC}"
        echo ""
        
        for server_info in "${SERVERS[@]}"; do
            name="${server_info%%:*}"
            ip="${server_info##*:}"
            
            echo -e "${GREEN}For $name ($ip):${NC}"
            echo "----------------------------------------"
            echo "ssh root@$ip"
            echo ""
            echo "# Quick install command:"
            echo "curl -sSL [installer_url]/install_auto_shared.sh | \\"
            echo "  sudo ZABBIX_SERVER=$ZABBIX_SERVER HOSTNAME=$name bash"
            echo ""
            echo "# Or manual install:"
            echo "wget install_auto_shared.sh"
            echo "chmod +x install_auto_shared.sh"
            echo "sudo ZABBIX_SERVER=$ZABBIX_SERVER HOSTNAME=$name ./install_auto_shared.sh"
            echo ""
            echo "# Verify:"
            echo "systemctl status zabbix-agent2"
            echo "zabbix_get -s localhost -k ubuntu.cpu.temp"
            echo "----------------------------------------"
            echo ""
        done
        
        echo -e "${YELLOW}Step 3: Add hosts to Zabbix:${NC}"
        echo "  Both hosts use the same 'Template Ubuntu Shared'"
        ;;
        
    3)
        # Single server deployment
        echo ""
        echo "Select server:"
        i=1
        for server_info in "${SERVERS[@]}"; do
            name="${server_info%%:*}"
            ip="${server_info##*:}"
            echo "  $i) $name ($ip)"
            i=$((i+1))
        done
        read -p "Choice: " server_choice
        
        selected="${SERVERS[$((server_choice-1))]}"
        name="${selected%%:*}"
        ip="${selected##*:}"
        
        echo ""
        echo -e "${BLUE}Deploying to $name ($ip)...${NC}"
        read -p "SSH username: " SSH_USER
        
        ssh "$SSH_USER@$ip" "
            curl -sSL [installer_url]/install_auto_shared.sh | \
            sudo ZABBIX_SERVER=$ZABBIX_SERVER HOSTNAME=$name bash
        "
        ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE} Benefits of Shared Template${NC}"
echo -e "${BLUE}========================================${NC}"
echo "✓ Single template for all Ubuntu servers"
echo "✓ Consistent monitoring across all hosts"
echo "✓ Easy to update - change once, applies to all"
echo "✓ Reduced Zabbix database overhead"
echo "✓ Simplified management and maintenance"
echo ""
echo "All servers use these shared metrics:"
echo "  ubuntu.cpu.temp, ubuntu.mem.available, ubuntu.disk.*"
echo "  ubuntu.service.*, ubuntu.net.*, ubuntu.updates.*"