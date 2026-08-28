Write-Output "=== AvastCleanupSvc Service Status ==="
Get-Service -Name "AvastCleanupSvc" | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize

Write-Output "=== TuneUp / Avast Cleanup Processes Still Running? ==="
$procs = Get-Process | Where-Object { $_.Name -match 'tuneup|cleanup' }
if ($procs) {
    $procs | Format-Table Id, Name, @{N='MemMB';E={[math]::Round($_.WS/1MB,1)}} -AutoSize
} else {
    Write-Output "No TuneUp/Cleanup processes running. Clean!"
}

Write-Output "=== Top 10 Processes by Memory ==="
Get-Process | Sort-Object WS -Descending | Select-Object -First 10 | Format-Table Id, Name, @{N='MemMB';E={[math]::Round($_.WS/1MB,1)}} -AutoSize

Write-Output "=== NVMe SRB Errors Since Last Reboot ==="
$boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
Get-WinEvent -LogName "Microsoft-Windows-Storage-ATAPort/Operational" -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 507 -and $_.TimeCreated -gt $boot } |
    Select-Object -First 5 | Format-Table TimeCreated, Id, Message -Wrap

Write-Output "=== Disk Free Space ==="
Get-PSDrive C, D, G | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}} | Format-Table -AutoSize
