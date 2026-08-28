$cs = Get-CimInstance Win32_ComputerSystem
$cs.AutomaticManagedPagefile = $true
Set-CimInstance -CimInstance $cs

Write-Output "=== Verified Pagefile Configuration ==="
Get-CimInstance Win32_ComputerSystem | Select-Object Name, AutomaticManagedPagefile | Format-List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' | Select-Object PagingFiles, ExistingPageFiles | Format-List
