# Set Variables
$repoUrl = "https://github.com/BrockBlaze/zabbixAgnet/archive/refs/heads/main.zip"
$downloadDir = "C:\Temp\zabbixAgent"
$installDir = "C:\Program Files\Zabbix Agent"
$scriptsDir = "$installDir\scripts"

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

# Copy configuration and scripts
Write-Host "Copying configuration and scripts..."
Copy-Item -Path "$downloadDir\BrockBlaze\windows\scripts\*" -Destination $scriptsDir -Force
Copy-Item -Path "$downloadDir\BrockBlaze\windows\zabbix_agentd.conf" -Destination "$installDir" -Force

# Install Zabbix Agent
Write-Host "Installing Zabbix Agent..."
$installerPath = "$downloadDir\BrockBlaze\windows\zabbix_agent.msi"
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $installerPath /quiet" -Wait

# Set Permissions and Execution Policies
Write-Host "Setting permissions..."
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force

# Configure Zabbix Agent Service
Write-Host "Configuring Zabbix Agent service..."
Restart-Service -Name "Zabbix Agent"
Set-Service -Name "Zabbix Agent" -StartupType Automatic

# Clean up
Write-Host "Cleaning up..."
Remove-Item -Path $zipPath -Force
Write-Host "Installation completed successfully!"
