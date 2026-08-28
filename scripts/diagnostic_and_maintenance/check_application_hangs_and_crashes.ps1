$ev = Get-WinEvent -FilterHashtable @{LogName='System'; ID=41} -MaxEvents 1
[xml]$xml = $ev.ToXml()
$bc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' }).'#text'
$p1 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter1' }).'#text'
$p2 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter2' }).'#text'
$p3 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter3' }).'#text'
$p4 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter4' }).'#text'
Write-Output "=== Latest Crash (Event 41) ==="
Write-Output ("Crash Time: {0}" -f $ev.TimeCreated)
Write-Output ("BugcheckCode: {0} (0x{1:X})" -f $bc, [int]$bc)
Write-Output ("P1: {0} | P2: {1} | P3: {2} | P4: {3}" -f $p1, $p2, $p3, $p4)

Write-Output ""
Write-Output "=== All System Errors in Last 30 Minutes ==="
$startTime = (Get-Date).AddMinutes(-30)
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$startTime} -ErrorAction SilentlyContinue | Format-Table TimeCreated, ProviderName, Id, Message -Wrap

Write-Output "=== Application Errors in Last 30 Minutes ==="
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$startTime} -ErrorAction SilentlyContinue | Select-Object -First 10 | Format-Table TimeCreated, ProviderName, Id, Message -Wrap

Write-Output "=== Recent Minidumps ==="
Get-ChildItem -Path C:\Windows\Minidump -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | Format-Table Name, Length, LastWriteTime

Write-Output "=== Current Disk Status ==="
Get-PSDrive C, D, G | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB, 2)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB, 2)}} | Format-Table -AutoSize
