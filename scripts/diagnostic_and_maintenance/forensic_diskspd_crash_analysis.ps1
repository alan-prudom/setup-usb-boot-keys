Write-Output "=== Last 25 Recorded Thermal Log Entries ==="
if (Test-Path "D:\nvme_thermal_log.csv") {
    Get-Content "D:\nvme_thermal_log.csv" | Select-Object -Last 25
} else {
    Write-Output "No D:\nvme_thermal_log.csv found."
}

Write-Output ""
Write-Output "=== Latest Crash (Event ID 41) ==="
$ev = Get-WinEvent -FilterHashtable @{LogName='System'; ID=41} -MaxEvents 1
[xml]$xml = $ev.ToXml()
$bc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' }).'#text'
$p1 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter1' }).'#text'
$p2 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter2' }).'#text'
$p3 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter3' }).'#text'
$p4 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter4' }).'#text'
Write-Output ("Crash Time   : " + $ev.TimeCreated)
Write-Output ("BugcheckCode : " + $bc + " (0x" + [Convert]::ToString([int64]$bc, 16) + ")")
Write-Output ("Param 1 (P1) : " + $p1)
Write-Output ("Param 2 (P2) : " + $p2)

Write-Output ""
Write-Output "=== Current Post-Reboot NVMe State ==="
$disk = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -or $_.FriendlyName -match 'Samsung' } | Select-Object -First 1
if ($disk) {
    $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($rel) {
        Write-Output ("Current Temp : " + $rel.Temperature + " C")
        Write-Output ("Max Temp Ever: " + $rel.TemperatureMax + " C")
        Write-Output ("ReadLatency  : " + $rel.ReadLatencyMax + " ms")
    }
}
