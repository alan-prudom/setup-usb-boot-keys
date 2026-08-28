# Check Event 41 details
$events41 = Get-WinEvent -FilterHashtable @{LogName='System'; ID=41} -MaxEvents 20
"=== Kernel-Power (Event 41) Events ==="
foreach ($e in $events41) {
    [xml]$xml = $e.ToXml()
    $bc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' }).'#text'
    $p1 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter1' }).'#text'
    $pb = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'PowerButtonTimestamp' }).'#text'
    Write-Output ("Time: {0} | Bugcheck: {1} | Param1: {2} | PowerBtn: {3}" -f $e.TimeCreated, $bc, $p1, $pb)
}

"=== Windows Updates / Hotfixes ==="
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 | Format-Table HotFixID, Description, InstalledOn -AutoSize

"=== Crash Dumps in C:\Windows\Minidump or C:\Windows\MEMORY.DMP ==="
Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | Format-Table Name, Length, LastWriteTime -AutoSize
Get-Item C:\Windows\MEMORY.DMP -ErrorAction SilentlyContinue | Format-Table Name, Length, LastWriteTime -AutoSize

"=== Reliability / WER / System Events near 31 July - 05 August 2026 ==="
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date '2026-07-30'); EndTime=(Get-Date '2026-08-06')} -MaxEvents 30 -ErrorAction SilentlyContinue | Select-Object TimeCreated, ProviderName, Id, Message | Format-List
