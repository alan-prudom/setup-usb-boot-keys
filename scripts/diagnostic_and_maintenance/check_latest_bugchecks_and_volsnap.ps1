"=== Latest Kernel-Power (Event 41) Events ==="
$evs = Get-WinEvent -FilterHashtable @{LogName='System'; ID=41} -MaxEvents 5
foreach ($e in $evs) {
    [xml]$xml = $e.ToXml()
    $bc = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' }).'#text'
    $p1 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter1' }).'#text'
    $p2 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter2' }).'#text'
    $p3 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter3' }).'#text'
    $p4 = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckParameter4' }).'#text'
    $pb = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'PowerButtonTimestamp' }).'#text'
    Write-Output ("Time: {0} | Bugcheck: {1} | P1: {2} | P2: {3} | P3: {4} | P4: {5} | PwrBtn: {6}" -f $e.TimeCreated, $bc, $p1, $p2, $p3, $p4, $pb)
}

"=== System Errors in the last 15 minutes ==="
$startTime = (Get-Date).AddMinutes(-15)
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$startTime} -ErrorAction SilentlyContinue | Format-Table TimeCreated, ProviderName, Id, Message -Wrap
