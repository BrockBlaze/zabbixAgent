#!/bin/bash

# Zabbix Agent Auto-Installer with Shared Template
# Version: 5.0.0
# Features: Single shared template for all Ubuntu servers

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration defaults
LOG_FILE="/var/log/zabbix/auto_install.log"
CONFIG_SUMMARY="/tmp/zabbix_config_summary.txt"

# Default Zabbix server (can be overridden)
DEFAULT_ZABBIX_SERVER="${ZABBIX_SERVER:-192.168.70.2}"

# Functions
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# Create log directory
mkdir -p "$(dirname $LOG_FILE)"

log_info "==================================================="
log_info " Zabbix Agent Auto-Installer v5.0.0"
log_info " Shared Template Configuration"
log_info "==================================================="

# Auto-detect system
detect_system() {
    log_info "Auto-detecting system configuration..."
    
    OS_VERSION=$(lsb_release -rs)
    HOSTNAME="${HOSTNAME:-$(hostname -f)}"
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    log_info "Hostname: $HOSTNAME"
    log_info "IP Address: $IP_ADDRESS"
    log_info "Ubuntu Version: $OS_VERSION"
    
    # Determine Zabbix version based on Ubuntu version
    case "$OS_VERSION" in
        24.04)
            ZABBIX_VERSION="7.0"
            REPO_VERSION="22.04"
            ;;
        22.04)
            ZABBIX_VERSION="6.4"
            REPO_VERSION="22.04"
            ;;
        20.04)
            ZABBIX_VERSION="6.0"
            REPO_VERSION="20.04"
            ;;
        *)
            ZABBIX_VERSION="6.0"
            REPO_VERSION="${OS_VERSION}"
            log_warning "Non-standard Ubuntu version, using Zabbix $ZABBIX_VERSION"
            ;;
    esac
}

# Quick install with minimal prompts
quick_install() {
    if [ -z "${ZABBIX_SERVER_IP:-}" ]; then
        if [ -n "$DEFAULT_ZABBIX_SERVER" ] && [ "$DEFAULT_ZABBIX_SERVER" != "192.168.70.2" ]; then
            ZABBIX_SERVER_IP="$DEFAULT_ZABBIX_SERVER"
            log_info "Using Zabbix server from environment: $ZABBIX_SERVER_IP"
        else
            read -p "Enter Zabbix Server IP [default: $DEFAULT_ZABBIX_SERVER]: " -t 10 ZABBIX_SERVER_IP || ZABBIX_SERVER_IP=""
            ZABBIX_SERVER_IP="${ZABBIX_SERVER_IP:-$DEFAULT_ZABBIX_SERVER}"
        fi
    fi
}

# Install repository
install_repository() {
    log_info "Installing Zabbix repository..."
    
    rm -f /tmp/zabbix-release*.deb 2>/dev/null
    
    if [ "$ZABBIX_VERSION" = "7.0" ]; then
        REPO_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu${REPO_VERSION}_all.deb"
    else
        REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${REPO_VERSION}_all.deb"
    fi
    
    wget -q -O /tmp/zabbix-release.deb "$REPO_URL" || {
        log_error "Failed to download repository package"
        exit 1
    }
    
    dpkg -i /tmp/zabbix-release.deb >/dev/null 2>&1
    apt-get update -qq
    
    log_success "Repository installed"
}

# Install agent
install_agent() {
    log_info "Installing Zabbix agent..."
    
    if apt-get install -qq -y zabbix-agent2 2>/dev/null; then
        AGENT_TYPE="zabbix-agent2"
        AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
        AGENT_SERVICE="zabbix-agent2"
        log_success "Installed zabbix-agent2"
    elif apt-get install -qq -y zabbix-agent 2>/dev/null; then
        AGENT_TYPE="zabbix-agent"
        AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
        AGENT_SERVICE="zabbix-agent"
        log_success "Installed zabbix-agent"
    else
        log_error "Failed to install Zabbix agent"
        exit 1
    fi
    
    apt-get install -qq -y lm-sensors smartmontools nvme-cli sysstat 2>/dev/null || {
        log_warning "Some monitoring tools could not be installed"
    }
    
    yes | sensors-detect >/dev/null 2>&1 || true
}

# Configure agent with shared parameters
configure_agent() {
    log_info "Configuring Zabbix agent..."
    
    cp "$AGENT_CONFIG" "${AGENT_CONFIG}.backup.$(date +%Y%m%d)"
    
    cat > "$AGENT_CONFIG" << EOF
# Zabbix Agent Configuration - Shared Template
# Generated: $(date)
# Host: $HOSTNAME

# Server configuration
Server=$ZABBIX_SERVER_IP
ServerActive=$ZABBIX_SERVER_IP:10051
Hostname=$HOSTNAME

# Performance tuning
StartAgents=3
Timeout=30
BufferSize=100
BufferSend=5

# Logging
LogFile=/var/log/zabbix/${AGENT_TYPE}.log
LogFileSize=10
DebugLevel=3

# Security
AllowKey=system.run[*]
DenyKey=system.run[rm *]

# Include additional configs
Include=/etc/zabbix/zabbix_${AGENT_TYPE}.d/*.conf
EOF
    
    # Create shared custom parameters file
    cat > "/etc/zabbix/zabbix_${AGENT_TYPE}.d/custom_ubuntu.conf" << 'EOF'
# Shared Custom Parameters for Ubuntu Servers
# This file is identical across all Ubuntu agents

# System monitoring
UserParameter=ubuntu.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=ubuntu.mem.available,free -b | awk '/^Mem:/{print $7}'
UserParameter=ubuntu.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=ubuntu.uptime.days,uptime | awk '{print $3}' | sed 's/,//'

# Service monitoring
UserParameter=ubuntu.service.status[*],systemctl is-active $1 2>/dev/null || echo "inactive"
UserParameter=ubuntu.service.count,systemctl list-units --state=running --no-pager | grep -c "\.service"
UserParameter=ubuntu.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0

# Updates and security
UserParameter=ubuntu.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0
UserParameter=ubuntu.updates.security,apt list --upgradable 2>/dev/null | grep -c security || echo 0
UserParameter=ubuntu.kernel.version,uname -r
UserParameter=ubuntu.reboot.required,test -f /var/run/reboot-required && echo 1 || echo 0

# Process monitoring
UserParameter=ubuntu.proc.top.cpu,ps aux | sort -nrk 3,3 | head -1 | awk '{print $2":"$3":"$11}'
UserParameter=ubuntu.proc.top.mem,ps aux | sort -nrk 4,4 | head -1 | awk '{print $2":"$4":"$11}'
UserParameter=ubuntu.proc.zombies,ps aux | grep -c " Z "

# Network monitoring
UserParameter=ubuntu.net.established,ss -tan | grep ESTABLISHED | wc -l
UserParameter=ubuntu.net.listening,ss -tln | grep LISTEN | wc -l
UserParameter=ubuntu.net.timewait,ss -tan | grep TIME-WAIT | wc -l

# Disk monitoring
UserParameter=ubuntu.disk.temp[*],smartctl -A /dev/$1 2>/dev/null | grep Temperature_Celsius | awk '{print $10}' || echo 0
UserParameter=ubuntu.disk.smart[*],smartctl -H /dev/$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0
UserParameter=ubuntu.disk.io.util[*],iostat -x 1 2 | grep "^$1" | tail -1 | awk '{print $NF}'

# Log monitoring
UserParameter=ubuntu.log.auth.failed,grep "authentication failure" /var/log/auth.log 2>/dev/null | tail -100 | wc -l
UserParameter=ubuntu.log.syslog.errors,grep -iE "error|fail|critical" /var/log/syslog 2>/dev/null | tail -100 | wc -l

# Discovery rules support
UserParameter=ubuntu.disk.discovery,lsblk -J -o NAME,TYPE | jq -c '.blockdevices | map(select(.type=="disk")) | map({"{#DISKNAME}": .name})'
UserParameter=ubuntu.service.discovery,systemctl list-unit-files --type=service --state=enabled --no-pager | tail -n +2 | head -n -2 | awk '{print $1}' | jq -R -s -c 'split("\n")[:-1] | map({"{#SERVICE}": .})'
EOF
    
    # Set permissions
    chown zabbix:zabbix "$AGENT_CONFIG"
    chmod 640 "$AGENT_CONFIG"
    chown zabbix:zabbix "/etc/zabbix/zabbix_${AGENT_TYPE}.d/custom_ubuntu.conf"
    chmod 640 "/etc/zabbix/zabbix_${AGENT_TYPE}.d/custom_ubuntu.conf"
    
    # Configure sudo for zabbix
    cat > /etc/sudoers.d/zabbix << EOF
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt, /usr/sbin/iostat
Defaults:zabbix !requiretty
EOF
    chmod 440 /etc/sudoers.d/zabbix
    
    log_success "Agent configured with shared parameters"
}

# Start agent
start_agent() {
    log_info "Starting Zabbix agent..."
    
    systemctl daemon-reload
    systemctl restart "$AGENT_SERVICE"
    systemctl enable "$AGENT_SERVICE"
    
    sleep 3
    
    if systemctl is-active --quiet "$AGENT_SERVICE"; then
        log_success "Agent started successfully"
        
        if timeout 5 zabbix_get -s localhost -k agent.ping 2>/dev/null | grep -q "1"; then
            log_success "Agent responding to queries"
        else
            log_warning "Agent running but not responding to test queries yet"
        fi
    else
        log_error "Agent failed to start. Check: journalctl -u $AGENT_SERVICE"
        exit 1
    fi
}

# Generate summary
generate_summary() {
    cat > "$CONFIG_SUMMARY" << EOF
================================================================================
ZABBIX AGENT INSTALLATION SUMMARY
================================================================================
Date: $(date)
Host: $HOSTNAME
IP: $IP_ADDRESS

INSTALLATION DETAILS:
- Ubuntu Version: $OS_VERSION
- Zabbix Version: $ZABBIX_VERSION
- Agent Type: $AGENT_TYPE
- Config File: $AGENT_CONFIG
- Custom Parameters: /etc/zabbix/zabbix_${AGENT_TYPE}.d/custom_ubuntu.conf

SERVER CONFIGURATION:
- Zabbix Server: $ZABBIX_SERVER_IP
- Port: 10051 (active checks)

SHARED TEMPLATE METRICS (ubuntu.*):
All Ubuntu servers share these same metrics:

SYSTEM:
- ubuntu.cpu.temp - CPU temperature
- ubuntu.mem.available - Available memory
- ubuntu.disk.count - Number of disks
- ubuntu.uptime.days - System uptime in days
- ubuntu.kernel.version - Kernel version
- ubuntu.reboot.required - Reboot required flag

SERVICES:
- ubuntu.service.status[service] - Service status
- ubuntu.service.count - Running services count
- ubuntu.docker.containers - Docker containers

UPDATES:
- ubuntu.updates.available - Available updates
- ubuntu.updates.security - Security updates

PROCESSES:
- ubuntu.proc.top.cpu - Top CPU process
- ubuntu.proc.top.mem - Top memory process
- ubuntu.proc.zombies - Zombie processes

NETWORK:
- ubuntu.net.established - Established connections
- ubuntu.net.listening - Listening ports
- ubuntu.net.timewait - TIME_WAIT connections

DISK:
- ubuntu.disk.temp[device] - Disk temperature
- ubuntu.disk.smart[device] - SMART status
- ubuntu.disk.io.util[device] - I/O utilization

LOGS:
- ubuntu.log.auth.failed - Auth failures
- ubuntu.log.syslog.errors - Syslog errors

DISCOVERY:
- ubuntu.disk.discovery - Discover disks
- ubuntu.service.discovery - Discover services

NEXT STEPS:
1. Import the shared template ONCE in Zabbix (see template file)
2. Add this host to Zabbix:
   - Hostname: $HOSTNAME
   - IP: $IP_ADDRESS
   - Template: "Template Ubuntu Shared"

3. Test: zabbix_get -s $IP_ADDRESS -k ubuntu.cpu.temp

================================================================================
EOF
    
    cat "$CONFIG_SUMMARY"
    log_success "Summary saved to: $CONFIG_SUMMARY"
}

# Main
main() {
    detect_system
    quick_install
    install_repository
    install_agent
    configure_agent
    start_agent
    generate_summary
    
    echo ""
    log_success "==================================================="
    log_success " Installation completed!"
    log_success "==================================================="
    log_info "All Ubuntu servers use the SAME shared template"
    log_info "Configuration summary: ${GREEN}$CONFIG_SUMMARY${NC}"
    echo ""
}

main "$@"