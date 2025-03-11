# Zabbix Agent Enhanced Installer

This repository contains scripts to automate the installation and configuration of Zabbix Agent with enhanced monitoring capabilities.

## Features

- Automatic installation and configuration of Zabbix Agent
- Robust error handling and validation
- Enhanced monitoring capabilities:
  - CPU temperature monitoring
  - System health monitoring
  - Login monitoring (failed and successful logins)
  - Top processes monitoring (CPU usage)

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/BrockBlaze/zabbixAgent.git
   ```

2. Navigate to the linux directory:
   ```
   cd zabbixAgent/linux
   ```

3. Make the install script executable:
   ```
   chmod +x install.sh
   ```

4. Run the install script with sudo:
   ```
   sudo ./install.sh
   ```

5. Follow the prompts to enter your Zabbix server IP and hostname.

## Monitoring Scripts

The installer includes several monitoring scripts:

- `cpu_temp.sh`: Monitors CPU temperature
- `login_monitoring.sh`: Monitors system logins
- `system_health.sh`: Provides comprehensive system health metrics
- `top_processes.sh`: Returns the top 10 processes by CPU usage

## Available UserParameters

After installation, these Zabbix UserParameters will be available:

- `cpu.temperature`: Get CPU temperature
- `login.monitoring`: Get full login monitoring data (JSON)
- `login.monitoring.failed_logins`: Get count of failed logins
- `login.monitoring.successful_logins`: Get count of successful logins
- `login.monitoring.total_attempts`: Get total login attempts
- `login.monitoring.user_details`: Get detailed user login information
- `login.monitoring.events`: Get login events timeline
- `system.health`: Get comprehensive system health data
- `system.top`: Get top 10 processes by CPU usage

## Uninstallation

To uninstall the Zabbix Agent and all added monitoring:

```
sudo ./uninstall.sh
```

## License

This project is licensed under the terms of the license included in the repository. 