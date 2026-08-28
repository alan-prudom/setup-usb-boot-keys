[CmdletBinding()]
param(
    [int]$IntervalSeconds = 20,
    [int]$WarningTemp = 65,
    [int]$CriticalTemp = 70,
    [int]$RecoveryTemp = 60,
    [string]$LogFile = "D:\nvme_thermal_log.csv",
    [switch]$Once,
    [switch]$TestMode
)

function Get-NVMeTemperature {
    try {
        $disk = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -or $_.FriendlyName -match 'Samsung' } | Select-Object -First 1
        if ($disk) {
            $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($rel -and $null -ne $rel.Temperature) {
                return [int]$rel.Temperature
            }
        }
    } catch {
        Write-Warning ("Failed to read NVMe temperature: " + $_.Exception.Message)
    }
    return $null
}

function Set-CpuThrottleLimit {
    param([int]$Percent)
    
    if ($TestMode) {
        Write-Host ("[TEST MODE] Would set CPU Max Throttle to " + $Percent + "%") -ForegroundColor DarkBlue
        return
    }
    
    try {
        & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $Percent
        & powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $Percent
        & powercfg -setactive SCHEME_CURRENT
        Write-Host ("CPU Throttle Max successfully set to " + $Percent + "%") -ForegroundColor DarkGreen
    } catch {
        Write-Error ("Failed to set CPU throttle via powercfg: " + $_.Exception.Message)
    }
}

# Initialize CSV log header
if (-not (Test-Path $LogFile)) {
    "Timestamp,TemperatureC,ThrottledState,CpuLimitPercent,Message" | Out-File -FilePath $LogFile -Encoding utf8
}

$isThrottled = $false

# High-contrast banner for light theme
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  NVMe Thermal Monitoring & CPU Back-off Watchdog" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ("  Sampling Interval : " + $IntervalSeconds + " seconds") -ForegroundColor Black
Write-Host ("  Warning Threshold : " + $WarningTemp + " C") -ForegroundColor Black
Write-Host ("  Critical (Throttle): " + $CriticalTemp + " C -> CPU 50%") -ForegroundColor DarkRed
Write-Host ("  Recovery (Restore): " + $RecoveryTemp + " C -> CPU 100%") -ForegroundColor DarkGreen
Write-Host ("  Log File          : " + $LogFile) -ForegroundColor Black
if ($TestMode) { Write-Host "  MODE              : DRY RUN (TestMode)" -ForegroundColor DarkMagenta }
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

while ($true) {
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $temp = Get-NVMeTemperature
    
    if ($null -eq $temp) {
        Write-Host ("[" + $now + "] [ERROR] Unable to read temperature. Retrying in " + $IntervalSeconds + "s...") -ForegroundColor DarkYellow
        if ($Once) { break }
        Start-Sleep -Seconds $IntervalSeconds
        continue
    }
    
    $statusMsg = "Normal"
    $cpuLimit = 100
    
    if ($temp -ge $CriticalTemp -and -not $isThrottled) {
        $isThrottled = $true
        $statusMsg = "CRITICAL_THROTTLING_ACTIVATED"
        $cpuLimit = 50
        Write-Host ("[" + $now + "] [CRITICAL] NVMe is " + $temp + " C (>= " + $CriticalTemp + " C)! Capping CPU to 50%...") -ForegroundColor DarkRed
        Set-CpuThrottleLimit -Percent 50
    }
    elseif ($isThrottled -and $temp -le $RecoveryTemp) {
        $isThrottled = $false
        $statusMsg = "RECOVERY_RESTORED_100%"
        $cpuLimit = 100
        Write-Host ("[" + $now + "] [COOLDOWN] NVMe cooled to " + $temp + " C (<= " + $RecoveryTemp + " C). Restoring CPU to 100%.") -ForegroundColor DarkGreen
        Set-CpuThrottleLimit -Percent 100
    }
    elseif ($temp -ge $WarningTemp -and -not $isThrottled) {
        $statusMsg = "WARNING_HIGH_TEMP"
        Write-Host ("[" + $now + "] [WARNING] NVMe is " + $temp + " C (elevated temperature).") -ForegroundColor DarkYellow
    }
    else {
        if ($isThrottled) {
            $stateTag = "[THROTTLED 50%]"
            $color = "DarkMagenta"
        } else {
            $stateTag = "[NORMAL 100%]"
            $color = "DarkGreen"
        }
        Write-Host ("[" + $now + "] [OK] NVMe Temp: " + $temp + " C " + $stateTag) -ForegroundColor $color
    }
    
    $logLine = $now + "," + $temp + "," + $isThrottled + "," + $cpuLimit + "," + $statusMsg
    $logLine | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSeconds
}
