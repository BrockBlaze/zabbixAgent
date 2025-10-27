# Zabbix Template Updates Needed

The installer now supports **new webapp performance metrics** that need to be added to your Zabbix template manually.

## New Monitoring Keys Added to Installer

These keys are now available in the agent configuration but need to be added as items in your Zabbix template (`zbx_export_templates.yaml`):

### Webapp Performance Metrics

| Item Name | Key | Type | Update Interval | Value Type | Units | Description |
|-----------|-----|------|----------------|------------|-------|-------------|
| Disk Read Latency | `custom.disk.read_latency` | Zabbix agent (active) | 1m | Float | ms | Disk read latency in milliseconds |
| Disk Write Latency | `custom.disk.write_latency` | Zabbix agent (active) | 1m | Float | ms | Disk write latency in milliseconds |
| Disk Read IOPS | `custom.disk.iops_read` | Zabbix agent (active) | 1m | Unsigned integer | | Disk read operations per second |
| Disk Write IOPS | `custom.disk.iops_write` | Zabbix agent (active) | 1m | Unsigned integer | | Disk write operations per second |
| Swap Used Percent | `custom.memory.swap_used_percent` | Zabbix agent (active) | 5m | Float | % | Swap usage percentage |
| Network Errors | `custom.network.errors` | Zabbix agent (active) | 1m | Unsigned integer | | Network packet errors/drops |
| NVMe Temperature | `custom.disk.nvme_temp[*]` | Zabbix agent (active) | 5m | Float | °C | NVMe-specific temperature (requires disk name) |
| Disk I/O Wait | `custom.disk.io_wait` | Zabbix agent (active) | 1m | Float | % | I/O wait percentage (already exists, verify it's present) |

## How to Add Items to Zabbix Template

### Option 1: Via Zabbix Web UI

1. Go to **Configuration → Templates**
2. Find and click on **Rithm** template
3. Go to **Items** tab
4. Click **Create item** for each new metric above
5. Fill in the details from the table

### Option 2: Export and Edit YAML

1. Go to **Configuration → Templates**
2. Select **Rithm** template
3. Click **Export** (YAML format)
4. Add the new items manually to the YAML file
5. Re-import the updated template

## Recommended Triggers

Add triggers to alert on webapp performance issues:

### High I/O Wait Trigger
- **Expression**: `min(/Rithm/custom.disk.io_wait,5m)>20`
- **Name**: High I/O Wait - Disk Bottleneck
- **Severity**: Warning
- **Description**: I/O wait > 20% indicates disk performance bottleneck

### High Disk Latency Trigger
- **Expression**: `min(/Rithm/custom.disk.read_latency,5m)>50 or min(/Rithm/custom.disk.write_latency,5m)>50`
- **Name**: High Disk Latency
- **Severity**: Warning
- **Description**: Disk latency over 50ms indicates slow disk performance

### Swap Usage Trigger
- **Expression**: `min(/Rithm/custom.memory.swap_used_percent,5m)>10`
- **Name**: High Swap Usage
- **Severity**: Warning
- **Description**: System is using swap, may indicate memory exhaustion

### Network Errors Trigger
- **Expression**: `min(/Rithm/custom.network.errors,5m)>100`
- **Name**: Network Packet Errors
- **Severity**: Average
- **Description**: Network is experiencing packet drops or errors

## Testing New Keys

Test from Zabbix server after agent installation:

```bash
# Disk Performance
zabbix_get -s <agent_ip> -k custom.disk.io_wait
zabbix_get -s <agent_ip> -k custom.disk.read_latency
zabbix_get -s <agent_ip> -k custom.disk.write_latency
zabbix_get -s <agent_ip> -k custom.disk.iops_read
zabbix_get -s <agent_ip> -k custom.disk.iops_write

# Memory
zabbix_get -s <agent_ip> -k custom.memory.swap_used_percent

# Network
zabbix_get -s <agent_ip> -k custom.network.errors

# NVMe Temperature (replace nvme0n1 with your disk)
zabbix_get -s <agent_ip> -k custom.disk.nvme_temp[nvme0n1]
```

## Why These Metrics Matter for Webapp Performance

### I/O Wait (custom.disk.io_wait)
High I/O wait means the CPU is idle waiting for disk operations to complete. This is the #1 indicator of disk bottlenecks causing slow webapps.

### Disk Latency (custom.disk.read_latency, custom.disk.write_latency)
High latency indicates slow disk responses. Database queries and file operations will be slow.

### IOPS (custom.disk.iops_read, custom.disk.iops_write)
Tracks disk throughput. If IOPS are maxed out, adding caching or upgrading storage may help.

### Swap Usage (custom.memory.swap_used_percent)
When the system runs out of RAM and starts swapping to disk, everything slows down dramatically.

### Network Errors (custom.network.errors)
Packet drops can cause connection timeouts and retries, slowing down webapp responses.

## Next Steps

1. Test the new keys on a test system first
2. Add items to your Zabbix template
3. Create triggers with appropriate thresholds for your environment
4. Monitor for a few days to establish baseline values
5. Adjust trigger thresholds based on your normal operating conditions
