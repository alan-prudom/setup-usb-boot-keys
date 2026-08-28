Write-Output "=== Physical Disk Health Summary ==="
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size | Format-Table -AutoSize

Write-Output "=== SMART Reliability Counters ==="
Get-PhysicalDisk | ForEach-Object {
    $disk = $_
    Write-Output "--- Disk: $($disk.FriendlyName) ---"
    $rel = $disk | Get-StorageReliabilityCounter
    $rel | Select-Object * | Format-List
}

Write-Output "=== NVMe Error Log (Windows Storage ==="
Get-WinEvent -LogName "Microsoft-Windows-Storage-ATAPort/Operational" -MaxEvents 20 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, LevelDisplayName, Message -Wrap
Get-WinEvent -LogName "Microsoft-Windows-Storage-ClassPnP/Operational" -MaxEvents 10 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, LevelDisplayName, Message -Wrap

Write-Output "=== Disk I/O Error Events (Last 30 Min) ==="
$startTime = (Get-Date).AddMinutes(-30)
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk','nvme','atapi','storahci','stornvme'; StartTime=$startTime} -ErrorAction SilentlyContinue | Format-Table TimeCreated, ProviderName, Id, LevelDisplayName, Message -Wrap
