# PowerShell script to deploy Zabbix agents to Arc and Cobalt from Windows
# Run this from PowerShell as Administrator

param(
    [string]$SSHUser = "root",
    [switch]$TestOnly
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Zabbix Agent Deployment for Arc & Cobalt" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Zabbix Server: 192.168.70.2" -ForegroundColor Green
Write-Host "Target Servers:" -ForegroundColor Green
Write-Host "  - Arc (192.168.68.146)" -ForegroundColor Green
Write-Host "  - Cobalt (192.168.70.35)" -ForegroundColor Green
Write-Host ""

$servers = @(
    @{Name="Arc"; IP="192.168.68.146"},
    @{Name="Cobalt"; IP="192.168.70.35"}
)

# Test connectivity first
Write-Host "Testing connectivity..." -ForegroundColor Yellow
foreach ($server in $servers) {
    $ping = Test-Connection -ComputerName $server.IP -Count 1 -Quiet
    if ($ping) {
        Write-Host "✓ $($server.Name) ($($server.IP)) - Reachable" -ForegroundColor Green
    } else {
        Write-Host "✗ $($server.Name) ($($server.IP)) - Not reachable" -ForegroundColor Red
    }
}

if ($TestOnly) {
    Write-Host "Test complete. Exiting." -ForegroundColor Yellow
    exit
}

Write-Host ""
Write-Host "Choose deployment method:" -ForegroundColor Yellow
Write-Host "1) Use SSH from this Windows machine (requires ssh.exe or PuTTY)"
Write-Host "2) Show commands to run manually on each server"
Write-Host "3) Generate individual installer files for copy/paste"

$choice = Read-Host "Enter choice (1-3)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "SSH Deployment selected" -ForegroundColor Cyan
        
        # Check if SSH is available
        $sshAvailable = $false
        try {
            $sshTest = ssh -V 2>&1
            $sshAvailable = $true
            Write-Host "✓ SSH client found: $sshTest" -ForegroundColor Green
        } catch {
            Write-Host "✗ SSH client not found" -ForegroundColor Red
        }
        
        if (-not $sshAvailable) {
            Write-Host "SSH not available. Please install OpenSSH or use option 2/3." -ForegroundColor Red
            exit
        }
        
        Write-Host "SSH Username: $SSHUser" -ForegroundColor Yellow
        Write-Host ""
        
        foreach ($server in $servers) {
            Write-Host "========================================" -ForegroundColor Blue
            Write-Host "Deploying to $($server.Name) ($($server.IP))" -ForegroundColor Blue
            Write-Host "========================================" -ForegroundColor Blue
            
            # Create installation script
            $installScript = @"
#!/bin/bash
set -e
echo "Installing Zabbix Agent for $($server.Name)..."

# Get Ubuntu version
OS_VERSION=`$(lsb_release -rs)
case "`$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="`$OS_VERSION" ;;
esac

# Install repository
wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/`${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_`${ZABBIX_VERSION}-4+ubuntu`${REPO_VERSION}_all.deb"
dpkg -i /tmp/zabbix-release.deb
apt-get update -q

# Install agent
apt-get install -qq -y zabbix-agent2 lm-sensors smartmontools || apt-get install -qq -y zabbix-agent lm-sensors smartmontools

# Configure agent
if systemctl list-unit-files | grep -q zabbix-agent2; then
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
else
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.d"
fi

# Main config
cat > "`$AGENT_CONFIG" << EOF
Server=192.168.70.2
ServerActive=192.168.70.2:10051
Hostname=$($server.Name)
LogFile=/var/log/zabbix/`$(basename `$AGENT_CONFIG .conf).log
Include=`$CUSTOM_DIR/*.conf
EOF

# Custom parameters
mkdir -p "`$CUSTOM_DIR"
cat > "`$CUSTOM_DIR/ubuntu_shared.conf" << 'EOF'
UserParameter=ubuntu.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=ubuntu.mem.available,free -b | awk '/^Mem:/{print `$7}'
UserParameter=ubuntu.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=ubuntu.service.status[*],systemctl is-active `$1 2>/dev/null || echo "inactive"
UserParameter=ubuntu.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=ubuntu.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=ubuntu.updates.security,apt list --upgradable 2>/dev/null | grep -c security || echo 0
UserParameter=ubuntu.net.established,ss -tan | grep ESTABLISHED | wc -l
UserParameter=ubuntu.net.listening,ss -tln | grep LISTEN | wc -l
UserParameter=ubuntu.disk.temp[*],smartctl -A /dev/`$1 2>/dev/null | grep Temperature_Celsius | awk '{print `$10}' || echo 0
UserParameter=ubuntu.disk.smart[*],smartctl -H /dev/`$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
UserParameter=ubuntu.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0
UserParameter=ubuntu.uptime.days,uptime | awk '{print `$3}' | sed 's/,//'
UserParameter=ubuntu.kernel.version,uname -r
EOF

# Permissions and sudo
chown zabbix:zabbix "`$AGENT_CONFIG" "`$CUSTOM_DIR/ubuntu_shared.conf" 2>/dev/null || true
chmod 640 "`$AGENT_CONFIG" "`$CUSTOM_DIR/ubuntu_shared.conf" 2>/dev/null || true

cat > /etc/sudoers.d/zabbix << 'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix

# Configure sensors
yes | sensors-detect >/dev/null 2>&1 || true

# Restart agent
systemctl restart "`$AGENT_SERVICE"
systemctl enable "`$AGENT_SERVICE"

echo "$($server.Name) installation completed!"
sleep 2

# Test
if systemctl is-active --quiet "`$AGENT_SERVICE"; then
    echo "✓ Agent is running"
    zabbix_get -s localhost -k agent.ping 2>/dev/null && echo "✓ Agent responds"
    zabbix_get -s localhost -k ubuntu.cpu.temp 2>/dev/null && echo "✓ Custom metrics work"
else
    echo "✗ Agent issues detected"
fi
"@
            
            try {
                # Send script to server and execute
                Write-Host "Connecting to $($server.IP)..." -ForegroundColor Yellow
                $installScript | ssh "$SSHUser@$($server.IP)" "cat > /tmp/install_$($server.Name.ToLower()).sh && chmod +x /tmp/install_$($server.Name.ToLower()).sh && sudo /tmp/install_$($server.Name.ToLower()).sh"
                Write-Host "✓ $($server.Name) deployment completed" -ForegroundColor Green
            } catch {
                Write-Host "✗ Failed to deploy to $($server.Name): $_" -ForegroundColor Red
            }
            
            Write-Host ""
        }
        
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Deployment Summary" -ForegroundColor Green  
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Import Template_Ubuntu_Shared.json to Zabbix"
        Write-Host "2. Add Arc and Cobalt hosts with Template Ubuntu Shared"
        Write-Host "3. Test from Zabbix server:"
        Write-Host "   zabbix_get -s 192.168.68.146 -k agent.ping"
        Write-Host "   zabbix_get -s 192.168.70.35 -k ubuntu.cpu.temp"
    }
    
    "2" {
        Write-Host ""
        Write-Host "Manual Commands:" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($server in $servers) {
            Write-Host "=== For $($server.Name) ($($server.IP)) ===" -ForegroundColor Green
            Write-Host "ssh $SSHUser@$($server.IP)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "# Copy and paste this entire block:"
            Write-Host @"
sudo apt-get update
sudo apt-get install -y wget lsb-release

# Get Ubuntu version and set Zabbix version
OS_VERSION=`$(lsb_release -rs)
case "`$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="`$OS_VERSION" ;;
esac

# Install Zabbix repository
wget -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/`${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_`${ZABBIX_VERSION}-4+ubuntu`${REPO_VERSION}_all.deb"
sudo dpkg -i /tmp/zabbix-release.deb
sudo apt-get update

# Install agent and tools
sudo apt-get install -y zabbix-agent2 lm-sensors smartmontools || sudo apt-get install -y zabbix-agent lm-sensors smartmontools

# Configure based on installed agent
if systemctl list-unit-files | grep -q zabbix-agent2; then
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
    SERVICE="zabbix-agent2"
else
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.d"  
    SERVICE="zabbix-agent"
fi

# Configure main agent
sudo tee `$AGENT_CONFIG > /dev/null << EOF
Server=192.168.70.2
ServerActive=192.168.70.2:10051
Hostname=$($server.Name)
LogFile=/var/log/zabbix/`$(basename `$AGENT_CONFIG .conf).log
Include=`$CUSTOM_DIR/*.conf
EOF

# Add custom parameters
sudo mkdir -p `$CUSTOM_DIR
sudo tee `$CUSTOM_DIR/ubuntu_shared.conf > /dev/null << 'EOF'
UserParameter=ubuntu.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=ubuntu.mem.available,free -b | awk '/^Mem:/{print `$7}'
UserParameter=ubuntu.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=ubuntu.service.status[*],systemctl is-active `$1 2>/dev/null || echo "inactive"
UserParameter=ubuntu.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=ubuntu.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=ubuntu.net.established,ss -tan | grep ESTABLISHED | wc -l
UserParameter=ubuntu.net.listening,ss -tln | grep LISTEN | wc -l
UserParameter=ubuntu.disk.temp[*],smartctl -A /dev/`$1 2>/dev/null | grep Temperature_Celsius | awk '{print `$10}' || echo 0
UserParameter=ubuntu.disk.smart[*],smartctl -H /dev/`$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
EOF

# Set up sudo permissions
sudo tee /etc/sudoers.d/zabbix > /dev/null << 'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF

# Configure sensors
sudo yes | sudo sensors-detect || true

# Start agent
sudo systemctl restart `$SERVICE
sudo systemctl enable `$SERVICE

# Test
systemctl status `$SERVICE
zabbix_get -s localhost -k agent.ping
zabbix_get -s localhost -k ubuntu.cpu.temp
"@
            Write-Host ""
            Write-Host ""
        }
    }
    
    "3" {
        Write-Host "Generating installer files..." -ForegroundColor Cyan
        
        foreach ($server in $servers) {
            $fileName = "install_$($server.Name.ToLower())_$(Get-Date -Format 'yyyyMMdd').sh"
            
            $content = @"
#!/bin/bash
# Zabbix Agent Installer for $($server.Name)
# Generated: $(Get-Date)

set -e
echo "Installing Zabbix Agent for $($server.Name)..."

# Auto-detect Ubuntu version
OS_VERSION=`$(lsb_release -rs)
case "`$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="`$OS_VERSION" ;;
esac

echo "Ubuntu `$OS_VERSION detected, using Zabbix `$ZABBIX_VERSION"

# Install Zabbix repository
wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/`${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_`${ZABBIX_VERSION}-4+ubuntu`${REPO_VERSION}_all.deb"
dpkg -i /tmp/zabbix-release.deb
apt-get update -q

# Install packages
apt-get install -qq -y zabbix-agent2 lm-sensors smartmontools || apt-get install -qq -y zabbix-agent lm-sensors smartmontools

# Determine which agent was installed
if systemctl list-unit-files | grep -q zabbix-agent2; then
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2" 
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
else
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.d"
fi

echo "Using `$AGENT_SERVICE with config `$AGENT_CONFIG"

# Configure main agent
cat > "`$AGENT_CONFIG" << EOF
# Zabbix Agent Configuration for $($server.Name)
Server=192.168.70.2
ServerActive=192.168.70.2:10051
Hostname=$($server.Name)
LogFile=/var/log/zabbix/`$(basename `$AGENT_CONFIG .conf).log
Include=`$CUSTOM_DIR/*.conf
EOF

# Create custom parameters for shared template
mkdir -p "`$CUSTOM_DIR"
cat > "`$CUSTOM_DIR/ubuntu_shared.conf" << 'EOF'
# Shared Ubuntu Template Parameters
# These work with Template_Ubuntu_Shared.json

UserParameter=ubuntu.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=ubuntu.mem.available,free -b | awk '/^Mem:/{print `$7}'
UserParameter=ubuntu.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=ubuntu.service.status[*],systemctl is-active `$1 2>/dev/null || echo "inactive"
UserParameter=ubuntu.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=ubuntu.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=ubuntu.updates.security,apt list --upgradable 2>/dev/null | grep -c security || echo 0
UserParameter=ubuntu.net.established,ss -tan | grep ESTABLISHED | wc -l  
UserParameter=ubuntu.net.listening,ss -tln | grep LISTEN | wc -l
UserParameter=ubuntu.disk.temp[*],smartctl -A /dev/`$1 2>/dev/null | grep Temperature_Celsius | awk '{print `$10}' || echo 0
UserParameter=ubuntu.disk.smart[*],smartctl -H /dev/`$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
UserParameter=ubuntu.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0
UserParameter=ubuntu.uptime.days,uptime | awk '{print `$3}' | sed 's/,//'
UserParameter=ubuntu.kernel.version,uname -r
EOF

# Set permissions
chown zabbix:zabbix "`$AGENT_CONFIG" "`$CUSTOM_DIR/ubuntu_shared.conf" 2>/dev/null || true
chmod 640 "`$AGENT_CONFIG" "`$CUSTOM_DIR/ubuntu_shared.conf" 2>/dev/null || true

# Configure sudo for zabbix user
cat > /etc/sudoers.d/zabbix << 'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix

# Configure sensors
echo "Configuring sensors..."
yes | sensors-detect >/dev/null 2>&1 || true

# Restart and enable agent
systemctl restart "`$AGENT_SERVICE"
systemctl enable "`$AGENT_SERVICE"

echo ""
echo "========================================" 
echo "$($server.Name) Zabbix Agent Installation Complete!"
echo "========================================"
echo "Agent: `$AGENT_SERVICE"
echo "Config: `$AGENT_CONFIG"
echo "Custom params: `$CUSTOM_DIR/ubuntu_shared.conf"
echo ""

# Test installation
if systemctl is-active --quiet "`$AGENT_SERVICE"; then
    echo "✓ Agent is running"
    if zabbix_get -s localhost -k agent.ping >/dev/null 2>&1; then
        echo "✓ Agent responds to ping"
    else
        echo "⚠ Agent not responding to ping yet (may need a moment)"
    fi
    
    if zabbix_get -s localhost -k ubuntu.cpu.temp >/dev/null 2>&1; then
        echo "✓ Custom ubuntu.* metrics working"
    else
        echo "⚠ Custom metrics not ready yet"
    fi
else
    echo "✗ Agent service issues detected"
    systemctl status "`$AGENT_SERVICE"
fi

echo ""
echo "Next steps:"
echo "1. Import Template_Ubuntu_Shared.json to your Zabbix server"
echo "2. Add this host ($($server.Name)) to Zabbix with IP $($server.IP)"
echo "3. Assign 'Template Ubuntu Shared' to this host"
echo "4. Test from Zabbix server: zabbix_get -s $($server.IP) -k ubuntu.cpu.temp"
"@
            
            $content | Out-File -FilePath $fileName -Encoding UTF8
            Write-Host "✓ Created $fileName" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "1. Copy the .sh files to each respective server"
        Write-Host "2. Run: chmod +x install_*.sh && sudo ./install_*.sh"
    }
    
    default {
        Write-Host "Invalid choice" -ForegroundColor Red
    }
}