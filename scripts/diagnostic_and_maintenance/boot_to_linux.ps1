<#
.SYNOPSIS
    Force One-Time UEFI Boot to USB Linux from Windows 11.
.DESCRIPTION
    Queries UEFI NVRAM firmware entries using bcdedit. Sets the bootsequence
    to the target USB / EFI device for a one-time reboot into Linux, or reboots
    into the UEFI Device Selection menu.
.EXAMPLE
    pwsh boot_to_linux.ps1
    pwsh boot_to_linux.ps1 -DirectMenu
#>

param(
    [switch]$DirectMenu,
    [switch]$ForceReboot
)

# Ensure Administrative Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Administrator privileges are required to modify UEFI NVRAM boot entries." -ForegroundColor Red
    Write-Host "Please run this script from an elevated PowerShell window (Run as Administrator)." -ForegroundColor Yellow
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "       Force One-Time UEFI Boot to USB Linux              " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if ($DirectMenu) {
    Write-Host "Rebooting into Windows Advanced UEFI Device Selection Menu..." -ForegroundColor Yellow
    & shutdown.exe /r /o /t 0
    exit 0
}

# Query UEFI Firmware Entries
Write-Host "Querying UEFI Firmware Boot Manager..." -ForegroundColor Gray
$rawBcd = bcdedit.exe /enum firmware 2>&1

$entries = @()
$currentId = ""
$currentDesc = ""

foreach ($line in $rawBcd) {
    $line = $line.Trim()
    if ($line -match "^identifier\s+(.+)$") {
        $currentId = $matches[1].Trim()
    }
    elseif ($line -match "^description\s+(.+)$") {
        $currentDesc = $matches[1].Trim()
        if ($currentId -and $currentId -ne "{fwbootmgr}" -and $currentId -ne "{bootmgr}") {
            $entries += [PSCustomObject]@{
                Index = $entries.Count + 1
                Identifier = $currentId
                Description = $currentDesc
            }
        }
        $currentId = ""
        $currentDesc = ""
    }
}

if ($entries.Count -eq 0) {
    Write-Host "[WARN] No secondary UEFI firmware applications found." -ForegroundColor Yellow
    Write-Host "Falling back to Windows Advanced Startup Menu..." -ForegroundColor Cyan
    & shutdown.exe /r /o /t 0
    exit 0
}

Write-Host "Available UEFI Firmware Boot Devices:" -ForegroundColor Green
$entries | Format-Table -AutoSize

Write-Host "Options:" -ForegroundColor Yellow
Write-Host "  [1-$($entries.Count)] Select a specific UEFI Boot Device from the list above"
Write-Host "  [M]   Reboot into Windows Advanced Startup / UEFI Device Menu (shutdown /r /o)"
Write-Host "  [Q]   Cancel and Quit"
Write-Host ""

$choice = Read-Host "Select option"

if ($choice -match "^[0-9]+$" -and [int]$choice -ge 1 -and [int]$choice -le $entries.Count) {
    $selected = $entries[[int]$choice - 1]
    Write-Host "Setting one-time boot sequence to: $($selected.Description) ($($selected.Identifier))..." -ForegroundColor Cyan
    
    $res = bcdedit.exe /set "{fwbootmgr}" bootsequence $selected.Identifier 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] One-time boot sequence successfully programmed!" -ForegroundColor Green
        Write-Host "System will boot into $($selected.Description) on the NEXT reboot only." -ForegroundColor Green
        
        $confirm = Read-Host "Reboot system now? (Y/N)"
        if ($confirm -match "^[Yy]$" -or $ForceReboot) {
            Write-Host "Rebooting system..." -ForegroundColor Yellow
            & shutdown.exe /r /t 0
        } else {
            Write-Host "Reboot postponed. The one-time boot sequence will take effect whenever you reboot." -ForegroundColor Cyan
        }
    } else {
        Write-Host "[ERROR] Failed to set bootsequence: $res" -ForegroundColor Red
    }
}
elseif ($choice -match "^[Mm]$") {
    Write-Host "Rebooting into Advanced Startup Menu..." -ForegroundColor Yellow
    & shutdown.exe /r /o /t 0
}
else {
    Write-Host "Operation cancelled." -ForegroundColor Gray
}
