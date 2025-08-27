#!/bin/bash

# Zabbix Agent Auto-Installer for Ubuntu 20.04+
# Version: 4.0.0
# Features: Fully automated, minimal user input, template generation

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration defaults
LOG_FILE="/var/log/zabbix/auto_install.log"
TEMPLATE_FILE="/tmp/zabbix_template_$(hostname).json"
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
log_info " Zabbix Agent Auto-Installer v4.0.0"
log_info " For Ubuntu 20.04, 22.04, 24.04+"
log_info "==================================================="

# Auto-detect system
detect_system() {
    log_info "Auto-detecting system configuration..."
    
    OS_VERSION=$(lsb_release -rs)
    HOSTNAME=$(hostname -f)
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    CPU_CORES=$(nproc)
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    DISK_COUNT=$(lsblk -d -o NAME,TYPE | grep -c disk)
    
    log_info "Hostname: $HOSTNAME"
    log_info "IP Address: $IP_ADDRESS"
    log_info "Ubuntu Version: $OS_VERSION"
    log_info "CPU Cores: $CPU_CORES"
    log_info "Memory: ${MEMORY_GB}GB"
    log_info "Disk Count: $DISK_COUNT"
    
    # Determine Zabbix version based on Ubuntu version
    case "$OS_VERSION" in
        24.04)
            ZABBIX_VERSION="7.0"
            REPO_VERSION="22.04"  # Use 22.04 repo for 24.04
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

# Quick mode - use defaults if possible
quick_install_prompt() {
    echo ""
    log_info "Quick Install Options:"
    echo "  1) Express Install (Use all defaults - Zabbix Server: $DEFAULT_ZABBIX_SERVER)"
    echo "  2) Custom Server (Specify Zabbix server IP only)"
    echo "  3) Full Custom (All manual configuration)"
    echo ""
    read -p "Select option [1-3] (default: 1): " -t 10 INSTALL_MODE || INSTALL_MODE="1"
    
    case "$INSTALL_MODE" in
        2)
            read -p "Enter Zabbix Server IP: " ZABBIX_SERVER_IP
            ;;
        3)
            read -p "Enter Zabbix Server IP [default: $DEFAULT_ZABBIX_SERVER]: " ZABBIX_SERVER_IP
            ZABBIX_SERVER_IP="${ZABBIX_SERVER_IP:-$DEFAULT_ZABBIX_SERVER}"
            read -p "Enter Hostname [default: $HOSTNAME]: " CUSTOM_HOSTNAME
            HOSTNAME="${CUSTOM_HOSTNAME:-$HOSTNAME}"
            ;;
        *)
            ZABBIX_SERVER_IP="$DEFAULT_ZABBIX_SERVER"
            log_info "Using express installation with defaults"
            ;;
    esac
    
    ZABBIX_SERVER_IP="${ZABBIX_SERVER_IP:-$DEFAULT_ZABBIX_SERVER}"
}

# Install repository
install_repository() {
    log_info "Installing Zabbix repository..."
    
    # Clean previous installations
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

# Install agent with automatic package selection
install_agent() {
    log_info "Installing Zabbix agent..."
    
    # Try agent2 first, fallback to agent
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
    
    # Install monitoring tools
    apt-get install -qq -y lm-sensors smartmontools nvme-cli sysstat 2>/dev/null || {
        log_warning "Some monitoring tools could not be installed"
    }
    
    # Configure sensors silently
    yes | sensors-detect >/dev/null 2>&1 || true
}

# Configure agent
configure_agent() {
    log_info "Configuring Zabbix agent..."
    
    # Backup original config
    cp "$AGENT_CONFIG" "${AGENT_CONFIG}.backup.$(date +%Y%m%d)"
    
    # Create optimized configuration
    cat > "$AGENT_CONFIG" << EOF
# Zabbix Agent Configuration - Auto-generated
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

# Enable remote commands (optional, uncomment if needed)
# EnableRemoteCommands=1
# LogRemoteCommands=1

# User parameters for system monitoring
UserParameter=custom.cpu.temp,sensors 2>/dev/null | grep -E 'Core|Package' | grep -oE '[0-9]+\.[0-9]+' | head -1
UserParameter=custom.mem.available,free -b | awk '/^Mem:/{print \$7}'
UserParameter=custom.disk.count,lsblk -d -o TYPE | grep -c disk
UserParameter=custom.service.status[*],systemctl is-active \$1 2>/dev/null || echo "inactive"
UserParameter=custom.docker.containers,docker ps -q 2>/dev/null | wc -l || echo 0
UserParameter=custom.updates.available,apt list --upgradable 2>/dev/null | grep -c upgradable || echo 0

# Process monitoring
UserParameter=custom.proc.top.cpu,ps aux | sort -nrk 3,3 | head -1 | awk '{print \$2":"\$3":"\$11}'
UserParameter=custom.proc.top.mem,ps aux | sort -nrk 4,4 | head -1 | awk '{print \$2":"\$4":"\$11}'

# Network monitoring
UserParameter=custom.net.connections,ss -tan | grep ESTABLISHED | wc -l
UserParameter=custom.net.listening,ss -tln | grep LISTEN | wc -l

# Disk monitoring
UserParameter=custom.disk.temp[*],smartctl -A /dev/\$1 2>/dev/null | grep Temperature_Celsius | awk '{print \$10}' || echo 0
UserParameter=custom.disk.smart[*],smartctl -H /dev/\$1 2>/dev/null | grep -q "PASSED" && echo 1 || echo 0

# Include additional configs
Include=/etc/zabbix/zabbix_${AGENT_TYPE}.d/*.conf
EOF
    
    # Set permissions
    chown zabbix:zabbix "$AGENT_CONFIG"
    chmod 640 "$AGENT_CONFIG"
    
    # Create sudoers entry for zabbix user
    cat > /etc/sudoers.d/zabbix << EOF
zabbix ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/smartctl, /usr/bin/docker, /usr/bin/sensors, /usr/bin/apt
Defaults:zabbix !requiretty
EOF
    chmod 440 /etc/sudoers.d/zabbix
    
    log_success "Agent configured"
}

# Generate Zabbix template for easy import
generate_template() {
    log_info "Generating Zabbix template for host configuration..."
    
    cat > "$TEMPLATE_FILE" << 'EOF'
{
    "zabbix_export": {
        "version": "6.0",
        "date": "TEMPLATE_DATE",
        "groups": [
            {
                "name": "Linux servers"
            }
        ],
        "templates": [
            {
                "template": "Template Linux Auto Custom",
                "name": "Linux Auto-Configured Monitoring",
                "description": "Auto-generated template for Ubuntu servers with custom metrics",
                "groups": [
                    {
                        "name": "Linux servers"
                    }
                ],
                "items": [
                    {
                        "name": "CPU Temperature",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.cpu.temp",
                        "delay": "30s",
                        "value_type": "FLOAT",
                        "units": "°C",
                        "description": "Current CPU temperature"
                    },
                    {
                        "name": "Available Memory",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.mem.available",
                        "delay": "30s",
                        "value_type": "UNSIGNED",
                        "units": "B",
                        "description": "Available memory in bytes"
                    },
                    {
                        "name": "Disk Count",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.disk.count",
                        "delay": "1h",
                        "value_type": "UNSIGNED",
                        "description": "Number of physical disks"
                    },
                    {
                        "name": "Docker Containers Running",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.docker.containers",
                        "delay": "1m",
                        "value_type": "UNSIGNED",
                        "description": "Number of running Docker containers"
                    },
                    {
                        "name": "Available Updates",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.updates.available",
                        "delay": "1h",
                        "value_type": "UNSIGNED",
                        "description": "Number of available system updates"
                    },
                    {
                        "name": "Established Connections",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.net.connections",
                        "delay": "30s",
                        "value_type": "UNSIGNED",
                        "description": "Number of established network connections"
                    },
                    {
                        "name": "Listening Ports",
                        "type": "ZABBIX_ACTIVE",
                        "key": "custom.net.listening",
                        "delay": "5m",
                        "value_type": "UNSIGNED",
                        "description": "Number of listening ports"
                    }
                ],
                "discovery_rules": [
                    {
                        "name": "Disk Discovery",
                        "type": "ZABBIX_ACTIVE",
                        "key": "vfs.dev.discovery",
                        "delay": "1h",
                        "item_prototypes": [
                            {
                                "name": "Disk {#DEVNAME} Temperature",
                                "type": "ZABBIX_ACTIVE",
                                "key": "custom.disk.temp[{#DEVNAME}]",
                                "delay": "5m",
                                "value_type": "FLOAT",
                                "units": "°C",
                                "description": "Temperature of disk {#DEVNAME}"
                            },
                            {
                                "name": "Disk {#DEVNAME} SMART Status",
                                "type": "ZABBIX_ACTIVE",
                                "key": "custom.disk.smart[{#DEVNAME}]",
                                "delay": "1h",
                                "value_type": "UNSIGNED",
                                "description": "SMART health status of disk {#DEVNAME}"
                            }
                        ]
                    },
                    {
                        "name": "Network Interface Discovery",
                        "type": "ZABBIX_ACTIVE",
                        "key": "net.if.discovery",
                        "delay": "1h",
                        "item_prototypes": [
                            {
                                "name": "Interface {#IFNAME} Incoming Traffic",
                                "type": "ZABBIX_ACTIVE",
                                "key": "net.if.in[{#IFNAME}]",
                                "delay": "30s",
                                "value_type": "UNSIGNED",
                                "units": "bps",
                                "preprocessing": [
                                    {
                                        "type": "CHANGE_PER_SECOND"
                                    },
                                    {
                                        "type": "MULTIPLIER",
                                        "params": "8"
                                    }
                                ]
                            },
                            {
                                "name": "Interface {#IFNAME} Outgoing Traffic",
                                "type": "ZABBIX_ACTIVE",
                                "key": "net.if.out[{#IFNAME}]",
                                "delay": "30s",
                                "value_type": "UNSIGNED",
                                "units": "bps",
                                "preprocessing": [
                                    {
                                        "type": "CHANGE_PER_SECOND"
                                    },
                                    {
                                        "type": "MULTIPLIER",
                                        "params": "8"
                                    }
                                ]
                            }
                        ]
                    }
                ],
                "triggers": [
                    {
                        "expression": "{Template Linux Auto Custom:custom.cpu.temp.last()}>80",
                        "name": "CPU temperature is too high",
                        "priority": "HIGH",
                        "description": "CPU temperature exceeds 80°C"
                    },
                    {
                        "expression": "{Template Linux Auto Custom:custom.mem.available.last()}<1073741824",
                        "name": "Available memory is low",
                        "priority": "WARNING",
                        "description": "Less than 1GB of memory available"
                    },
                    {
                        "expression": "{Template Linux Auto Custom:custom.updates.available.last()}>50",
                        "name": "Many system updates available",
                        "priority": "INFO",
                        "description": "More than 50 system updates are available"
                    },
                    {
                        "expression": "{Template Linux Auto Custom:custom.net.connections.last()}>1000",
                        "name": "High number of network connections",
                        "priority": "WARNING",
                        "description": "More than 1000 established connections"
                    }
                ]
            }
        ]
    }
}
EOF
    
    # Update template date
    sed -i "s/TEMPLATE_DATE/$(date -Iseconds)/" "$TEMPLATE_FILE"
    
    log_success "Template generated: $TEMPLATE_FILE"
}

# Generate configuration summary
generate_summary() {
    log_info "Generating configuration summary..."
    
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
- Service Name: $AGENT_SERVICE

SERVER CONFIGURATION:
- Zabbix Server: $ZABBIX_SERVER_IP
- Port: 10051 (active checks)

CUSTOM METRICS AVAILABLE:
- custom.cpu.temp - CPU temperature
- custom.mem.available - Available memory
- custom.disk.count - Number of disks
- custom.docker.containers - Docker containers running
- custom.updates.available - System updates available
- custom.net.connections - Established connections
- custom.net.listening - Listening ports
- custom.disk.temp[device] - Disk temperature
- custom.disk.smart[device] - Disk SMART status

QUICK COMMANDS:
- Check agent status: systemctl status $AGENT_SERVICE
- Test connectivity: zabbix_get -s localhost -k agent.ping
- View logs: tail -f /var/log/zabbix/${AGENT_TYPE}.log
- Restart agent: systemctl restart $AGENT_SERVICE

NEXT STEPS:
1. Import the template file into Zabbix server:
   File: $TEMPLATE_FILE
   
2. Add this host to Zabbix server:
   - Hostname: $HOSTNAME
   - IP Address: $IP_ADDRESS
   - Templates: "Template Linux Auto Custom" + "Linux by Zabbix agent"
   
3. Verify data collection:
   zabbix_get -s $IP_ADDRESS -k custom.cpu.temp

For bulk deployments, use:
   ZABBIX_SERVER=your.server.ip curl -sSL http://yourserver/install_auto.sh | sudo bash

================================================================================
EOF
    
    cat "$CONFIG_SUMMARY"
    log_success "Summary saved to: $CONFIG_SUMMARY"
}

# Start and verify agent
start_agent() {
    log_info "Starting Zabbix agent..."
    
    systemctl daemon-reload
    systemctl restart "$AGENT_SERVICE"
    systemctl enable "$AGENT_SERVICE"
    
    sleep 3
    
    if systemctl is-active --quiet "$AGENT_SERVICE"; then
        log_success "Agent started successfully"
        
        # Test agent
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

# Main installation flow
main() {
    detect_system
    quick_install_prompt
    install_repository
    install_agent
    configure_agent
    generate_template
    start_agent
    generate_summary
    
    echo ""
    log_success "==================================================="
    log_success " Installation completed successfully!"
    log_success "==================================================="
    echo ""
    log_info "Template file for Zabbix server: ${GREEN}$TEMPLATE_FILE${NC}"
    log_info "Configuration summary: ${GREEN}$CONFIG_SUMMARY${NC}"
    echo ""
}

# Run main function
main "$@"