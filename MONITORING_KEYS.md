# Zabbix Custom Monitoring Keys Reference

## Template: Rithm Custom Monitoring Final

This document contains all the monitoring keys used in the custom Zabbix template for easy reference when recreating the template.

## System Metrics

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| CPU Temperature | `custom.cpu.temperature` | Zabbix agent (active) | 1m | Float | °C | CPU temperature from sensors |
| Memory Available | `custom.memory.available` | Zabbix agent (active) | 30s | Unsigned integer | B | Available memory in bytes |
| System Uptime Days | `custom.system.uptime` | Zabbix agent (active) | 5m | Unsigned integer | days | System uptime in days |
| Updates Available | `custom.security.updates_available` | Zabbix agent (active) | 1h | Unsigned integer | | Available system updates |

## Disk Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Disk Count | `custom.disk.count` | Zabbix agent (active) | 1h | Unsigned integer | | Number of physical disks |
| Root Disk Usage Percent | `custom.disk.root_usage` | Zabbix agent (active) | 5m | Unsigned integer | % | Root filesystem usage percentage |

## Network Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Network Connections | `custom.network.connections_established` | Zabbix agent (active) | 30s | Unsigned integer | | Number of established connections |

## Security & Login Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Failed Logins Last Hour | `custom.login.failed_last_hour` | Zabbix agent (active) | 5m | Unsigned integer | | Failed login attempts in last hour |

## Service Monitoring

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Running Services | `custom.service.count_running` | Zabbix agent (active) | 5m | Unsigned integer | | Number of running services |
| Docker Containers Running | `custom.docker.containers_running` | Zabbix agent (active) | 1m | Unsigned integer | | Number of running Docker containers |

## Template Recreation Instructions

### Step 1: Create Template
1. Go to Configuration → Templates
2. Click "Create template"
3. Set template name: `Template Rithm Custom Final`
4. Set visible name: `Rithm Custom Monitoring Final`  
5. Add to group: `Templates`
6. Set description: `Custom monitoring template with custom.* parameters - proper UUIDs`

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

### Step 3: Apply to Hosts
1. Go to Configuration → Hosts
2. Select target host
3. Go to Templates tab
4. Link the `Template Rithm Custom Final` template

## Custom Script Dependencies

The following custom scripts must be deployed to `/etc/zabbix/scripts/` on target hosts:
- `cpu_temp.sh` - For CPU temperature monitoring
- `disk_health.sh` - For disk monitoring  
- `login_monitoring.sh` - For login monitoring
- `top_processes.sh` - For process monitoring

## Notes
- All items use **Zabbix agent (active)** type
- All keys use the `custom.*` namespace
- Update intervals are optimized for performance vs. data freshness
- Temperature values are in Celsius
- Memory values are in bytes
- Percentage values are integers (0-100)