# Zabbix Agent Simplified Deployment Guide

## Overview
This guide provides simplified methods for installing Zabbix agents on Ubuntu servers (20.04+) and configuring monitoring on the Zabbix host.

## Quick Start

### Single Server Installation

#### Method 1: Express Install (Recommended)
```bash
# Download and run with defaults
curl -sSL https://yourserver/install_auto.sh | sudo bash

# Or with custom Zabbix server
curl -sSL https://yourserver/install_auto.sh | sudo ZABBIX_SERVER=10.0.0.100 bash
```

#### Method 2: Interactive Install
```bash
# Download the installer
wget https://yourserver/install_auto.sh
chmod +x install_auto.sh

# Run with options:
# Option 1: Express (all defaults)
# Option 2: Custom server IP only  
# Option 3: Full custom configuration
sudo ./install_auto.sh
```

### Bulk Deployment

#### For Multiple Servers
1. Create a hosts file:
```
# hosts.txt
web-01 192.168.1.10
web-02 192.168.1.11
db-01 192.168.1.20
app-01 192.168.1.30
```

2. Run bulk deployment:
```bash
./bulk_deploy.sh hosts.txt
```

#### Using Ansible
```bash
# Generate playbook
./bulk_deploy.sh
# Select option 4

# Run deployment
ansible-playbook -i inventory zabbix_deploy.yml
```

## Zabbix Server Configuration

### Automatic Template Import

1. After installation, find the generated template:
```
/tmp/zabbix_template_[hostname].json
```

2. Import to Zabbix:
   - Go to Configuration → Templates
   - Click Import
   - Select the JSON file
   - Click Import

### Manual Host Addition

1. Go to Configuration → Hosts
2. Click Create Host
3. Configure:
   - **Host name**: Use server hostname
   - **Groups**: Linux servers
   - **Interfaces**: Agent, IP address, port 10050
   - **Templates**: 
     - Template Linux Auto Custom
     - Linux by Zabbix agent

## Available Monitoring Keys

### System Metrics
- `custom.cpu.temp` - CPU temperature
- `custom.mem.available` - Available memory
- `custom.updates.available` - Pending system updates

### Network Monitoring  
- `custom.net.connections` - Established connections
- `custom.net.listening` - Listening ports

### Disk Monitoring
- `custom.disk.count` - Number of physical disks
- `custom.disk.temp[sda]` - Disk temperature
- `custom.disk.smart[sda]` - SMART health status

### Service Monitoring
- `custom.service.status[nginx]` - Service status check
- `custom.docker.containers` - Docker containers running

### Process Monitoring
- `custom.proc.top.cpu` - Top CPU consuming process
- `custom.proc.top.mem` - Top memory consuming process

## Testing Installation

### On the Agent Server
```bash
# Check agent status
systemctl status zabbix-agent2

# Test agent response
zabbix_get -s localhost -k agent.ping

# Test custom metric
zabbix_get -s localhost -k custom.cpu.temp

# View logs
tail -f /var/log/zabbix/zabbix_agent2.log
```

### From Zabbix Server
```bash
# Test connectivity
zabbix_get -s <agent_ip> -k agent.ping

# Test custom metrics
zabbix_get -s <agent_ip> -k custom.cpu.temp
zabbix_get -s <agent_ip> -k custom.disk.count
```

## Troubleshooting

### Common Issues

#### Agent Not Starting
```bash
# Check configuration
zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf -t agent.ping

# Check for port conflicts
ss -tlnp | grep 10050

# Review logs
journalctl -u zabbix-agent2 -n 50
```

#### Connection Refused
```bash
# Check firewall
ufw status
ufw allow 10050/tcp

# Verify server IP in config
grep ^Server= /etc/zabbix/zabbix_agent2.conf

# Restart agent
systemctl restart zabbix-agent2
```

#### Missing Metrics
```bash
# Check sudo permissions
sudo -u zabbix sudo -l

# Test commands manually
sudo -u zabbix sensors
sudo -u zabbix smartctl -A /dev/sda
```

## Advanced Configuration

### Environment Variables
```bash
# Set for all deployments
export ZABBIX_SERVER=10.0.0.100
export SSH_USER=ubuntu
export SSH_KEY=/path/to/key.pem

# Run bulk deployment
./bulk_deploy.sh hosts.txt
```

### Custom UserParameters
Add to `/etc/zabbix/zabbix_agent2.conf`:
```
UserParameter=custom.app.metric,/path/to/script.sh
UserParameter=custom.db.connections,mysql -e "show processlist" | wc -l
```

### Security Hardening
```bash
# Limit allowed commands
echo "AllowKey=system.run[/usr/local/bin/safe-script.sh]" >> /etc/zabbix/zabbix_agent2.conf
echo "DenyKey=system.run[*]" >> /etc/zabbix/zabbix_agent2.conf

# Use passive checks only
sed -i 's/^ServerActive=/#ServerActive=/' /etc/zabbix/zabbix_agent2.conf
```

## Automation Examples

### CI/CD Integration
```yaml
# GitLab CI
deploy_zabbix:
  script:
    - ssh user@server 'curl -sSL https://yourserver/install_auto.sh | sudo bash'
```

### Terraform
```hcl
resource "null_resource" "zabbix_agent" {
  provisioner "remote-exec" {
    inline = [
      "curl -sSL https://yourserver/install_auto.sh | sudo ZABBIX_SERVER=${var.zabbix_server} bash"
    ]
  }
}
```

### Docker
```dockerfile
FROM ubuntu:22.04
RUN apt-get update && \
    curl -sSL https://yourserver/install_auto.sh | ZABBIX_SERVER=zabbix.server bash
```

## Best Practices

1. **Use Configuration Management**: For production, use Ansible/Puppet/Chef
2. **Secure Communications**: Enable PSK encryption for agent-server communication
3. **Monitor the Monitors**: Set up alerts for agent availability
4. **Regular Updates**: Keep agents updated with security patches
5. **Log Rotation**: Configure proper log rotation for agent logs
6. **Resource Limits**: Set appropriate timeout and buffer values
7. **Documentation**: Keep inventory of all monitored hosts

## Support

### Log Locations
- Installation log: `/var/log/zabbix/auto_install.log`
- Agent logs: `/var/log/zabbix/zabbix_agent2.log`
- Summary: `/tmp/zabbix_config_summary.txt`

### Configuration Files
- Main config: `/etc/zabbix/zabbix_agent2.conf`
- Custom scripts: `/etc/zabbix/scripts/`
- Sudo permissions: `/etc/sudoers.d/zabbix`

### Getting Help
1. Check installation summary: `cat /tmp/zabbix_config_summary.txt`
2. Review agent status: `systemctl status zabbix-agent2`
3. Test connectivity: `zabbix_get -s localhost -k agent.ping`
4. Check Zabbix server latest data for the host