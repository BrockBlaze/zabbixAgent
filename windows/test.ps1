# Set variables
$installerUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/6.0/6.0.20/zabbix_agent-6.0.20-x86_64.msi"
$tempDir = "C:\Temp\zabbixAgent"
$installerPath = "$tempDir\zabbix_agent.msi"

# Create temporary directory
Write-Host "Creating temporary directory: $tempDir"
if (!(Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force
}

# Download the Zabbix Agent installer
Write-Host "Downloading Zabbix Agent installer..."
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -ErrorAction Stop

# Verify the installer exists
if (!(Test-Path $installerPath)) {
    Write-Host "Error: Failed to download the installer."
    exit 1
}
else {
    Write-Host "Installer downloaded successfully."
}

# Install Zabbix Agent
Write-Host "Installing Zabbix Agent..."
$installArgs = "/i `"$installerPath`" /quiet /norestart"
Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -NoNewWindow

# Verify installation
$serviceName = "zabbix_agentd"
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    Write-Host "Zabbix Agent installed successfully."
    # Set service to start automatically
    Set-Service -Name $serviceName -StartupType Automatic
    Write-Host "Zabbix Agent service set to start automatically."
}
else {
    Write-Host "Error: Zabbix Agent installation failed or service not found."
    exit 1
}

# Clean up temporary files
Write-Host "Cleaning up temporary files..."
Remove-Item -Recurse -Force $tempDir

Write-Host "Installation completed successfully."
