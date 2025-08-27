#!/bin/bash

# Zabbix Agent Bulk Deployment Script
# Version: 1.0.0
# For managing multiple Ubuntu servers

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
HOSTS_FILE="${1:-hosts.txt}"
ZABBIX_SERVER="${ZABBIX_SERVER:-192.168.70.2}"
SSH_USER="${SSH_USER:-root}"
SSH_KEY="${SSH_KEY:-}"
LOG_FILE="bulk_deploy_$(date +%Y%m%d_%H%M%S).log"
PARALLEL_JOBS=5

# Functions
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }

# Check if hosts file exists
if [ ! -f "$HOSTS_FILE" ]; then
    log_error "Hosts file not found: $HOSTS_FILE"
    echo "Usage: $0 [hosts_file]"
    echo ""
    echo "Create a hosts file with format:"
    echo "  hostname1 ip_address1"
    echo "  hostname2 ip_address2"
    echo ""
    echo "Or use simple format:"
    echo "  192.168.1.10"
    echo "  192.168.1.11"
    exit 1
fi

# Create sample hosts file if requested
if [ "$HOSTS_FILE" = "--create-sample" ]; then
    cat > sample_hosts.txt << EOF
# Zabbix Agent Deployment Hosts File
# Format: hostname ip_address
# Or just: ip_address

web-server-01 192.168.1.10
web-server-02 192.168.1.11
db-server-01 192.168.1.20
app-server-01 192.168.1.30

# You can also just list IPs:
# 192.168.1.40
# 192.168.1.41
EOF
    log_success "Sample hosts file created: sample_hosts.txt"
    exit 0
fi

log_info "==================================================="
log_info " Zabbix Agent Bulk Deployment"
log_info "==================================================="
log_info "Hosts file: $HOSTS_FILE"
log_info "Zabbix Server: $ZABBIX_SERVER"
log_info "SSH User: $SSH_USER"
log_info "Parallel Jobs: $PARALLEL_JOBS"
echo ""

# Count hosts
TOTAL_HOSTS=$(grep -v '^#' "$HOSTS_FILE" | grep -v '^$' | wc -l)
log_info "Found $TOTAL_HOSTS hosts to deploy"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

# Remote installation script
REMOTE_INSTALL_SCRIPT='
#!/bin/bash
set -e

# Download and run the auto installer
echo "Downloading Zabbix agent installer..."
wget -q -O /tmp/install_auto.sh https://raw.githubusercontent.com/yourusername/zabbix-scripts/main/install_auto.sh || {
    # Fallback to local copy
    cat > /tmp/install_auto.sh << "INSTALLER_EOF"
'"$(cat install_auto.sh)"'
INSTALLER_EOF
}

chmod +x /tmp/install_auto.sh
echo "1" | ZABBIX_SERVER='"$ZABBIX_SERVER"' /tmp/install_auto.sh

# Return status
if systemctl is-active --quiet zabbix-agent2 || systemctl is-active --quiet zabbix-agent; then
    echo "SUCCESS"
    exit 0
else
    echo "FAILED"
    exit 1
fi
'

# Deploy to single host
deploy_to_host() {
    local host_entry="$1"
    local host_ip=""
    local hostname=""
    
    # Parse host entry
    if echo "$host_entry" | grep -q ' '; then
        hostname=$(echo "$host_entry" | awk '{print $1}')
        host_ip=$(echo "$host_entry" | awk '{print $2}')
    else
        host_ip="$host_entry"
        hostname=""
    fi
    
    echo -e "\n${BLUE}Deploying to: $host_ip${NC}"
    
    # Test SSH connection
    if ! ssh $SSH_OPTS "${SSH_USER}@${host_ip}" "echo 'SSH OK'" >/dev/null 2>&1; then
        log_error "Cannot connect to $host_ip"
        echo "$host_ip FAILED - SSH connection failed" >> "$LOG_FILE"
        return 1
    fi
    
    # Deploy agent
    local result
    result=$(ssh $SSH_OPTS "${SSH_USER}@${host_ip}" "$REMOTE_INSTALL_SCRIPT" 2>&1 | tail -1)
    
    if [ "$result" = "SUCCESS" ]; then
        log_success "$host_ip - Agent installed successfully"
        echo "$host_ip SUCCESS" >> "$LOG_FILE"
        
        # Get agent info
        local agent_info
        agent_info=$(ssh $SSH_OPTS "${SSH_USER}@${host_ip}" "
            if systemctl is-active --quiet zabbix-agent2; then
                echo 'zabbix-agent2'
            elif systemctl is-active --quiet zabbix-agent; then
                echo 'zabbix-agent'
            fi
        ")
        
        echo "  Agent type: $agent_info"
        return 0
    else
        log_error "$host_ip - Installation failed"
        echo "$host_ip FAILED" >> "$LOG_FILE"
        return 1
    fi
}

# Deploy with parallel execution
deploy_parallel() {
    local success_count=0
    local fail_count=0
    local pids=()
    local count=0
    
    while IFS= read -r host_entry; do
        # Skip comments and empty lines
        [[ "$host_entry" =~ ^#.*$ ]] && continue
        [[ -z "$host_entry" ]] && continue
        
        # Run in background with job control
        (deploy_to_host "$host_entry") &
        pids+=($!)
        count=$((count + 1))
        
        # Wait if we've reached parallel limit
        if [ ${#pids[@]} -ge $PARALLEL_JOBS ]; then
            for pid in "${pids[@]}"; do
                wait "$pid"
                if [ $? -eq 0 ]; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
            done
            pids=()
        fi
    done < "$HOSTS_FILE"
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    # Summary
    echo ""
    log_info "==================================================="
    log_info " Deployment Summary"
    log_info "==================================================="
    log_success "Successful: $success_count"
    log_error "Failed: $fail_count"
    log_info "Total: $((success_count + fail_count))"
    log_info "Log file: $LOG_FILE"
}

# Generate Ansible playbook (optional)
generate_ansible_playbook() {
    cat > zabbix_deploy.yml << 'EOF'
---
- name: Deploy Zabbix Agent to Ubuntu Servers
  hosts: all
  become: yes
  vars:
    zabbix_server: "{{ lookup('env', 'ZABBIX_SERVER') | default('192.168.70.2') }}"
  
  tasks:
    - name: Download installer script
      get_url:
        url: https://raw.githubusercontent.com/yourusername/zabbix-scripts/main/install_auto.sh
        dest: /tmp/install_auto.sh
        mode: '0755'
    
    - name: Run installer
      shell: |
        echo "1" | ZABBIX_SERVER={{ zabbix_server }} /tmp/install_auto.sh
      register: install_result
    
    - name: Verify agent is running
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      with_items:
        - zabbix-agent2
        - zabbix-agent
      ignore_errors: yes
    
    - name: Display installation result
      debug:
        msg: "Installation completed on {{ inventory_hostname }}"
EOF
    
    log_info "Ansible playbook generated: zabbix_deploy.yml"
}

# Generate configuration for Configuration Management tools
generate_puppet_manifest() {
    cat > zabbix_agent.pp << 'EOF'
# Puppet manifest for Zabbix Agent deployment

class zabbix_agent (
  $zabbix_server = '192.168.70.2',
) {
  
  # Download installer
  file { '/tmp/install_auto.sh':
    source => 'https://raw.githubusercontent.com/yourusername/zabbix-scripts/main/install_auto.sh',
    mode   => '0755',
  }
  
  # Run installer
  exec { 'install_zabbix_agent':
    command => "echo '1' | ZABBIX_SERVER=${zabbix_server} /tmp/install_auto.sh",
    path    => ['/bin', '/usr/bin'],
    creates => '/etc/zabbix/zabbix_agent2.conf',
    require => File['/tmp/install_auto.sh'],
  }
  
  # Ensure service is running
  service { ['zabbix-agent2', 'zabbix-agent']:
    ensure  => running,
    enable  => true,
    require => Exec['install_zabbix_agent'],
  }
}
EOF
    
    log_info "Puppet manifest generated: zabbix_agent.pp"
}

# Main menu
show_menu() {
    echo ""
    echo "Select deployment method:"
    echo "  1) Deploy to all hosts (parallel)"
    echo "  2) Deploy to all hosts (sequential)"
    echo "  3) Test single host"
    echo "  4) Generate Ansible playbook"
    echo "  5) Generate Puppet manifest"
    echo "  6) Create sample hosts file"
    echo "  0) Exit"
    echo ""
    read -p "Choice: " choice
    
    case $choice in
        1)
            deploy_parallel
            ;;
        2)
            PARALLEL_JOBS=1
            deploy_parallel
            ;;
        3)
            read -p "Enter host IP: " test_host
            deploy_to_host "$test_host"
            ;;
        4)
            generate_ansible_playbook
            ;;
        5)
            generate_puppet_manifest
            ;;
        6)
            $0 --create-sample
            ;;
        0)
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            show_menu
            ;;
    esac
}

# Auto-deploy if hosts file provided, otherwise show menu
if [ -f "$HOSTS_FILE" ] && [ "$HOSTS_FILE" != "hosts.txt" ]; then
    deploy_parallel
else
    show_menu
fi