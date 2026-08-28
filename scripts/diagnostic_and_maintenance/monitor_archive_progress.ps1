<#
.SYNOPSIS
    Live Background Progress Monitor for Ubuntu 16 Archiving
.DESCRIPTION
    Monitors tar.exe execution, tracks the growth of D:\Ubuntu16_archive.tar.gz in real-time,
    and displays live NVMe temperature and estimated completion progress.
#>
[CmdletBinding()]
param(
    [string]$ArchiveFile = "D:\Ubuntu16_archive.tar.gz",
    [int]$EstimatedTotalMB = 3200
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  Live Ubuntu 16 Archiving & NVMe Thermal Monitor" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan

$initialTime = Get-Date

while ($true) {
    $tarProc = Get-Process -Name tar -ErrorAction SilentlyContinue | Select-Object -First 1
    $archItem = Get-Item -Path $ArchiveFile -ErrorAction SilentlyContinue
    
    # Read live NVMe temperature
    $temp = "N/A"
    try {
        $disk = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -or $_.FriendlyName -match 'Samsung' } | Select-Object -First 1
        if ($disk) {
            $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($rel -and $null -ne $rel.Temperature) {
                $temp = "$($rel.Temperature) C"
            }
        }
    } catch {}
    
    $nowStr = (Get-Date).ToString("HH:mm:ss")
    
    if ($archItem) {
        $sizeMB = [math]::Round($archItem.Length / 1MB, 2)
        $sizeGB = [math]::Round($archItem.Length / 1GB, 3)
        $pct = [math]::Min(99, [math]::Round(($sizeMB / $EstimatedTotalMB) * 100, 1))
        
        if ($tarProc) {
            $cpuSec = [math]::Round($tarProc.CPU, 1)
            $memMB = [math]::Round($tarProc.WorkingSet64 / 1MB, 1)
            Write-Host "[$nowStr] [RUNNING] Archive: $sizeMB MB ($sizeGB GB) | ~$pct% | tar PID $($tarProc.Id) (CPU: ${cpuSec}s, RAM: ${memMB}MB) | NVMe: $temp" -ForegroundColor DarkGreen
        } else {
            Write-Host "[$nowStr] [COMPLETED] tar.exe finished! Final Archive: $sizeMB MB ($sizeGB GB) | NVMe: $temp" -ForegroundColor DarkCyan
            break
        }
    } else {
        if ($tarProc) {
            Write-Host "[$nowStr] [STARTING] tar.exe running (PID $($tarProc.Id)) | Initializing archive... | NVMe: $temp" -ForegroundColor DarkYellow
        } else {
            Write-Host "[$nowStr] [IDLE] No active tar.exe process found. Waiting for job to start..." -ForegroundColor DarkGray
        }
    }
    
    Start-Sleep -Seconds 3
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Archiving completed successfully." -ForegroundColor DarkGreen
