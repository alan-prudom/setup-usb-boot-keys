$startTime = (Get-Date).AddMinutes(-15)

Write-Output "=== Volsnap & VSS Events (Last 15 Mins) ==="
$events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Volsnap','VSS'; StartTime=$startTime} -ErrorAction SilentlyContinue

if ($events) {
    $events | Format-Table TimeCreated, ProviderName, Id, LevelDisplayName, Message -Wrap
} else {
    Write-Output "No Volsnap errors or abort events recorded in the last 15 minutes! System is clean."
}

Write-Output "=== Drive Free Space Status ==="
Get-PSDrive C, D, G | Select-Object Name, @{N='UsedGB';E={[math]::Round($_.Used/1GB, 2)}}, @{N='FreeGB';E={[math]::Round($_.Free/1GB, 2)}} | Format-Table -AutoSize
