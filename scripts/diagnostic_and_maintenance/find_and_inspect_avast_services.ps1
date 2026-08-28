Write-Output "=== Finding TuneUp Service Name ==="
$proc = Get-Process -Name "TuneupSvc" -ErrorAction SilentlyContinue
if ($proc) {
    $svc = Get-WmiObject Win32_Service | Where-Object { $_.ProcessId -eq $proc[0].Id }
    Write-Output "Service Name: $($svc.Name)"
    Write-Output "Display Name: $($svc.DisplayName)"
    Write-Output "Start Mode:   $($svc.StartMode)"
    Write-Output "State:        $($svc.State)"
} else {
    Write-Output "TuneupSvc process not found."
}

Write-Output ""
Write-Output "=== All Avast / TuneUp Services ==="
Get-WmiObject Win32_Service | Where-Object { $_.PathName -match 'avast|tuneup|avg' -or $_.Name -match 'avast|tuneup|avg' } | Select-Object Name, DisplayName, StartMode, State, ProcessId | Format-Table -AutoSize
