# Use Event Logs to track login attempts
$logins = Get-EventLog -LogName Security -InstanceId 4624 -Newest 5 | Select-Object TimeGenerated, Message
$logins | ForEach-Object { $_.TimeGenerated.ToString() + " " + $_.Message }