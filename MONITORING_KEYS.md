# Zabbix Custom Monitoring Keys Reference

## Template: Rithm Custom Monitoring Final

This document contains all the monitoring keys used in the custom Zabbix template for easy reference when recreating the template.

## Complete List of All Available Monitoring Keys

### System Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| System Uptime Days | `custom.system.uptime` | Zabbix agent (active) | 5m | Text/Unsigned integer | days | System uptime in days |
| System Kernel Version | `custom.system.kernel` | Zabbix agent (active) | 1h | Text | | Current kernel version |
| Reboot Required | `custom.system.reboot_required` | Zabbix agent (active) | 1h | Unsigned integer | | 1 if reboot required, 0 otherwise |

### CPU Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| CPU Temperature | `custom.cpu.temperature` | Zabbix agent (active) | 1m | Float | °C | CPU temperature from sensors |
| CPU Core Count | `custom.cpu.cores` | Zabbix agent (active) | 1h | Unsigned integer | | Number of CPU cores |
| CPU Load 1 Minute | `custom.cpu.load_1min` | Zabbix agent (active) | 1m | Float | | 1 minute load average |
| CPU Load 5 Minutes | `custom.cpu.load_5min` | Zabbix agent (active) | 5m | Float | | 5 minute load average |

### Memory Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Memory Available | `custom.memory.available` | Zabbix agent (active) | 30s | Unsigned integer | B | Available memory in bytes |
| Memory Used Percent | `custom.memory.used_percent` | Zabbix agent (active) | 1m | Float | % | Memory usage percentage |
| Swap Used | `custom.memory.swap_used` | Zabbix agent (active) | 5m | Unsigned integer | B | Swap space used in bytes |

### Disk Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Disk Count | `custom.disk.count` | Zabbix agent (active) | 1h | Unsigned integer | | Number of physical disks |
| Root Disk Usage Percent | `custom.disk.root_usage` | Zabbix agent (active) | 5m | Unsigned integer | % | Root filesystem usage percentage |
| Disk Temperature | `custom.disk.temperature[*]` | Zabbix agent (active) | 5m | Float | °C | Disk temperature (requires disk name) |
| Disk SMART Status | `custom.disk.smart_status[*]` | Zabbix agent (active) | 1h | Unsigned integer | | SMART health status (1=passed, 0=failed) |
| Disk IO Wait | `custom.disk.io_wait` | Zabbix agent (active) | 1m | Float | % | Average I/O wait percentage |

### Network Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Network Connections Established | `custom.network.connections_established` | Zabbix agent (active) | 30s | Unsigned integer | | Number of established connections |
| Network Connections Listening | `custom.network.connections_listening` | Zabbix agent (active) | 5m | Unsigned integer | | Number of listening ports |
| Network Connections TIME_WAIT | `custom.network.connections_timewait` | Zabbix agent (active) | 1m | Unsigned integer | | Connections in TIME_WAIT state |

### Service Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Service Status | `custom.service.status[*]` | Zabbix agent (active) | 1m | Text | | Service status (requires service name) |
| Running Services Count | `custom.service.count_running` | Zabbix agent (active) | 5m | Unsigned integer | | Number of running services |
| Failed Services Count | `custom.service.count_failed` | Zabbix agent (active) | 5m | Unsigned integer | | Number of failed services |

### Process Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Top CPU Process | `custom.process.top_cpu` | Zabbix agent (active) | 1m | Text | | Top CPU consuming process |
| Top Memory Process | `custom.process.top_memory` | Zabbix agent (active) | 1m | Text | | Top memory consuming process |
| Zombie Process Count | `custom.process.zombie_count` | Zabbix agent (active) | 5m | Unsigned integer | | Number of zombie processes |
| Total Process Count | `custom.process.total_count` | Zabbix agent (active) | 5m | Unsigned integer | | Total number of processes |

### Login & Security Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Failed Logins Last Hour | `custom.login.failed_last_hour` | Zabbix agent (active) | 5m | Unsigned integer | | Failed login attempts in last hour |
| Successful Logins Last Hour | `custom.login.successful_last_hour` | Zabbix agent (active) | 5m | Unsigned integer | | Successful logins in last hour |
| Last Login User | `custom.login.last_user` | Zabbix agent (active) | 5m | Text | | Username of last login |
| Current Active Users | `custom.login.current_users` | Zabbix agent (active) | 1m | Unsigned integer | | Number of currently logged in users |
| Updates Available | `custom.security.updates_available` | Zabbix agent (active) | 1h | Unsigned integer | | Available system updates |
| Security Updates Available | `custom.security.updates_security` | Zabbix agent (active) | 1h | Unsigned integer | | Available security updates |
| Sudo Attempts Today | `custom.security.sudo_attempts` | Zabbix agent (active) | 5m | Unsigned integer | | Sudo command attempts today |

### Log Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Auth Log Errors | `custom.log.auth_errors` | Zabbix agent (active) | 5m | Unsigned integer | | Errors in auth.log (last 100 lines) |
| Syslog Errors | `custom.log.syslog_errors` | Zabbix agent (active) | 5m | Unsigned integer | | Errors in syslog (last 100 lines) |
| Kernel Log Errors | `custom.log.kern_errors` | Zabbix agent (active) | 5m | Unsigned integer | | Errors in kern.log (last 100 lines) |

### Docker Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Docker Containers Running | `custom.docker.containers_running` | Zabbix agent (active) | 1m | Unsigned integer | | Number of running Docker containers |
| Docker Containers Total | `custom.docker.containers_total` | Zabbix agent (active) | 5m | Unsigned integer | | Total number of Docker containers |
| Docker Images Count | `custom.docker.images_count` | Zabbix agent (active) | 5m | Unsigned integer | | Number of Docker images |

### Discovery Rules

| Discovery Name | Key | Description | Returns |
|---------------|-----|-------------|---------|
| Disk Discovery | `custom.discovery.disks` | Discovers physical disks | JSON with disk names |
| Service Discovery | `custom.discovery.services` | Discovers enabled services | JSON with service names |
| Network Interface Discovery | `custom.discovery.network_interfaces` | Discovers active network interfaces | JSON with interface names |

## Priority Items for Initial Template (10 Items)

These are the 10 most important items to start with:

1. **CPU Temperature** - `custom.cpu.temperature`
2. **Memory Available** - `custom.memory.available`  
3. **Disk Count** - `custom.disk.count`
4. **Network Connections** - `custom.network.connections_established`
5. **Failed Logins Last Hour** - `custom.login.failed_last_hour`
6. **Updates Available** - `custom.security.updates_available`
7. **System Uptime Days** - `custom.system.uptime`
8. **Running Services** - `custom.service.count_running`
9. **Root Disk Usage Percent** - `custom.disk.root_usage`
10. **Docker Containers Running** - `custom.docker.containers_running`

## Template Recreation Instructions

### Step 1: Create Template
1. Go to Configuration → Templates
2. Click "Create template"
3. Set template name: `Template Rithm Custom Final`
4. Set visible name: `Rithm Custom Monitoring Final`  
5. Add to group: `Templates`
6. Set description: `Custom monitoring template with custom.* parameters`

### Step 2: Add Items
For each item in the tables above:
1. Go to Items tab in the template
2. Click "Create item"
3. Fill in the details from the table:
   - **Name**: Use the Item Name from table
   - **Type**: Zabbix agent (active)
   - **Key**: Use the exact key from table
   - **Type of information**: Use Value Type from table
   - **Update interval**: Use Update Interval from table
   - **Units**: Use Units from table (if specified)
   - **Description**: Use Description from table

### Step 3: Add Discovery Rules (Optional)
1. Go to Discovery rules tab
2. Click "Create discovery rule"
3. Add the discovery rules from the table above
4. Create item prototypes for discovered items

### Step 4: Apply to Hosts
1. Go to Configuration → Hosts
2. Select target host
3. Go to Templates tab
4. Link the `Template Rithm Custom Final` template

## Testing Keys

To test any key from the Zabbix server:
```bash
zabbix_get -s <host_ip> -k <key_name>
```

Examples:
```bash
zabbix_get -s 192.168.68.146 -k custom.cpu.temperature
zabbix_get -s 192.168.68.146 -k custom.disk.temperature[sda]
zabbix_get -s 192.168.68.146 -k custom.service.status[nginx]
```

## Notes
- All items use **Zabbix agent (active)** type
- All keys use the `custom.*` namespace for consistency
- Update intervals are optimized for performance vs. data freshness
- Temperature values are in Celsius
- Memory values are in bytes (Zabbix will auto-convert to KB/MB/GB)
- Percentage values are integers (0-100) or floats where precision is needed
- Items with [*] require parameters (e.g., disk name, service name)