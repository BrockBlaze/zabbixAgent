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

1. Run these commands in the terminal:
   ```bash
   git clone https://github.com/BrockBlaze/zabbixAgent.git
   ```
   ```bash
   cd zabbixAgent
   ```
   ```bash
   sudo chmod +x linux/install.sh
   ```
   ```bash
   sudo ./linux/install.sh
   ```
   

### Windows

1. Download and install [Git](https://git-scm.com/download/win).

2. Download and install [OpenHardwareMonitor](https://openhardwaremonitor.org/downloads/).
   - **a**. Unzip files to C:\Tools\OpenHardwareMonitor\
   - **b**. Run OpenHardwareMonitor.exe
   - **c**. Go to Options Tab of OpenHardwareMonitor and Check Start Minimized, Minimize To Tray, Minimize On Close, and Run On Windows Startup. Make sure to Check Remote Web Server, Run.

2. Run this in PowerShell as administrator:
   ```powershell
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/BrockBlaze/zabbixAgent/main/windows/install.ps1" -OutFile "install.ps1"
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```