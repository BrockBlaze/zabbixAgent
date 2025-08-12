# Disk Temperature and Health Monitoring for Zabbix

## Overview
This documentation covers the disk monitoring scripts added to your Zabbix agent installation for monitoring SSD/HDD temperatures and health status on Ubuntu servers.

## Scripts Added

### 1. `disk_temp.sh` - Temperature Monitoring
Monitors the temperature of all disk drives (SSD, HDD, NVMe) using smartctl.

### 2. `disk_health.sh` - Health and SMART Monitoring
Monitors disk health status, wear level, reallocated sectors, and other SMART attributes.

## Installation Requirements
The installer automatically installs:
- `smartmontools` - For SMART monitoring
- `nvme-cli` - For NVMe drive support

## Available Zabbix Items

### Temperature Monitoring
```bash
# Get specific disk temperature
disk.temperature[sda]           # Returns temperature of /dev/sda
disk.temperature[nvme0n1]       # Returns temperature of /dev/nvme0n1

# Discover all disks (for Zabbix LLD)
disk.temperature.discovery      # Returns JSON with all discovered disks

# Get all disk temperatures
disk.temperature.all            # Returns all disk temps as "disk:temp" pairs

# Get average temperature
disk.temperature.average        # Returns average temp of all disks

# Get maximum temperature (hottest disk)
disk.temperature.max            # Returns highest temperature among all disks
```

### Health Monitoring
```bash
# Overall health status
disk.health[sda]               # Returns OK/CRITICAL/UNKNOWN for specific disk
disk.health[]                  # Returns worst health status among all disks

# SSD wear level (percentage used)
disk.wear[sda]                 # Returns wear percentage (0-100)

# Reallocated sectors count
disk.reallocated[sda]          # Returns number of reallocated sectors

# Pending sectors count
disk.pending[sda]              # Returns number of pending sectors

# Power on hours
disk.power_hours[sda]          # Returns total power-on hours

# Disk information
disk.info[sda]                 # Returns model and serial number

# Complete stats in JSON
disk.stats[sda]                # Returns all stats in JSON format
```

## Testing the Scripts

After installation, test the monitoring:

```bash
# Test temperature monitoring
zabbix_get -s 127.0.0.1 -k "disk.temperature.max"
zabbix_get -s 127.0.0.1 -k "disk.temperature[sda]"

# Test health monitoring
zabbix_get -s 127.0.0.1 -k "disk.health[]"
zabbix_get -s 127.0.0.1 -k "disk.wear[sda]"

# Test discovery
zabbix_get -s 127.0.0.1 -k "disk.temperature.discovery"
```

## Zabbix Template Configuration

### Create Items
1. **Disk Temperature (Max)** - Monitor the hottest disk
   - Key: `disk.temperature.max`
   - Type: Zabbix agent
   - Update interval: 5m
   - Units: °C

2. **Disk Health Status** - Overall health check
   - Key: `disk.health[]`
   - Type: Zabbix agent
   - Update interval: 10m
   - Value mapping: OK=0, CRITICAL=1, UNKNOWN=2

### Create Discovery Rule
1. **Disk Discovery**
   - Key: `disk.temperature.discovery`
   - Type: Zabbix agent
   - Update interval: 1h

2. **Item Prototypes:**
   - Temperature: `disk.temperature[{#DISKNAME}]`
   - Health: `disk.health[{#DISKNAME}]`
   - Wear Level: `disk.wear[{#DISKNAME}]`
   - Reallocated Sectors: `disk.reallocated[{#DISKNAME}]`

### Create Triggers
1. **High Disk Temperature**
   ```
   {host:disk.temperature.max.last()}>50
   ```
   Warning at 50°C, Critical at 60°C

2. **Disk Health Failed**
   ```
   {host:disk.health[].str(CRITICAL)}=1
   ```
   
3. **High SSD Wear**
   ```
   {host:disk.wear[sda].last()}>80
   ```
   Warning at 80% wear

4. **Reallocated Sectors Detected**
   ```
   {host:disk.reallocated[sda].last()}>0
   ```

## Troubleshooting

### Permission Issues
The installer automatically configures sudo permissions for smartctl and nvme commands. If you encounter permission errors:

```bash
# Check sudo configuration
sudo cat /etc/sudoers.d/zabbix

# Test as zabbix user
sudo -u zabbix smartctl -A /dev/sda
```

### No Temperature Data
Some drives may not report temperature. Check manually:
```bash
sudo smartctl -A /dev/sda | grep -i temp
sudo nvme smart-log /dev/nvme0n1 | grep -i temp
```

### NVMe Drives Not Detected
Ensure nvme-cli is installed:
```bash
sudo apt install nvme-cli
```

## Supported Drives
- SATA SSDs and HDDs (`/dev/sd*`)
- NVMe SSDs (`/dev/nvme*`)
- IDE drives (`/dev/hd*`)

## Notes
- Temperature readings update every 5 minutes by default
- Health checks run every 10 minutes
- Discovery runs hourly to detect new drives
- All scripts include timeout protection (5 seconds)
- Scripts handle missing drives gracefully