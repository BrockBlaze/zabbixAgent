# Rithm Zabbix Agent Installer

Automated installation of Zabbix Agent with custom monitoring for Ubuntu Server (20.04, 24.04) and Proxmox VE.

## Features

- **CPU Monitoring**: Temperature, load averages, utilization
- **NVME/SSD Monitoring**: Temperature, SMART health status
- **Login Tracking**: Failed/successful login attempts
- **Webapp Performance Metrics**: I/O wait, disk latency, IOPS, memory/swap, network connections
- **System Health**: Service status, process monitoring, security updates

## Supported Systems

- Ubuntu Server 20.04 LTS → Zabbix 6.0
- Ubuntu Server 24.04 LTS → Zabbix 7.0
- Proxmox VE 8.x → Zabbix 7.0

## Quick Installation

### 1. Clone Repository

```bash
git clone https://github.com/BrockBlaze/zabbixAgent.git
cd zabbixAgent
```

### 2. Set Environment Variables (Optional)

```bash
export ZABBIX_SERVER=192.168.70.2  # Default: 192.168.70.2
export ZABBIX_HOSTNAME=$(hostname)  # Default: system hostname
```

### 3. Run Installer

```bash
sudo bash linux/install.sh
```

Or with custom Zabbix server:

```bash
sudo ZABBIX_SERVER=10.0.0.100 bash linux/install.sh
```

## What Gets Installed

- **Zabbix Agent** (agent2 if available, fallback to agent)
- **Monitoring Tools**: lm-sensors, smartmontools, sysstat, nvme-cli, jq
- **Custom Parameters**: 40+ monitoring keys for comprehensive system monitoring
- **Sudo Permissions**: Configured for zabbix user to run monitoring commands

## Monitored Metrics

### Critical for Webapp Performance

- `custom.disk.io_wait` - I/O wait percentage (high = disk bottleneck)
- `custom.disk.read_latency` - Disk read latency in ms
- `custom.disk.write_latency` - Disk write latency in ms
- `custom.disk.iops_read` - Read operations per second
- `custom.disk.iops_write` - Write operations per second
- `custom.memory.swap_used_percent` - Swap pressure
- `custom.network.connections_established` - Active connections
- `custom.network.errors` - Packet drops/errors
- `custom.process.top_cpu` - Top CPU consuming process
- `custom.process.top_memory` - Top memory consuming process

### Hardware Monitoring

- `custom.cpu.temperature` - CPU temperature
- `custom.disk.temperature[*]` - Disk temperature (NVMe/SSD)
- `custom.disk.nvme_temp[*]` - NVMe-specific temperature
- `custom.disk.smart_status[*]` - SMART health (1=healthy, 0=failed)

### Login & Security

- `custom.login.failed_last_hour` - Failed login attempts
- `custom.login.successful_last_hour` - Successful logins
- `custom.login.current_users` - Currently logged in users
- `custom.security.updates_available` - Available system updates
- `custom.security.updates_security` - Available security updates

### Full List

See [MONITORING_KEYS.md](MONITORING_KEYS.md) for complete reference.

## Zabbix Server Configuration

### 1. Import Template

1. Go to **Configuration → Templates**
2. Click **Import**
3. Select `zbx_export_templates.yaml` from this repository
4. Click **Import**

### 2. Add Host

1. Go to **Configuration → Hosts**
2. Click **Create host**
3. Configure:
   - **Host name**: `<your_hostname>` (must match ZABBIX_HOSTNAME)
   - **Groups**: `Linux servers` or `Rithm`
   - **Interfaces**: Agent, `<server_ip>`, port `10050`
   - **Templates**: Link `Rithm` template

### 3. Test Connection

From your Zabbix server:

```bash
zabbix_get -s <agent_ip> -k agent.ping
zabbix_get -s <agent_ip> -k custom.cpu.temperature
zabbix_get -s <agent_ip> -k custom.disk.io_wait
```

## Troubleshooting Slow Webapps

Monitor these metrics to diagnose performance issues:

| Metric | High Value Indicates |
|--------|---------------------|
| `custom.disk.io_wait` > 20% | Disk bottleneck (slow DB queries, log writes) |
| `custom.disk.read_latency` > 50ms | Slow disk reads |
| `custom.disk.write_latency` > 50ms | Slow disk writes |
| `custom.memory.swap_used_percent` > 10% | System out of RAM, swapping to disk |
| `custom.network.errors` > 0 | Packet loss, network issues |
| `system.cpu.util` > 80% | CPU exhaustion |
| `custom.network.connections_established` > 1000 | Too many connections or connection leaks |

## Installation Logs

- Installation log: `/var/log/zabbix/install.log`
- Agent log: `/var/log/zabbix/zabbix_agent2.log`
- Config: `/etc/zabbix/zabbix_agent2.conf`
- Custom parameters: `/etc/zabbix/zabbix_agent2.d/rithm_custom.conf`

## Uninstallation

```bash
sudo systemctl stop zabbix-agent2
sudo apt-get remove --purge zabbix-agent2 zabbix-agent
sudo rm -rf /etc/zabbix /var/log/zabbix
sudo rm -f /etc/sudoers.d/zabbix
```

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues or questions, check:
- Installation log: `cat /var/log/zabbix/install.log`
- Agent status: `systemctl status zabbix-agent2`
- Test metrics: `zabbix_get -s localhost -k custom.cpu.temperature`
