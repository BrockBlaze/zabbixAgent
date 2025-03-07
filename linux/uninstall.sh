#!/bin/bash

# Configuration
LOG_FILE="/var/log/zabbix_uninstall.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

# Create log file
mkdir -p "$(dirname $LOG_FILE)"
log "Starting Zabbix agent uninstallation..."

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
systemctl stop zabbix-agent || log "Warning: Failed to stop Zabbix agent service"

# Disable service on boot
log "Disabling Zabbix agent service..."
systemctl disable zabbix-agent || log "Warning: Failed to disable Zabbix agent service"

# Remove Zabbix agent package
log "Removing Zabbix agent package..."
apt-get remove --purge -y zabbix-agent || error "Failed to remove Zabbix agent package"

# Clean up configuration files
log "Cleaning up configuration files..."
rm -rf /etc/zabbix || log "Warning: Failed to remove /etc/zabbix directory"

# Remove monitoring scripts
log "Removing monitoring scripts..."
rm -rf /etc/zabbix/scripts || log "Warning: Failed to remove monitoring scripts"

# Clean up logs
log "Cleaning up log files..."
rm -rf /var/log/zabbix || log "Warning: Failed to remove Zabbix log directory"

# Remove any remaining dependencies
log "Removing unused dependencies..."
apt-get autoremove -y || log "Warning: Failed to remove unused dependencies"

# Clean apt cache
log "Cleaning apt cache..."
apt-get clean || log "Warning: Failed to clean apt cache"

log "Uninstallation completed successfully"
log "Configuration backup stored in $BACKUP_DIR"
log "To completely remove the backup, run: rm -rf $BACKUP_DIR"

echo
echo "Zabbix agent has been successfully uninstalled"
echo "Configuration backup is stored in: $BACKUP_DIR"
echo "Uninstallation log is available at: $LOG_FILE" 