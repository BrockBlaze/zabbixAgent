# 🚀 DEPLOY ZABBIX AGENTS TO ARC & COBALT - READY TO RUN!

## ✅ Connectivity Test Results:
- **Arc (192.168.68.146)**: ✓ Reachable (1ms response)  
- **Cobalt (192.168.70.35)**: ✓ Reachable (<1ms response)

## 📋 DEPLOYMENT COMMANDS - COPY & PASTE READY

### 🔧 Step 1: Deploy to Arc (192.168.68.146)

SSH to Arc and run this complete block:

```bash
ssh root@192.168.68.146
```

```bash
# === ARC INSTALLATION SCRIPT ===
set -e
echo "Installing Zabbix Agent for Arc..."

# Auto-detect Ubuntu version and set Zabbix version
OS_VERSION=$(lsb_release -rs)
case "$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="$OS_VERSION" ;;
esac

echo "Ubuntu $OS_VERSION detected, using Zabbix $ZABBIX_VERSION"

# Install Zabbix repository
wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${REPO_VERSION}_all.deb"
sudo dpkg -i /tmp/zabbix-release.deb
sudo apt-get update -q

# Install agent and monitoring tools
sudo apt-get install -qq -y zabbix-agent2 lm-sensors smartmontools || sudo apt-get install -qq -y zabbix-agent lm-sensors smartmontools

# Auto-detect which agent was installed
if systemctl list-unit-files | grep -q zabbix-agent2; then
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
else
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.d"
fi

echo "Using $AGENT_SERVICE with config $AGENT_CONFIG"

# Configure main agent file
sudo tee $AGENT_CONFIG > /dev/null << 'EOF'
# Zabbix Agent Configuration for Arc
Server=192.168.70.2
ServerActive=192.168.70.2:10051
Hostname=Arc
LogFile=/var/log/zabbix/zabbix_agent.log
Include=/etc/zabbix/zabbix_agent*.d/*.conf
EOF

# Create shared custom parameters directory
sudo mkdir -p $CUSTOM_DIR

# Create shared Ubuntu template parameters
sudo tee $CUSTOM_DIR/ubuntu_shared.conf > /dev/null << 'EOF'
# Shared Ubuntu Template Parameters - Work with ALL Ubuntu servers
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
UserParameter=ubuntu.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0
UserParameter=ubuntu.uptime.days,uptime | awk '{print $3}' | sed 's/,//'
UserParameter=ubuntu.kernel.version,uname -r
EOF

# Set proper permissions
sudo chown zabbix:zabbix $AGENT_CONFIG $CUSTOM_DIR/ubuntu_shared.conf 2>/dev/null || true
sudo chmod 640 $AGENT_CONFIG $CUSTOM_DIR/ubuntu_shared.conf 2>/dev/null || true

# Configure sudo permissions for zabbix user
sudo tee /etc/sudoers.d/zabbix > /dev/null << 'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
sudo chmod 440 /etc/sudoers.d/zabbix

# Configure hardware sensors
echo "Configuring sensors..."
sudo yes | sudo sensors-detect >/dev/null 2>&1 || true

# Restart and enable Zabbix agent
sudo systemctl restart $AGENT_SERVICE
sudo systemctl enable $AGENT_SERVICE

echo ""
echo "========================================" 
echo "Arc Zabbix Agent Installation Complete!"
echo "========================================"

# Test the installation
sleep 3
if sudo systemctl is-active --quiet $AGENT_SERVICE; then
    echo "✓ Agent service is running"
    
    # Test basic connectivity
    if zabbix_get -s localhost -k agent.ping >/dev/null 2>&1; then
        echo "✓ Agent responds to ping"
    else
        echo "⚠ Agent not responding to ping yet"
    fi
    
    # Test custom metrics
    if zabbix_get -s localhost -k ubuntu.cpu.temp >/dev/null 2>&1; then
        echo "✓ Custom ubuntu.* metrics working"
    else
        echo "⚠ Custom metrics may need a moment to initialize"
    fi
else
    echo "✗ Agent service issues"
    sudo systemctl status $AGENT_SERVICE
fi

echo ""
echo "Arc is ready! Ubuntu shared template metrics available."
```

---

### 🔧 Step 2: Deploy to Cobalt (192.168.70.35)

SSH to Cobalt and run this complete block:

```bash
ssh root@192.168.70.35
```

```bash
# === COBALT INSTALLATION SCRIPT ===
set -e
echo "Installing Zabbix Agent for Cobalt..."

# Auto-detect Ubuntu version and set Zabbix version  
OS_VERSION=$(lsb_release -rs)
case "$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="$OS_VERSION" ;;
esac

echo "Ubuntu $OS_VERSION detected, using Zabbix $ZABBIX_VERSION"

# Install Zabbix repository
wget -q -O /tmp/zabbix-release.deb "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${REPO_VERSION}_all.deb"
sudo dpkg -i /tmp/zabbix-release.deb
sudo apt-get update -q

# Install agent and monitoring tools
sudo apt-get install -qq -y zabbix-agent2 lm-sensors smartmontools || sudo apt-get install -qq -y zabbix-agent lm-sensors smartmontools

# Auto-detect which agent was installed
if systemctl list-unit-files | grep -q zabbix-agent2; then
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    AGENT_SERVICE="zabbix-agent2"
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
else
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    AGENT_SERVICE="zabbix-agent"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.d"
fi

echo "Using $AGENT_SERVICE with config $AGENT_CONFIG"

# Configure main agent file
sudo tee $AGENT_CONFIG > /dev/null << 'EOF'
# Zabbix Agent Configuration for Cobalt
Server=192.168.70.2
ServerActive=192.168.70.2:10051
Hostname=Cobalt
LogFile=/var/log/zabbix/zabbix_agent.log
Include=/etc/zabbix/zabbix_agent*.d/*.conf
EOF

# Create shared custom parameters directory
sudo mkdir -p $CUSTOM_DIR

# Create shared Ubuntu template parameters (IDENTICAL to Arc)
sudo tee $CUSTOM_DIR/ubuntu_shared.conf > /dev/null << 'EOF'
# Shared Ubuntu Template Parameters - Work with ALL Ubuntu servers
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
UserParameter=ubuntu.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0
UserParameter=ubuntu.uptime.days,uptime | awk '{print $3}' | sed 's/,//'
UserParameter=ubuntu.kernel.version,uname -r
EOF

# Set proper permissions
sudo chown zabbix:zabbix $AGENT_CONFIG $CUSTOM_DIR/ubuntu_shared.conf 2>/dev/null || true
sudo chmod 640 $AGENT_CONFIG $CUSTOM_DIR/ubuntu_shared.conf 2>/dev/null || true

# Configure sudo permissions for zabbix user  
sudo tee /etc/sudoers.d/zabbix > /dev/null << 'EOF'
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
sudo chmod 440 /etc/sudoers.d/zabbix

# Configure hardware sensors
echo "Configuring sensors..."
sudo yes | sudo sensors-detect >/dev/null 2>&1 || true

# Restart and enable Zabbix agent
sudo systemctl restart $AGENT_SERVICE
sudo systemctl enable $AGENT_SERVICE

echo ""
echo "========================================" 
echo "Cobalt Zabbix Agent Installation Complete!"
echo "========================================"

# Test the installation
sleep 3
if sudo systemctl is-active --quiet $AGENT_SERVICE; then
    echo "✓ Agent service is running"
    
    # Test basic connectivity
    if zabbix_get -s localhost -k agent.ping >/dev/null 2>&1; then
        echo "✓ Agent responds to ping"
    else
        echo "⚠ Agent not responding to ping yet"
    fi
    
    # Test custom metrics
    if zabbix_get -s localhost -k ubuntu.cpu.temp >/dev/null 2>&1; then
        echo "✓ Custom ubuntu.* metrics working"
    else
        echo "⚠ Custom metrics may need a moment to initialize"
    fi
else
    echo "✗ Agent service issues"
    sudo systemctl status $AGENT_SERVICE
fi

echo ""
echo "Cobalt is ready! Ubuntu shared template metrics available."
```

---

## 🎯 Step 3: Configure Zabbix Server (192.168.70.2)

### A) Import the Shared Template (ONCE ONLY):
1. Copy `Template_Ubuntu_Shared.json` to your Zabbix server
2. Log into Zabbix web interface
3. Go to **Configuration → Templates**
4. Click **Import**
5. Select `Template_Ubuntu_Shared.json`
6. Click **Import**

### B) Add Hosts:
1. Go to **Configuration → Hosts**
2. Click **Create Host**

**For Arc:**
- Host name: `Arc`
- Groups: `Linux servers`
- Interfaces: Agent, `192.168.68.146`, Port `10050`
- Templates: Link `Template Ubuntu Shared`

**For Cobalt:**
- Host name: `Cobalt`
- Groups: `Linux servers` 
- Interfaces: Agent, `192.168.70.35`, Port `10050`
- Templates: Link `Template Ubuntu Shared`

---

## ✅ Step 4: Test from Zabbix Server

SSH to your Zabbix server (192.168.70.2) and run:

```bash
# Test basic connectivity
zabbix_get -s 192.168.68.146 -k agent.ping
zabbix_get -s 192.168.70.35 -k agent.ping

# Test custom shared metrics
zabbix_get -s 192.168.68.146 -k ubuntu.cpu.temp
zabbix_get -s 192.168.70.35 -k ubuntu.mem.available
zabbix_get -s 192.168.68.146 -k ubuntu.disk.count
zabbix_get -s 192.168.70.35 -k ubuntu.net.established
```

---

## 🎉 Benefits of This Setup:
- ✅ **Single template** for all Ubuntu servers
- ✅ **Identical configuration** on Arc and Cobalt  
- ✅ **Shared ubuntu.*** namespace for all metrics
- ✅ **Easy to add more servers** - just assign same template
- ✅ **Consistent monitoring** across your infrastructure

Both servers will now report the same metrics using the shared template!