# Rithm Zabbix Agent Installer

This repository provides an automated installer for setting up the Zabbix Agent on Linux and Windows servers, pre-configured for monitoring system hardware, logins, and logs.

## Features

- **Hardware Monitoring**: CPU, memory, disk, and temperature monitoring.
- **Login Monitoring**: Tracks successful and failed login attempts.
- **Log Monitoring**: Monitors system logs for specified events.

## Requirements

- **Linux**: Ubuntu/Debian-based systems
- **Windows**: Windows 7 or higher
- **Zabbix Server**: A Zabbix server must be running to monitor these agents.

## Installation

### Linux

1. Clone the repository:
   ```bash
   git clone https://github.com/BrockBlaze/zabbixAgent.git
   cd zabbixAgent
   sudo chmod +x linux/install.sh
   sudo ./linux/install.sh
### Windows