# Set Variables
$repoUrl = "https://github.com/BrockBlaze/zabbixAgent/archive/refs/heads/main.zip"
$tempDir = "C:\Temp"
$downloadDir = "C:\Temp\zabbixAgent"
$installDir = "C:\Program Files\Zabbix Agent"
$scriptsDir = "$installDir\scripts"
$configFile = "$installDir\zabbix_agentd.conf"

# Ensure required folders exist
if (-Not (Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

# Download and Extract Repository
Write-Host "Downloading repository..."
$zipPath = "$downloadDir\zabbixAgent.zip"
Invoke-WebRequest -Uri $repoUrl -OutFile $zipPath

Write-Host "Extracting repository..."
Expand-Archive -Path $zipPath -DestinationPath $downloadDir -Force

# Install Zabbix Agent
Write-Host "Installing Zabbix Agent..."
$installerPath = "$downloadDir\zabbixAgent-main\windows\zabbix_agent.msi"
Start-Process  $installerPath -Wait

# Set Permissions and Execution Policies
Write-Host "Setting permissions..."
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force

#Create Zabbix Agent Script Directory
if (-Not (Test-Path -Path $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
}

# Copy configuration and scripts
Write-Host "Copying scripts..."
Copy-Item -Path "$downloadDir\zabbixAgent-main\windows\scripts\*" -Destination $scriptsDir -Force

# Add UserParameter entries to configuration file
Write-Host "Adding UserParameter entries to configuration..."
$customParameters = @"
# Custom UserParameters
UserParameter=login.attempts,powershell -ExecutionPolicy Bypass -File "$scriptsDir\login_monitoring.ps1"
UserParameter=cpu.temperature,powershell -ExecutionPolicy Bypass -File "$scriptsDir\cpu_temp.ps1"
"@

if (Test-Path $configFile) {
    Add-Content -Path $configFile -Value $customParameters
}
else {
    Write-Host "Configuration file not found! Creating a new one..."
    Set-Content -Path $configFile -Value $customParameters
}

# Configure Zabbix Agent Service
Write-Host "Configuring Zabbix Agent service..."
Restart-Service -Name "Zabbix Agent"
Set-Service -Name "Zabbix Agent" -StartupType Automatic

# Clean up
Write-Host "Cleaning up..."
Remove-Item -Path $tempDir -Recurse -Force -Confirm:$false
Write-Host "Installation completed successfully!"
