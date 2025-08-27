# 🧹 Rithm Zabbix Agent - Clean Deployment Guide

## ✨ **What's New:**
- **Single installer script** - No more multiple files
- **Consistent `custom.*` naming** - All parameters follow same format
- **Comprehensive monitoring** - 30+ metrics with clean organization
- **One-liner deployment** - SSH and run, that's it
- **Matching Zabbix template** - Import once, use everywhere

---

## 🚀 **Quick Deployment**

### For Arc (192.168.68.146):
```bash
ssh root@192.168.68.146 "curl -sSL [your-url]/install_clean.sh | sudo ZABBIX_SERVER=192.168.70.2 HOSTNAME=Arc bash"
```

### For Cobalt (192.168.70.35):
```bash
ssh root@192.168.70.35 "curl -sSL [your-url]/install_clean.sh | sudo ZABBIX_SERVER=192.168.70.2 HOSTNAME=Cobalt bash"
```

### Or manually on each server:
```bash
# Copy install_clean.sh to server, then:
chmod +x install_clean.sh
sudo ZABBIX_SERVER=192.168.70.2 HOSTNAME=YourHostname ./install_clean.sh
```

---

## 📊 **Template Import**

1. **Import Template** (one time only):
   - File: `Template_Rithm_Custom.json`
   - Zabbix: Configuration → Templates → Import

2. **Add Hosts**:
   - Arc: IP `192.168.68.146`, Template `Template Rithm Custom`  
   - Cobalt: IP `192.168.70.35`, Template `Template Rithm Custom`

---

## 🎯 **New Custom Parameters**

### **System Monitoring**
- `custom.system.uptime` - Days uptime
- `custom.system.kernel` - Kernel version  
- `custom.system.reboot_required` - Reboot needed flag

### **CPU Monitoring** 
- `custom.cpu.temperature` - CPU temp from sensors
- `custom.cpu.cores` - Number of cores
- `custom.cpu.load_1min` / `custom.cpu.load_5min` - Load averages

### **Memory Monitoring**
- `custom.memory.available` - Available bytes
- `custom.memory.used_percent` - Usage percentage  
- `custom.memory.swap_used` - Swap usage

### **Disk Monitoring**
- `custom.disk.count` - Physical disk count
- `custom.disk.root_usage` - Root filesystem %
- `custom.disk.temperature[device]` - Per-disk temperature
- `custom.disk.smart_status[device]` - SMART health (1=OK, 0=Failed)
- `custom.disk.io_wait` - I/O wait percentage

### **Network Monitoring**
- `custom.network.connections_established` - Active connections
- `custom.network.connections_listening` - Listening ports  
- `custom.network.connections_timewait` - TIME_WAIT connections

### **Service Monitoring** 
- `custom.service.status[service]` - Service status
- `custom.service.count_running` - Running services
- `custom.service.count_failed` - Failed services

### **Process Monitoring**
- `custom.process.top_cpu` - Top CPU process (PID:CPU%:Command)
- `custom.process.top_memory` - Top memory process (PID:MEM%:Command) 
- `custom.process.zombie_count` - Zombie processes
- `custom.process.total_count` - Total processes

### **Login Monitoring**
- `custom.login.failed_last_hour` - Failed logins/hour
- `custom.login.successful_last_hour` - Successful logins/hour
- `custom.login.last_user` - Last user to login
- `custom.login.current_users` - Currently logged in users

### **Security Monitoring**
- `custom.security.updates_available` - Available updates
- `custom.security.updates_security` - Security updates  
- `custom.security.sudo_attempts` - Sudo attempts today

### **Log Monitoring**
- `custom.log.auth_errors` - Auth errors (last 100 lines)
- `custom.log.syslog_errors` - Syslog errors (last 100 lines)
- `custom.log.kern_errors` - Kernel errors (last 100 lines)

### **Docker Monitoring** (if available)
- `custom.docker.containers_running` - Running containers
- `custom.docker.containers_total` - Total containers
- `custom.docker.images_count` - Number of images

### **Discovery Rules**
- `custom.discovery.disks` - Auto-discover physical disks
- `custom.discovery.services` - Auto-discover enabled services  
- `custom.discovery.network_interfaces` - Auto-discover network interfaces

---

## ✅ **Testing Commands**

From Zabbix server (192.168.70.2):
```bash
# Basic connectivity
zabbix_get -s 192.168.68.146 -k agent.ping
zabbix_get -s 192.168.70.35 -k agent.ping

# Test key custom parameters  
zabbix_get -s 192.168.68.146 -k custom.cpu.temperature
zabbix_get -s 192.168.68.146 -k custom.memory.available
zabbix_get -s 192.168.68.146 -k custom.disk.count
zabbix_get -s 192.168.68.146 -k custom.network.connections_established

# Test discovery
zabbix_get -s 192.168.68.146 -k custom.discovery.disks
zabbix_get -s 192.168.68.146 -k custom.discovery.services
```

---

## 🔧 **What the Installer Does**

1. **Auto-detects Ubuntu version** and installs correct Zabbix version
2. **Installs monitoring tools** (lm-sensors, smartmontools, sysstat) 
3. **Configures hardware sensors** automatically
4. **Creates consistent custom parameters** with `custom.*` naming
5. **Sets up sudo permissions** for zabbix user monitoring
6. **Tests installation** and reports status
7. **Generates template info** for easy Zabbix configuration

---

## 🎉 **Benefits**

- **✅ Consistent naming** - All `custom.*` parameters
- **✅ Single script** - No more file copying/multiple scripts  
- **✅ Auto-detection** - Works on Ubuntu 20.04, 22.04, 24.04+
- **✅ Comprehensive** - 30+ monitoring parameters
- **✅ Discovery rules** - Auto-finds disks, services, interfaces
- **✅ Clean triggers** - Smart thresholds with macros
- **✅ Dashboard ready** - Pre-built overview dashboard

---

## 📋 **Ready to Deploy!**

Both Arc and Cobalt can now be deployed with a single command each. The template works for both servers and any future Ubuntu servers you add.

**File Locations:**
- Installer: `install_clean.sh` 
- Template: `Template_Rithm_Custom.json`
- This guide: `CLEAN_DEPLOYMENT.md`