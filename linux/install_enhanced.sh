#!/bin/bash

# Enhanced Zabbix Agent Installer for Ubuntu 20.04/22.04/24.04
# Version: 3.0.0
# Author: Enhanced by Assistant
# Features: Auto-detection, rollback support, health checks, better error handling

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/var/log/zabbix/install.log"
VERSION="3.0.0"
BACKUP_DIR="/var/backups/zabbix-install-$(date +%Y%m%d-%H%M%S)"

# Functions for colored output
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[INFO] $1" | tee -a "$LOG_FILE"
}

# Cleanup function for rollback
cleanup_on_error() {
    log_error "Installation failed. Rolling back changes..."
    
    # Stop services if started
    systemctl stop zabbix-agent2 2>/dev/null || true
    systemctl stop zabbix-agent 2>/dev/null || true
    
    # Restore backup if exists
    if [ -d "$BACKUP_DIR" ]; then
        if [ -f "$BACKUP_DIR/zabbix_agent2.conf" ]; then
            cp "$BACKUP_DIR/zabbix_agent2.conf" /etc/zabbix/zabbix_agent2.conf 2>/dev/null || true
        fi
        if [ -f "$BACKUP_DIR/zabbix_agentd.conf" ]; then
            cp "$BACKUP_DIR/zabbix_agentd.conf" /etc/zabbix/zabbix_agentd.conf 2>/dev/null || true
        fi
    fi
    
    log_error "Rollback completed. Please check $LOG_FILE for details."
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}" >&2
    exit 1
fi

# Create log directory
mkdir -p "$(dirname $LOG_FILE)" || { log_error "Failed to create log directory"; exit 1; }
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Enhanced Zabbix Agent installation (Version $VERSION)..." | tee -a "$LOG_FILE"

# System detection and validation
detect_system() {
    log_info "Detecting system information..."
    
    # Check if Ubuntu/Debian
    if ! grep -q 'Ubuntu\|Debian' /etc/os-release; then
        log_error "This script only supports Ubuntu/Debian systems"
        exit 1
    fi
    
    # Get system info
    OS_NAME=$(lsb_release -is)
    OS_VERSION=$(lsb_release -rs)
    OS_CODENAME=$(lsb_release -cs)
    ARCH=$(dpkg --print-architecture)
    
    log_info "System: $OS_NAME $OS_VERSION ($OS_CODENAME) - $ARCH"
    
    # Validate Ubuntu version
    case "$OS_VERSION" in
        20.04|22.04|24.04)
            log_success "Ubuntu $OS_VERSION is supported"
            ;;
        *)
            log_warning "Ubuntu $OS_VERSION is not officially tested but will attempt installation"
            ;;
    esac
}

# Network connectivity check
check_network() {
    log_info "Checking network connectivity..."
    
    if ! ping -c 1 -W 3 repo.zabbix.com >/dev/null 2>&1; then
        log_error "Cannot reach repo.zabbix.com. Please check your internet connection."
        exit 1
    fi
    
    log_success "Network connectivity verified"
}

# Backup existing configuration
backup_existing() {
    if [ -f /etc/zabbix/zabbix_agent2.conf ] || [ -f /etc/zabbix/zabbix_agentd.conf ]; then
        log_info "Backing up existing configuration..."
        mkdir -p "$BACKUP_DIR"
        
        [ -f /etc/zabbix/zabbix_agent2.conf ] && cp /etc/zabbix/zabbix_agent2.conf "$BACKUP_DIR/"
        [ -f /etc/zabbix/zabbix_agentd.conf ] && cp /etc/zabbix/zabbix_agentd.conf "$BACKUP_DIR/"
        [ -d /etc/zabbix/scripts ] && cp -r /etc/zabbix/scripts "$BACKUP_DIR/"
        
        log_success "Backup created at $BACKUP_DIR"
    fi
}

# Interactive configuration with validation
get_configuration() {
    log_info "Gathering configuration parameters..."
    
    # Get Zabbix server IP with validation
    while true; do
        echo -n "Enter Zabbix Server IP [default: 192.168.70.2]: "
        read ZABBIX_SERVER_IP
        
        if [ -z "$ZABBIX_SERVER_IP" ]; then
            ZABBIX_SERVER_IP="192.168.70.2"
            break
        elif [[ $ZABBIX_SERVER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            log_error "Invalid IP address format. Please try again."
        fi
    done
    
    # Get hostname with validation
    echo -n "Enter Hostname for this server [default: $(hostname)]: "
    read CUSTOM_HOSTNAME
    if [ -z "$CUSTOM_HOSTNAME" ]; then
        CUSTOM_HOSTNAME=$(hostname)
    fi
    
    # Ask for proxy configuration
    echo -n "Use Zabbix Proxy? (y/N): "
    read USE_PROXY
    if [[ "$USE_PROXY" =~ ^[Yy]$ ]]; then
        echo -n "Enter Zabbix Proxy IP: "
        read ZABBIX_PROXY_IP
    fi
    
    # Confirm settings
    echo
    echo "========================================"
    echo "Configuration Summary:"
    echo "========================================"
    echo "Zabbix Server: $ZABBIX_SERVER_IP"
    echo "Hostname: $CUSTOM_HOSTNAME"
    [ ! -z "${ZABBIX_PROXY_IP:-}" ] && echo "Zabbix Proxy: $ZABBIX_PROXY_IP"
    echo "========================================"
    echo -n "Proceed with installation? (Y/n): "
    read CONFIRM
    
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

# Determine Zabbix version based on Ubuntu version
determine_zabbix_version() {
    case "$OS_VERSION" in
        24.04)
            ZABBIX_REPO_VERSION="22.04"  # Ubuntu 24.04 uses 22.04 repo
            ZABBIX_VERSION="7.0"
            ;;
        22.04)
            ZABBIX_REPO_VERSION="22.04"
            ZABBIX_VERSION="6.0"
            ;;
        20.04)
            ZABBIX_REPO_VERSION="20.04"
            ZABBIX_VERSION="6.0"
            ;;
        *)
            log_warning "Using default Zabbix 6.0 for Ubuntu $OS_VERSION"
            ZABBIX_REPO_VERSION="$OS_VERSION"
            ZABBIX_VERSION="6.0"
            ;;
    esac
    
    log_info "Selected Zabbix version $ZABBIX_VERSION for Ubuntu $OS_VERSION"
}

# Install Zabbix repository
install_repository() {
    log_info "Installing Zabbix repository..."
    
    # Clean up any previous repository files
    rm -f /tmp/zabbix-release*.deb 2>/dev/null
    
    # Determine repository URL
    if [ "$ZABBIX_VERSION" = "7.0" ]; then
        REPO_URL="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu${ZABBIX_REPO_VERSION}_all.deb"
    else
        REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release_${ZABBIX_VERSION}-4+ubuntu${ZABBIX_REPO_VERSION}_all.deb"
    fi
    
    log_info "Downloading repository package from: $REPO_URL"
    
    # Download with retry
    for i in {1..3}; do
        if wget -O /tmp/zabbix-release.deb "$REPO_URL" 2>/dev/null; then
            break
        fi
        log_warning "Download attempt $i failed, retrying..."
        sleep 2
    done
    
    if [ ! -f /tmp/zabbix-release.deb ]; then
        log_error "Failed to download Zabbix repository package after 3 attempts"
        exit 1
    fi
    
    dpkg -i /tmp/zabbix-release.deb || { log_error "Failed to install repository"; exit 1; }
    rm -f /tmp/zabbix-release.deb
    
    log_success "Repository installed successfully"
}

# Handle Ubuntu-specific dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update package list
    apt update || { log_error "Failed to update package list"; exit 1; }
    
    # Common dependencies
    DEPS="wget curl lm-sensors sudo"
    
    # Ubuntu version specific dependencies
    case "$OS_VERSION" in
        24.04)
            log_info "Installing Ubuntu 24.04 specific dependencies..."
            DEPS="$DEPS libldap2-dev libssl-dev"
            ;;
        22.04)
            log_info "Installing Ubuntu 22.04 dependencies..."
            DEPS="$DEPS libssl-dev"
            ;;
        20.04)
            log_info "Installing Ubuntu 20.04 dependencies..."
            DEPS="$DEPS libssl1.1"
            ;;
    esac
    
    apt install -y $DEPS || log_warning "Some dependencies may have failed to install"
    
    # Handle libldap compatibility for Ubuntu 24.04
    if [ "$OS_VERSION" = "24.04" ] && [ ! -f /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0 ]; then
        log_info "Creating libldap compatibility link for Ubuntu 24.04..."
        ln -sf /usr/lib/x86_64-linux-gnu/libldap-2.6.so.0 /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0 2>/dev/null || \
            log_warning "Could not create libldap compatibility link"
    fi
    
    log_success "Dependencies installed"
}

# Install Zabbix agent with fallback support
install_agent() {
    log_info "Installing Zabbix agent..."
    
    # Try agent2 first, fallback to agent if needed
    if apt install -y zabbix-agent2 2>/dev/null; then
        AGENT_TYPE="zabbix-agent2"
        AGENT_CONFIG="/etc/zabbix/zabbix_agent2.conf"
        AGENT_SERVICE="zabbix-agent2"
        AGENT_BINARY="zabbix_agent2"
        log_success "Zabbix Agent 2 installed successfully"
    elif apt install -y zabbix-agent 2>/dev/null; then
        AGENT_TYPE="zabbix-agent"
        AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
        AGENT_SERVICE="zabbix-agent"
        AGENT_BINARY="zabbix_agentd"
        log_warning "Installed Zabbix Agent (v1) as fallback"
    else
        log_error "Failed to install any Zabbix agent package"
        exit 1
    fi
    
    # Configure sensors
    if command -v sensors-detect >/dev/null 2>&1; then
        log_info "Configuring hardware sensors..."
        yes | sensors-detect >/dev/null 2>&1 || log_warning "Sensor detection may not have completed fully"
    fi
}

# Configure agent
configure_agent() {
    log_info "Configuring Zabbix agent..."
    
    # Create directories
    mkdir -p /etc/zabbix/scripts
    mkdir -p /etc/zabbix/zabbix_agent2.d
    mkdir -p /var/log/zabbix
    mkdir -p /var/run/zabbix
    
    # Copy monitoring scripts
    if [ -d "$(dirname "$0")/scripts" ]; then
        log_info "Installing monitoring scripts..."
        cp -r "$(dirname "$0")/scripts"/*.sh /etc/zabbix/scripts/ 2>/dev/null || log_warning "Some scripts may not have copied"
        chmod +x /etc/zabbix/scripts/*.sh 2>/dev/null || true
    else
        log_warning "Scripts directory not found, skipping custom scripts installation"
    fi
    
    # Generate configuration
    log_info "Writing agent configuration..."
    
    cat > "$AGENT_CONFIG" << EOF
# Zabbix Agent Configuration
# Generated by Enhanced Installer v$VERSION
# Date: $(date)

# Server configuration
Server=${ZABBIX_PROXY_IP:-$ZABBIX_SERVER_IP}
ServerActive=${ZABBIX_PROXY_IP:-$ZABBIX_SERVER_IP}
Hostname=$CUSTOM_HOSTNAME

# Logging
LogFile=/var/log/zabbix/${AGENT_BINARY}.log
LogFileSize=10
DebugLevel=3

# Process management
PidFile=/var/run/zabbix/${AGENT_BINARY}.pid

# Timeouts and buffers
Timeout=30
BufferSize=100
BufferSend=5

# Security
EnableRemoteCommands=0
LogRemoteCommands=1

# Performance
StartAgents=3

# Custom monitoring scripts
Include=/etc/zabbix/zabbix_agent2.d/*.conf

# User parameters for custom scripts
UserParameter=system.temperature,/etc/zabbix/scripts/cpu_temp.sh
UserParameter=system.processes,/etc/zabbix/scripts/top_processes.sh
UserParameter=system.login.failed,/etc/zabbix/scripts/login_monitoring.sh failed_logins
UserParameter=system.login.successful,/etc/zabbix/scripts/login_monitoring.sh successful_logins
UserParameter=system.login.last10,/etc/zabbix/scripts/login_monitoring.sh last10

# Health check parameter
UserParameter=agent.health,echo 1
EOF
    
    # Set permissions
    chown -R zabbix:zabbix /etc/zabbix/
    chown -R zabbix:zabbix /var/log/zabbix/
    chown -R zabbix:zabbix /var/run/zabbix/
    chmod 640 "$AGENT_CONFIG"
    
    # Configure sudo for monitoring scripts
    log_info "Configuring sudo permissions..."
    cat > /etc/sudoers.d/zabbix << EOF
# Zabbix monitoring permissions
zabbix ALL=(ALL) NOPASSWD: /usr/bin/last, /usr/bin/grep, /usr/bin/sensors, /usr/bin/top, /usr/bin/who
Defaults:zabbix !requiretty
EOF
    chmod 440 /etc/sudoers.d/zabbix
    
    log_success "Configuration completed"
}

# Test and start service
start_service() {
    log_info "Starting Zabbix agent service..."
    
    # Test configuration
    if sudo -u zabbix $AGENT_BINARY -t "$AGENT_CONFIG" 2>/dev/null; then
        log_success "Configuration test passed"
    else
        log_warning "Configuration test showed warnings but continuing..."
    fi
    
    # Start service
    systemctl daemon-reload
    systemctl stop "$AGENT_SERVICE" 2>/dev/null || true
    sleep 2
    
    if systemctl start "$AGENT_SERVICE"; then
        systemctl enable "$AGENT_SERVICE"
        log_success "Service started and enabled"
    else
        log_error "Failed to start service"
        journalctl -u "$AGENT_SERVICE" --no-pager -n 20 | tee -a "$LOG_FILE"
        exit 1
    fi
}

# Perform health checks
health_check() {
    log_info "Performing health checks..."
    
    # Check if service is running
    if ! systemctl is-active --quiet "$AGENT_SERVICE"; then
        log_error "Service is not running"
        return 1
    fi
    
    # Check if agent is listening
    if [ "$AGENT_TYPE" = "zabbix-agent2" ]; then
        PORT=10050
    else
        PORT=10050
    fi
    
    if ss -tuln | grep -q ":$PORT "; then
        log_success "Agent is listening on port $PORT"
    else
        log_warning "Agent may not be listening on expected port $PORT"
    fi
    
    # Test local connection
    if command -v zabbix_get >/dev/null 2>&1; then
        if zabbix_get -s 127.0.0.1 -k "agent.health" 2>/dev/null | grep -q "1"; then
            log_success "Agent responds to health check"
        else
            log_warning "Agent health check failed"
        fi
    fi
    
    # Check logs for errors
    if [ -f "/var/log/zabbix/${AGENT_BINARY}.log" ]; then
        if tail -20 "/var/log/zabbix/${AGENT_BINARY}.log" | grep -qi "error"; then
            log_warning "Errors found in agent log file"
        fi
    fi
    
    return 0
}

# Generate installation report
generate_report() {
    REPORT_FILE="/var/log/zabbix/installation_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
================================================================================
                    Zabbix Agent Installation Report
================================================================================
Date: $(date)
Installer Version: $VERSION

SYSTEM INFORMATION:
- OS: $OS_NAME $OS_VERSION ($OS_CODENAME)
- Architecture: $ARCH
- Kernel: $(uname -r)

INSTALLATION DETAILS:
- Agent Type: $AGENT_TYPE
- Zabbix Version: $ZABBIX_VERSION
- Configuration File: $AGENT_CONFIG
- Service Name: $AGENT_SERVICE

CONFIGURATION:
- Zabbix Server: $ZABBIX_SERVER_IP
- Hostname: $CUSTOM_HOSTNAME
$([ ! -z "${ZABBIX_PROXY_IP:-}" ] && echo "- Proxy: $ZABBIX_PROXY_IP")

SERVICE STATUS:
$(systemctl status "$AGENT_SERVICE" --no-pager 2>&1 | head -20)

PORT STATUS:
$(ss -tuln | grep 10050 || echo "No listeners on port 10050")

RECENT LOG ENTRIES:
$([ -f "/var/log/zabbix/${AGENT_BINARY}.log" ] && tail -10 "/var/log/zabbix/${AGENT_BINARY}.log" || echo "No log entries yet")

FILES CREATED/MODIFIED:
- $AGENT_CONFIG
- /etc/sudoers.d/zabbix
- /etc/zabbix/scripts/
- /var/log/zabbix/

BACKUP LOCATION: $BACKUP_DIR

================================================================================
EOF
    
    log_success "Installation report saved to $REPORT_FILE"
}

# Print summary
print_summary() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   INSTALLATION COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo "Agent Type: $AGENT_TYPE"
    echo "Zabbix Version: $ZABBIX_VERSION"
    echo "Ubuntu Version: $OS_VERSION"
    echo "Configuration: $AGENT_CONFIG"
    echo "Service: $AGENT_SERVICE"
    echo "Server: $ZABBIX_SERVER_IP"
    echo "Hostname: $CUSTOM_HOSTNAME"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Add this host to your Zabbix server"
    echo "2. Test connectivity: zabbix_get -s 127.0.0.1 -k agent.ping"
    echo "3. Check status: systemctl status $AGENT_SERVICE"
    echo "4. View logs: tail -f /var/log/zabbix/${AGENT_BINARY}.log"
    echo "5. Installation report: /var/log/zabbix/installation_report_*.txt"
    echo
    echo -e "${GREEN}Installation log: $LOG_FILE${NC}"
}

# Main installation flow
main() {
    echo -e "${GREEN}Enhanced Zabbix Agent Installer v$VERSION${NC}"
    echo "========================================"
    
    # Run installation steps
    detect_system
    check_network
    backup_existing
    get_configuration
    determine_zabbix_version
    install_repository
    install_dependencies
    install_agent
    configure_agent
    start_service
    
    # Perform health checks
    if health_check; then
        generate_report
        print_summary
        log_success "Installation completed successfully!"
        exit 0
    else
        log_error "Installation completed with errors. Please check the logs."
        exit 1
    fi
}

# Run main function
main "$@"