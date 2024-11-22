# Variables
$repoUrl = "https://github.com/BrockBlaze/zabbixAgent"
$downloadDir = "C:\Temp\zabbixAgent"
$scriptsDir = "C:\Program Files\Zabbix Agent\scripts"
$configFile = "C:\Program Files\Zabbix Agent\zabbix_agentd.conf"

# Step 1: Download and install Zabbix Agent
Invoke-WebRequest -Uri "https://cdn.zabbix.com/zabbix/binaries/stable/6.0/6.0.19/zabbix_agent-6.0.19-windows-amd64-openssl.msi" -OutFile "$downloadDir\zabbix_agent.msi"
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $downloadDir\zabbix_agent.msi /quiet" -Wait

# Step 2: Clone repository
git clone $repoUrl $downloadDir

# Step 3: Copy custom scripts
New-Item -ItemType Directory -Path $scriptsDir -Force
Copy-Item -Path "$downloadDir\scripts\*" -Destination $scriptsDir -Recurse -Force

# Step 4: Apply custom configuration
Copy-Item -Path "$downloadDir\zabbix_agentd.conf" -Destination $configFile -Force
(Get-Content $configFile) -replace 'Hostname=.*', "Hostname=$env:COMPUTERNAME" | Set-Content $configFile

# Step 5: Restart and enable service
Restart-Service -Name "Zabbix Agent"
Set-Service -Name "Zabbix Agent" -StartupType Automatic

# Cleanup
Remove-Item -Recurse -Force $downloadDir
Write-Host "Zabbix Agent installed and configured successfully!"