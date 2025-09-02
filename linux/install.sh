#!/bin/bash

# Rithm Zabbix Agent - Clean Installer
# Version: 5.0.0 - Streamlined
# Usage: curl -sSL [url]/install_clean.sh | sudo bash
# Or: ssh user@server "curl -sSL [url]/install_clean.sh | sudo bash"

set -euo pipefail

# Configuration
ZABBIX_SERVER="${ZABBIX_SERVER:-192.168.70.2}"
LOG_FILE="/var/log/zabbix/install.log"
INSTALL_DIR="$(pwd)"

# Create log directory early
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"; cleanup_on_failure; exit 1; }

# Cleanup function for failed installations
cleanup_on_failure() {
    log "Installation failed. Cleaning up..."
    
    # Stop and remove Zabbix services
    systemctl stop zabbix-agent2 2>/dev/null || true
    systemctl stop zabbix-agent 2>/dev/null || true
    systemctl disable zabbix-agent2 2>/dev/null || true
    systemctl disable zabbix-agent 2>/dev/null || true
    
    # Remove Zabbix packages
    apt-get remove --purge -y zabbix-agent2 zabbix-agent 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    
    # Remove Zabbix repository
    rm -f /etc/apt/sources.list.d/zabbix.list 2>/dev/null || true
    apt-get update -qq 2>/dev/null || true
    
    # Remove configuration files and directories
    rm -rf /etc/zabbix/ 2>/dev/null || true
    rm -rf /var/log/zabbix/ 2>/dev/null || true
    rm -rf /var/run/zabbix/ 2>/dev/null || true
    rm -f /etc/sudoers.d/zabbix 2>/dev/null || true
    
    # Remove installation files if we're in a git clone
    if [[ "$INSTALL_DIR" == *"zabbixAgent"* ]] && [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$(dirname "$INSTALL_DIR")"
        rm -rf "$INSTALL_DIR" 2>/dev/null || true
        log "Removed git clone directory: $INSTALL_DIR"
    fi
    
    log "Cleanup completed."
}

# Check root
[[ $EUID -eq 0 ]] || error "This script must be run as root"

# Kill any existing zabbix processes that might be using port 10050
log "Checking for existing Zabbix processes..."
pkill -f zabbix_agent 2>/dev/null || true
pkill -f zabbix_agent2 2>/dev/null || true
sleep 2  # Give processes time to terminate

# Interactive hostname configuration
if [ -z "${ZABBIX_HOSTNAME:-}" ]; then
    # Only ask interactively if running with a terminal
    if [ -t 0 ]; then
        echo -e "\n${BLUE}=== Zabbix Agent Configuration ===${NC}"
        echo -e "${BLUE}Enter hostname for this agent${NC} [default: $(hostname)]: "
        read -r USER_HOSTNAME
        HOSTNAME="${USER_HOSTNAME:-$(hostname)}"
    else
        HOSTNAME="$(hostname)"
    fi
else
    HOSTNAME="$ZABBIX_HOSTNAME"
fi

# Create log directory
mkdir -p "$(dirname $LOG_FILE)" 2>/dev/null || true

log "=============================================="
log " Rithm Zabbix Agent - Clean Install v5.0.0"
log "=============================================="
log "Server: $ZABBIX_SERVER"
log "Hostname: $HOSTNAME (as configured in Zabbix)"

# Detect system
OS_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
case "$OS_VERSION" in
    24.04) ZABBIX_VERSION="7.0"; REPO_VERSION="22.04" ;;
    22.04) ZABBIX_VERSION="6.4"; REPO_VERSION="22.04" ;;
    20.04) ZABBIX_VERSION="6.0"; REPO_VERSION="20.04" ;;
    *) ZABBIX_VERSION="6.0"; REPO_VERSION="22.04"; warning "Unknown Ubuntu version, using defaults" ;;
esac
log "Ubuntu $OS_VERSION detected, using Zabbix $ZABBIX_VERSION"

# Install repository
log "Installing Zabbix repository..."
wget -q -O /tmp/zabbix-release.deb \
    "https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${REPO_VERSION}_all.deb" \
    || error "Failed to download Zabbix repository"

dpkg -i /tmp/zabbix-release.deb >/dev/null 2>&1
apt-get update -qq || error "Failed to update package list"
success "Repository installed"

# Install packages
log "Installing Zabbix agent and monitoring tools..."
apt-get install -qq -y zabbix-agent2 lm-sensors smartmontools sysstat jq || \
    { apt-get install -qq -y zabbix-agent lm-sensors smartmontools sysstat jq || error "Failed to install packages"; }

# Detect installed agent
if systemctl list-unit-files 2>/dev/null | grep -q zabbix-agent2; then
    AGENT_SERVICE="zabbix-agent2"
    AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
    CUSTOM_DIR="/etc/zabbix/zabbix_agent2.d"
else
    AGENT_SERVICE="zabbix-agent"
    AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
    CUSTOM_DIR="/etc/zabbix/zabbix_agentd.conf.d"
fi
success "Installed $AGENT_SERVICE"

# Create necessary directories with proper permissions
mkdir -p /etc/zabbix 2>/dev/null || true
mkdir -p "$CUSTOM_DIR" 2>/dev/null || true
mkdir -p /var/log/zabbix 2>/dev/null || true
mkdir -p /var/run/zabbix 2>/dev/null || true

# Set proper ownership for zabbix user
if id "zabbix" &>/dev/null; then
    chown -R zabbix:zabbix /var/log/zabbix
    chown -R zabbix:zabbix /var/run/zabbix
    chmod 755 /var/log/zabbix
    chmod 755 /var/run/zabbix
fi

# Configure sensors
log "Configuring hardware sensors..."
yes | sensors-detect >/dev/null 2>&1 || warning "Sensor configuration may have failed"

# Create main configuration
log "Creating agent configuration..."

# Check if using agent2 or older agent for config compatibility
if [[ "$AGENT_SERVICE" == "zabbix-agent2" ]]; then
    # Agent2 configuration (supports AllowKey/DenyKey)
    cat > "$AGENT_CONFIG" << EOF
# Rithm Zabbix Agent Configuration
# Generated: $(date)
# Host: $HOSTNAME

Server=$ZABBIX_SERVER
ServerActive=$ZABBIX_SERVER:10051
Hostname=$HOSTNAME

# Performance
Timeout=30
BufferSize=100
BufferSend=5

# Logging
LogFile=/var/log/zabbix/$(basename $AGENT_CONFIG .conf).log
LogFileSize=10
DebugLevel=3

# Security
AllowKey=system.run[*]
DenyKey=system.run[rm *]
DenyKey=system.run[shutdown *]

# Include custom parameters
Include=$CUSTOM_DIR/*.conf
EOF
else
    # Older agent configuration (doesn't support AllowKey/DenyKey)
    cat > "$AGENT_CONFIG" << EOF
# Rithm Zabbix Agent Configuration
# Generated: $(date)
# Host: $HOSTNAME

Server=$ZABBIX_SERVER
ServerActive=$ZABBIX_SERVER:10051
Hostname=$HOSTNAME

# Performance
Timeout=30
BufferSize=100
BufferSend=5

# Logging
LogFile=/var/log/zabbix/$(basename $AGENT_CONFIG .conf).log
LogFileSize=10
DebugLevel=3

# Security - using older format
EnableRemoteCommands=1
LogRemoteCommands=1

# Include custom parameters
Include=$CUSTOM_DIR/*.conf
EOF
fi

# Custom directory creation is already done above

# Create streamlined custom parameters with consistent naming
log "Creating custom monitoring parameters..."
cat > "$CUSTOM_DIR/rithm_custom.conf" << 'EOF'
# Rithm Custom Parameters - Clean v5.0.0
# All parameters use consistent custom.* naming

### SYSTEM MONITORING ###
UserParameter=custom.system.uptime,uptime | awk '{print $3}' | sed 's/,//'
UserParameter=custom.system.kernel,uname -r
UserParameter=custom.system.reboot_required,test -f /var/run/reboot-required && echo 1 || echo 0

### CPU MONITORING ###
UserParameter=custom.cpu.temperature,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 | grep -oE '[0-9]+\.[0-9]+' || echo 0
UserParameter=custom.cpu.cores,nproc
UserParameter=custom.cpu.load_1min,uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//'
UserParameter=custom.cpu.load_5min,uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//'

### MEMORY MONITORING ###
UserParameter=custom.memory.available,free -b | awk '/^Mem:/{print $7}'
UserParameter=custom.memory.used_percent,free | awk '/^Mem:/{printf "%.2f", ($3/$2)*100}'
UserParameter=custom.memory.swap_used,free -b | awk '/^Swap:/{print $3}'

### DISK MONITORING ###
UserParameter=custom.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=custom.disk.root_usage,df / | awk 'NR==2{print $5}' | sed 's/%//'
UserParameter=custom.disk.temperature[*],smartctl -A /dev/$1 2>/dev/null | grep Temperature_Celsius | awk '{print $10}' || echo 0
UserParameter=custom.disk.smart_status[*],smartctl -H /dev/$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
UserParameter=custom.disk.io_wait,iostat -x 1 1 | tail -n +4 | awk '{sum+=$10} END {printf "%.2f", sum/NR}' || echo 0

### NETWORK MONITORING ###
UserParameter=custom.network.connections_established,ss -tan | grep ESTABLISHED | wc -l
UserParameter=custom.network.connections_listening,ss -tln | grep LISTEN | wc -l
UserParameter=custom.network.connections_timewait,ss -tan | grep TIME-WAIT | wc -l

### SERVICE MONITORING ###
UserParameter=custom.service.status[*],systemctl is-active $1 2>/dev/null || echo "inactive"
UserParameter=custom.service.count_running,systemctl list-units --type=service --state=running --no-pager | grep -c "\.service"
UserParameter=custom.service.count_failed,systemctl list-units --type=service --state=failed --no-pager | grep -c "\.service"

### PROCESS MONITORING ###
UserParameter=custom.process.top_cpu,ps aux | sort -nrk 3,3 | head -1 | awk '{print $2":"$3":"$11}'
UserParameter=custom.process.top_memory,ps aux | sort -nrk 4,4 | head -1 | awk '{print $2":"$4":"$11}'
UserParameter=custom.process.zombie_count,ps aux | awk '$8 ~ /^Z/ {count++} END {print count+0}'
UserParameter=custom.process.total_count,ps aux | wc -l

### LOGIN MONITORING ###
UserParameter=custom.login.failed_last_hour,grep "authentication failure" /var/log/auth.log 2>/dev/null | grep "$(date --date='1 hour ago' '+%b %d %H')" | wc -l || echo 0
UserParameter=custom.login.successful_last_hour,grep "Accepted" /var/log/auth.log 2>/dev/null | grep "$(date --date='1 hour ago' '+%b %d %H')" | wc -l || echo 0
UserParameter=custom.login.last_user,last -n 1 | head -1 | awk '{print $1}' || echo "none"
UserParameter=custom.login.current_users,who | wc -l

### SECURITY MONITORING ###
UserParameter=custom.security.updates_available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=custom.security.updates_security,apt list --upgradable 2>/dev/null | grep -c security || echo 0
UserParameter=custom.security.sudo_attempts,grep "sudo:" /var/log/auth.log 2>/dev/null | grep "$(date '+%b %d')" | wc -l || echo 0

### LOG MONITORING ###
UserParameter=custom.log.auth_errors,grep -iE "error|fail|denied" /var/log/auth.log 2>/dev/null | tail -100 | wc -l || echo 0
UserParameter=custom.log.syslog_errors,grep -iE "error|critical|fail" /var/log/syslog 2>/dev/null | tail -100 | wc -l || echo 0
UserParameter=custom.log.kern_errors,grep -iE "error|fail|critical" /var/log/kern.log 2>/dev/null | tail -100 | wc -l || echo 0

### DOCKER MONITORING (if available) ###
UserParameter=custom.docker.containers_running,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=custom.docker.containers_total,docker ps -aq 2>/dev/null | wc -l || echo 0
UserParameter=custom.docker.images_count,docker images -q 2>/dev/null | wc -l || echo 0

### DISCOVERY RULES ###
UserParameter=custom.discovery.disks,lsblk -J -o NAME,TYPE | jq -c '.blockdevices | map(select(.type=="disk")) | map({"{#DISKNAME}": .name})'
UserParameter=custom.discovery.services,systemctl list-unit-files --type=service --state=enabled --no-pager | tail -n +2 | head -n -2 | awk '{print $1}' | sed 's/.service$//' | jq -R -s -c 'split("\n")[:-1] | map({"{#SERVICE}": .})'
UserParameter=custom.discovery.network_interfaces,ip -j link show | jq -c '[.[] | select(.operstate == "UP" and .ifname != "lo") | {"{#INTERFACE}": .ifname}]'
EOF

# Set permissions
chown -R zabbix:zabbix "$AGENT_CONFIG" "$CUSTOM_DIR" 2>/dev/null || true
chmod 640 "$AGENT_CONFIG" "$CUSTOM_DIR"/*.conf 2>/dev/null || true

# Configure sudo permissions
log "Configuring sudo permissions..."
cat > /etc/sudoers.d/zabbix << 'EOF'
# Zabbix monitoring permissions
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl status *, /usr/bin/systemctl is-active *
zabbix ALL=(ALL) NOPASSWD: /usr/sbin/smartctl, /usr/bin/sensors, /usr/bin/iostat
zabbix ALL=(ALL) NOPASSWD: /usr/bin/apt list, /usr/bin/docker ps, /usr/bin/docker images
zabbix ALL=(ALL) NOPASSWD: /bin/grep, /bin/cat /var/log/*, /usr/bin/tail /var/log/*
Defaults:zabbix !requiretty
EOF
chmod 440 /etc/sudoers.d/zabbix

# Start and enable agent
log "Starting Zabbix agent..."
systemctl daemon-reload
systemctl restart "$AGENT_SERVICE"
systemctl enable "$AGENT_SERVICE"

# Test installation
sleep 3
if systemctl is-active --quiet "$AGENT_SERVICE"; then
    success "Agent is running ($AGENT_SERVICE)"
    
    # Test basic connectivity
    if command -v zabbix_get >/dev/null && timeout 5 zabbix_get -s localhost -k agent.ping 2>/dev/null | grep -q "1"; then
        success "Agent responds to ping"
    else
        warning "Agent ping test inconclusive (may need zabbix-get package)"
    fi
    
    # Test a few custom parameters
    for metric in "custom.cpu.temperature" "custom.memory.available" "custom.disk.count"; do
        if command -v zabbix_get >/dev/null; then
            result=$(timeout 3 zabbix_get -s localhost -k "$metric" 2>/dev/null || echo "test_failed")
            if [[ "$result" != "test_failed" && "$result" != "" ]]; then
                success "$metric: $result"
            else
                warning "$metric: Not ready yet"
            fi
        fi
    done
else
    log "Agent failed to start. Checking logs..."
    journalctl -u "$AGENT_SERVICE" -n 10 --no-pager | tee -a "$LOG_FILE"
    error "Agent failed to start. Check logs above."
fi

# Installation summary
log "=============================================="
success "Rithm Zabbix Agent Installation Complete!"
log "=============================================="
log "Host: $HOSTNAME"
log "Server: $ZABBIX_SERVER"
log "Agent: $AGENT_SERVICE"
log "Config: $AGENT_CONFIG"
log "Custom Parameters: $CUSTOM_DIR/rithm_custom.conf"
log ""
log "Next steps:"
log "1. Import the Rithm template to your Zabbix server"
log "2. Add this host with hostname '$HOSTNAME'"
log "3. Test from Zabbix server:"
log "   zabbix_get -s $(hostname -I | awk '{print $1}') -k custom.cpu.temperature"
log ""
log "All custom parameters use 'custom.*' naming for consistency"

# Generate template summary for admin
cat > "/tmp/rithm_template_info_$(hostname).txt" << EOF
Rithm Zabbix Template Information
Generated: $(date)
Hostname: $HOSTNAME
IP: $(hostname -I | awk '{print $1}')

Custom Parameters Available:
- custom.system.* (uptime, kernel, reboot_required)
- custom.cpu.* (temperature, cores, load_*)
- custom.memory.* (available, used_percent, swap_used)
- custom.disk.* (count, root_usage, temperature[*], smart_status[*])
- custom.network.* (connections_*)
- custom.service.* (status[*], count_*)
- custom.process.* (top_*, zombie_count, total_count)
- custom.login.* (failed_*, successful_*, last_user)
- custom.security.* (updates_*, sudo_attempts)
- custom.log.* (*_errors)
- custom.docker.* (containers_*, images_count)

Discovery Rules:
- custom.discovery.disks
- custom.discovery.services
- custom.discovery.network_interfaces

Template file will be generated separately.
EOF

log "Template information saved to: /tmp/rithm_template_info_$(hostname).txt"
success "Installation completed successfully!"