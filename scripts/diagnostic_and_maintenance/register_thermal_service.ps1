<#
.SYNOPSIS
    Registers the NVMe Thermal Governor as an Unattended 24/7 Background System Task
    and adds the System Tray App to User Startup.
.DESCRIPTION
    1. Creates Windows Scheduled Task "NVMeThermalGovernor" running bin/NVMeThermalDaemon.exe
       at machine startup under NT AUTHORITY\SYSTEM with Highest privileges.
    2. Adds NVMeThermalTray to HKCU:\Software\Microsoft\Windows\CurrentVersion\Run for automatic
       taskbar icon and desktop notifications on user login.
#>

[CmdletBinding()]
param(
    [switch]$Unregister
)

$repo = "D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys"
$daemonExe = Join-Path $repo "bin\NVMeThermalDaemon.exe"
$trayExe = Join-Path $repo "bin\NVMeThermalTray.exe"
$taskName = "NVMeThermalGovernor"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

if ($Unregister) {
    Write-Host "=== Unregistering NVMe Thermal Auto-Start Services ===" -ForegroundColor DarkYellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $runKey -Name "NVMeThermalTray" -ErrorAction SilentlyContinue
    Write-Host "Auto-start services successfully unregistered." -ForegroundColor DarkGreen
    return
}

Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  Registering NVMe Thermal Governor 24/7 Auto-Start Task  " -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan

# 1. Register Scheduled Task (SYSTEM at boot)
if (Test-Path $daemonExe) {
    Write-Host "[1/2] Registering Background Daemon Scheduled Task ($taskName)..." -ForegroundColor DarkYellow
    $action = New-ScheduledTaskAction -Execute $daemonExe
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    
    $registered = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($registered) {
        Write-Host "  -> Scheduled Task '$taskName' successfully registered (State: $($registered.State))." -ForegroundColor DarkGreen
    } else {
        Write-Host "  -> Note: Scheduled task requires Administrator elevation to register." -ForegroundColor DarkRed
    }
} else {
    Write-Host "[ERROR] Daemon binary not found at $daemonExe" -ForegroundColor DarkRed
}

# 2. Register User Login Tray App
Write-Host "[2/2] Registering System Tray App in User Startup (HKCU Run)..." -ForegroundColor DarkYellow
if (Test-Path $trayExe) {
    Set-ItemProperty -Path $runKey -Name "NVMeThermalTray" -Value "`"$trayExe`"" -Force
    Write-Host "  -> HKCU Run entry 'NVMeThermalTray' configured successfully." -ForegroundColor DarkGreen
} else {
    Write-Host "  -> Note: Tray binary not found at $trayExe" -ForegroundColor DarkYellow
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Thermal Governor is now configured to protect the machine 24/7 unattended!" -ForegroundColor DarkGreen
