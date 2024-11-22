# Check if Git is installed
$gitPath = Get-Command git -ErrorAction SilentlyContinue

if (-not $gitPath) {
    Write-Host "Git is not installed. Installing Git..."

    # Download Git installer
    $gitInstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/Git-2.47.0.2-64-bit.exe"
    $installerPath = "$env:TEMP\Git-installer.exe"
    
    # Download the installer
    Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $installerPath

    # Run the installer
    Start-Process -FilePath $installerPath -ArgumentList "/silent" -Wait

    # Verify installation
    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitPath) {
        Write-Host "Git installed successfully."
    }
    else {
        Write-Host "Git installation failed. Please install Git manually."
        exit
    }
}
else {
    Write-Host "Git is already installed."
}

# Variables
$repoUrl = "https://github.com/BrockBlaze/zabbixAgent"
$downloadDir = "C:\Temp\zabbixAgent"
$scriptsDir = "C:\Program Files\Zabbix Agent\scripts"
$configFile = "C:\Program Files\Zabbix Agent\zabbix_agentd.conf"

# Ensure the download directory exists
Write-Host "Testing directory $downloadDir"
if (-not (Test-Path $downloadDir)) {
    Write-Host "Creating directory $downloadDir"
    New-Item -ItemType Directory -Force -Path $downloadDir
}

# Prompt for Zabbix server IP and hostname
$zabbixServerIP = Read-Host "Enter the Zabbix Server IP"
$hostname = Read-Host "Enter the Hostname (this server's name)"

# Step 1: Download and install Zabbix Agent
Write-Host "Downloading Zabbix Agent installer..."
Invoke-WebRequest -Uri "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.6/zabbix_agent-7.0.6-windows-amd64-openssl.msi" -OutFile "$downloadDir\zabbix_agent.msi"

Write-Host "Installing Zabbix Agent..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $downloadDir\zabbix_agent.msi /quiet" -Wait

# Step 2: Clone repository
Write-Host "Cloning repository..."
git clone $repoUrl $downloadDir

# Step 3: Copy custom scripts
Write-Host "Copying scripts..."
New-Item -ItemType Directory -Path $scriptsDir -Force
Copy-Item -Path "$downloadDir\windows\scripts\*" -Destination $scriptsDir -Recurse -Force

# Step 4: Update configuration file
Write-Host "Updating configuration file..."
Copy-Item -Path "$downloadDir\windows\zabbix_agentd.conf" -Destination $configFile -Force

# Replace placeholders in the configuration file
(Get-Content $configFile) -replace 'Server=.*', "Server=$zabbixServerIP" `
    -replace 'Hostname=.*', "Hostname=$hostname" `
| Set-Content $configFile

# Step 5: Restart and enable service
Write-Host "Restarting Zabbix Agent service..."
Restart-Service -Name "Zabbix Agent"
Set-Service -Name "Zabbix Agent" -StartupType Automatic

# Cleanup
Write-Host "Cleaning up temporary files..."
Remove-Item -Recurse -Force $downloadDir

Write-Host "Zabbix Agent installed and configured successfully!"
