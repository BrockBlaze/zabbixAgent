#Set Permissions
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Get the last 10 successful logins from the Security log
$logins = Get-WinEvent -LogName Security | Where-Object {
    $_.Id -eq 4624 -and $_.Properties[5].Value -ne "ANONYMOUS LOGON"
} | Select-Object -First 10

# Display user and login time
$logins | ForEach-Object {
    [PSCustomObject]@{
        User = $_.Properties[5].Value       # User who logged in
        Time = $_.TimeCreated              # Time of the event
    }
} | Format-Table -AutoSize