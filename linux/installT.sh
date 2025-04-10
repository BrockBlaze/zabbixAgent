#!/bin/bash

set -e

# --- Configurable values ---
ZBX_SERVER="your.zabbix.server.ip"   # <-- Change this!
AGENT_HOSTNAME="$(hostname)"         # Optional: set a custom hostname

# --- Install Zabbix repository & agent 2 ---
echo "Installing Zabbix Agent 2..."
wget https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu$(lsb_release -rs)_all.deb
dpkg -i zabbix-release_6.4-1+ubuntu$(lsb_release -rs)_all.deb
apt update
apt install -y zabbix-agent2 lm-sensors

# --- Setup sensors (optional: run interactively first time) ---
yes | sensors-detect || true

# --- Create the custom script directory ---
mkdir -p /etc/zabbix/scripts

# --- CPU temp script ---
cat <<'EOF' > /etc/zabbix/scripts/cpu_temp.sh
#!/bin/bash
TEMP=$(sensors | awk '
/k10temp/ {found=1}
/Tctl:/ && found {gsub(/\+/,""); gsub(/°C/,""); print $2; exit}
/CPU Package:/ {gsub(/\+/,""); gsub(/°C/,""); print $3; exit}
')
echo "$TEMP"
EOF

chmod +x /etc/zabbix/scripts/cpu_temp.sh

# --- Create UserParameter config ---
cat <<EOF > /etc/zabbix/zabbix_agent2.d/userparameter_cpu_temp.conf
UserParameter=system.cpu.temp,/etc/zabbix/scripts/cpu_temp.sh
EOF

# --- Configure Zabbix agent ---
sed -i "s/^Server=127.0.0.1/Server=$ZBX_SERVER/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=127.0.0.1/ServerActive=$ZBX_SERVER/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=Zabbix server/Hostname=$AGENT_HOSTNAME/" /etc/zabbix/zabbix_agent2.conf

# --- Restart and enable the agent ---
systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

echo "✅ Zabbix Agent 2 installed and configured."
echo "ℹ️  Don't forget to add this host in the Zabbix frontend with the key: system.cpu.temp"
