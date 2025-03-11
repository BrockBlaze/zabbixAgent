#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix_uninstall.log"
VERSION="1.1.0"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Display help information
show_help() {
    echo "Zabbix Agent Uninstaller Script v$VERSION"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -y, --yes           Automatically answer yes to all prompts"
    echo ""
    exit 0
}

# Parse command line arguments
AUTO_YES=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -y|--yes)
            AUTO_YES=1
            shift
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Create log file
mkdir -p "$(dirname $LOG_FILE)"
log "Starting Zabbix agent uninstallation (Version $VERSION)..."

# Confirm uninstallation
if [ $AUTO_YES -eq 0 ]; then
    read -p "Are you sure you want to uninstall Zabbix agent? This will remove all configurations and scripts. (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "Uninstallation aborted by user"
        exit 0
    fi
fi

# Determine package manager
PACKAGE_MANAGER=""
if command_exists apt-get; then
    PACKAGE_MANAGER="apt-get"
    REMOVE_CMD="$PACKAGE_MANAGER remove --purge -y"
elif command_exists yum; then
    PACKAGE_MANAGER="yum"
    REMOVE_CMD="$PACKAGE_MANAGER remove -y"
elif command_exists dnf; then
    PACKAGE_MANAGER="dnf"
    REMOVE_CMD="$PACKAGE_MANAGER remove -y"
else
    warning "Could not determine package manager. Will try to continue anyway."
    REMOVE_CMD="echo 'Package manager not found. Skipping package removal for'"
fi

# Backup configuration
BACKUP_DIR="/root/zabbix_backup_$(date +%Y%m%d_%H%M%S)"
log "Creating backup directory at $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -d "/etc/zabbix" ]; then
    log "Backing up Zabbix configuration..."
    cp -r /etc/zabbix "$BACKUP_DIR/" || error "Failed to backup configuration"
fi

# Stop Zabbix agent service
log "Stopping Zabbix agent service..."
if command_exists systemctl; then
    systemctl stop zabbix-agent || warning "Failed to stop Zabbix agent service with systemctl"
elif command_exists service; then
    service zabbix-agent stop || warning "Failed to stop Zabbix agent service with service command"
else
    warning "Could not determine service manager. Attempting to continue..."
fi

# Disable service on boot
log "Disabling Zabbix agent service..."
if command_exists systemctl; then
    systemctl disable zabbix-agent || warning "Failed to disable Zabbix agent service with systemctl"
elif command_exists chkconfig; then
    chkconfig zabbix-agent off || warning "Failed to disable Zabbix agent service with chkconfig"
else
    warning "Could not determine service manager. Attempting to continue..."
fi

# Remove Zabbix agent package
log "Removing Zabbix agent package..."
$REMOVE_CMD zabbix-agent || warning "Failed to remove Zabbix agent package"

# Clean up configuration files
log "Cleaning up configuration files..."
rm -rf /etc/zabbix || warning "Failed to remove /etc/zabbix directory"

# Remove monitoring scripts
log "Removing monitoring scripts..."
rm -rf /etc/zabbix/scripts || warning "Failed to remove monitoring scripts"

# Clean up logs
log "Cleaning up log files..."
rm -rf /var/log/zabbix || warning "Failed to remove Zabbix log directory"

# Remove sudoers configuration
log "Removing sudoers configuration..."
if [ -f "/etc/sudoers.d/zabbix" ]; then
    rm -f /etc/sudoers.d/zabbix || warning "Failed to remove /etc/sudoers.d/zabbix"
fi

# Remove any remaining dependencies
log "Removing unused dependencies..."
if [ -n "$PACKAGE_MANAGER" ]; then
    if [ "$PACKAGE_MANAGER" = "apt-get" ]; then
        apt-get autoremove -y || warning "Failed to remove unused dependencies"
    elif [ "$PACKAGE_MANAGER" = "yum" ] || [ "$PACKAGE_MANAGER" = "dnf" ]; then
        $PACKAGE_MANAGER autoremove -y || warning "Failed to remove unused dependencies"
    fi
fi

# Clean package manager cache
log "Cleaning package manager cache..."
if [ -n "$PACKAGE_MANAGER" ]; then
    if [ "$PACKAGE_MANAGER" = "apt-get" ]; then
        apt-get clean || warning "Failed to clean apt cache"
    elif [ "$PACKAGE_MANAGER" = "yum" ] || [ "$PACKAGE_MANAGER" = "dnf" ]; then
        $PACKAGE_MANAGER clean all || warning "Failed to clean package manager cache"
    fi
fi

log "Uninstallation completed successfully"
log "Configuration backup stored in $BACKUP_DIR"
log "To completely remove the backup, run: rm -rf $BACKUP_DIR"

echo
echo "Zabbix agent has been successfully uninstalled"
echo "Configuration backup is stored in: $BACKUP_DIR"
echo "Uninstallation log is available at: $LOG_FILE" 