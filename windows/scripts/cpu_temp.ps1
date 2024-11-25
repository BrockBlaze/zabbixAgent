Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Path to Open Hardware Monitor executable
$ohmPath = "C:\Tools\OpenHardwareMonitor"

# Start OHM if not already running
if (-not (Get-Process | Where-Object { $_.ProcessName -eq "OpenHardwareMonitor" })) {
    Start-Process -FilePath "$ohmPath\OpenHardwareMonitor.exe" -NoNewWindow
    Start-Sleep -Seconds 5 # Give OHM time to start
}

$response = Invoke-WebRequest -Uri "http://localhost:8085/data.json" -UseBasicParsing
$data = $response.Content | ConvertFrom-Json

$desktop = $data.Children
$cpuNode = $desktop.Children | Where-Object { $_.id -eq 3 }
$temperatureNode = $cpuNode.Children | Where-Object { $_.id -eq 14 }
$cpuTempValue = $temperatureNode.Children.Value -replace "[^0-9\.]", ""

Write-Output "$cpuTempValue"