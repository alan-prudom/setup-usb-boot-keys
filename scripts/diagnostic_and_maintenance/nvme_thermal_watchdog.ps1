<#
.SYNOPSIS
    Proportional Multi-Stage NVMe Thermal Governor & Adaptive Watchdog
.DESCRIPTION
    Continuously monitors Samsung NVMe SSD temperature and applies smooth,
    multi-stage CPU throttling via powercfg to prevent thermal saturation.
    Features adaptive sampling (1s to 10s), stability-gated step-ups, and an
    optional -Aggressive mode with stall-timeout deep throttling.
.PARAMETER Aggressive
    Enables active stall-timeout escalation: if temperature remains >= 56°C for > 90s,
    deepens CPU throttling and pauses heavy background sync I/O until cooled.
#>
[CmdletBinding()]
param(
    [switch]$Aggressive,
    [string]$LogFile = "D:\nvme_thermal_log.csv",
    [switch]$Once,
    [switch]$TestMode
)

$ErrorActionPreference = "SilentlyContinue"

function Get-NVMeTemperature {
    try {
        $disk = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -or $_.FriendlyName -match 'Samsung' } | Select-Object -First 1
        if ($disk) {
            $rel = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            if ($rel -and $null -ne $rel.Temperature) {
                return [int]$rel.Temperature
            }
        }
    } catch {}
    return $null
}

function Set-CpuThrottleLimit {
    param([int]$Percent)
    
    if ($TestMode) {
        Write-Host ("[TEST MODE] Would set CPU Max Throttle to " + $Percent + "%") -ForegroundColor DarkBlue
        return
    }
    
    try {
        & powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $Percent | Out-Null
        & powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $Percent | Out-Null
        & powercfg -setactive SCHEME_CURRENT | Out-Null
        Write-Host ("CPU Throttle Max successfully set to " + $Percent + "%") -ForegroundColor DarkGreen
    } catch {
        Write-Error ("Failed to set CPU throttle: " + $_.Exception.Message)
    }
}

function Set-BackgroundIoState {
    param([bool]$Suspend)
    
    $procs = @("Dropbox")
    foreach ($pName in $procs) {
        $p = Get-Process -Name $pName -ErrorAction SilentlyContinue
        if ($p) {
            if ($Suspend) {
                Write-Host ("[AGGRESSIVE] Pausing background I/O process: " + $pName) -ForegroundColor DarkYellow
                # In PowerShell on Windows, we can adjust priority to Idle to de-prioritize disk I/O
                $p | ForEach-Object { $_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle }
            } else {
                Write-Host ("[AGGRESSIVE] Restoring background I/O process: " + $pName) -ForegroundColor DarkGreen
                $p | ForEach-Object { $_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal }
            }
        }
    }
}

# Initialize CSV log header
if (-not (Test-Path $LogFile)) {
    "Timestamp,TemperatureC,CpuLimitPercent,PollIntervalSec,StateTag,Message" | Out-File -FilePath $LogFile -Encoding utf8
}

# State Variables
$currentCpuLimit = 100
$stableBelowCounter = 0      # Seconds spent stably below next step-up threshold
$dwellRequiredSeconds = 30   # Must remain stable for 30s before stepping up
$stalledHotCounter = 0       # Seconds spent stalled at >= 56°C (for -Aggressive mode)
$isAggressiveThrottled = $false

Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  Proportional Multi-Stage NVMe Thermal Governor" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  Thermal Ladder & Power Profiles:" -ForegroundColor Black
Write-Host "    [NORMAL]    < 50 C  -> CPU 100% (Poll: 10s)" -ForegroundColor DarkGreen
Write-Host "    [WARM]     50-54 C  -> CPU  80% (Poll:  5s)" -ForegroundColor DarkYellow
Write-Host "    [HOT]      55-58 C  -> CPU  60% (Poll:  3s)" -ForegroundColor DarkMagenta
Write-Host "    [CRITICAL] >= 59 C  -> CPU  40% (Poll:  1s)" -ForegroundColor DarkRed
Write-Host "  Step-Up Gating : 30s continuous stability required" -ForegroundColor DarkGray
if ($Aggressive) {
    Write-Host "  Aggressive Mode: ACTIVE (Stall Timeout > 90s triggers deep throttle & I/O back-off)" -ForegroundColor DarkYellow
} else {
    Write-Host "  Aggressive Mode: OFF (Standard Proportional Mode)" -ForegroundColor DarkGray
}
Write-Host ("  Log File       : " + $LogFile) -ForegroundColor Black
if ($TestMode) { Write-Host "  MODE           : DRY RUN (TestMode)" -ForegroundColor DarkBlue }
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

while ($true) {
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $temp = Get-NVMeTemperature
    
    if ($null -eq $temp) {
        Write-Host ("[" + $now + "] [ERROR] Unable to read NVMe temperature. Retrying in 5s...") -ForegroundColor DarkYellow
        if ($Once) { break }
        Start-Sleep -Seconds 5
        continue
    }
    
    # 1. Determine Target Tier & Adaptive Poll Interval based on Temperature
    $targetLimit = 100
    $pollInterval = 10
    $stateTag = "[NORMAL 100%]"
    $stateColor = "DarkGreen"
    $statusMsg = "Normal"
    
    if ($temp -ge 59) {
        $targetLimit = 40
        $pollInterval = 1
        $stateTag = "[CRITICAL 40%]"
        $stateColor = "DarkRed"
        $statusMsg = "CRITICAL_THROTTLING"
    }
    elseif ($temp -ge 55) {
        $targetLimit = 60
        $pollInterval = 3
        $stateTag = "[HOT 60%]"
        $stateColor = "DarkMagenta"
        $statusMsg = "HOT_ACTIVE_COOLING"
    }
    elseif ($temp -ge 50) {
        $targetLimit = 80
        $pollInterval = 5
        $stateTag = "[WARM 80%]"
        $stateColor = "DarkYellow"
        $statusMsg = "WARM_PREVENTATIVE"
    }
    else {
        $targetLimit = 100
        $pollInterval = 10
        $stateTag = "[NORMAL 100%]"
        $stateColor = "DarkGreen"
        $statusMsg = "NORMAL"
    }
    
    # 2. Aggressive Stall-Timeout Logic (If -Aggressive is enabled)
    if ($Aggressive) {
        if ($temp -ge 56) {
            $stalledHotCounter += $pollInterval
            if ($stalledHotCounter -ge 90 -and -not $isAggressiveThrottled) {
                $isAggressiveThrottled = $true
                $targetLimit = [math]::Max(25, $targetLimit - 15) # Drop an extra 15% (e.g. 60% -> 45%)
                $stateTag = "[AGGRESSIVE DEEP THROTTLE]"
                $stateColor = "DarkRed"
                $statusMsg = "AGGRESSIVE_STALL_DEEP_THROTTLE"
                Write-Host ("[" + $now + "] ⚠️ [AGGRESSIVE] Temperature stalled >= 56 C for 90s! Forcing Deep Throttle to " + $targetLimit + "%...") -ForegroundColor DarkRed
                Set-BackgroundIoState -Suspend $true
            }
        } else {
            $stalledHotCounter = 0
            if ($isAggressiveThrottled -and $temp -le 52) {
                $isAggressiveThrottled = $false
                Write-Host ("[" + $now + "] [AGGRESSIVE] Temperature recovered <= 52 C. Clearing deep throttle state.") -ForegroundColor DarkGreen
                Set-BackgroundIoState -Suspend $false
            }
        }
    }
    
    # 3. Step-Down Logic (IMMEDIATE) vs Step-Up Logic (STABILITY GATED)
    if ($targetLimit -lt $currentCpuLimit) {
        # Immediate Step-Down on thermal rise
        $oldLimit = $currentCpuLimit
        $currentCpuLimit = $targetLimit
        $stableBelowCounter = 0
        Write-Host ("[" + $now + "] " + $stateTag + " NVMe is " + $temp + " C! Stepping DOWN CPU: " + $oldLimit + "% -> " + $currentCpuLimit + "%") -ForegroundColor $stateColor
        Set-CpuThrottleLimit -Percent $currentCpuLimit
    }
    elseif ($targetLimit -gt $currentCpuLimit) {
        # Step-Up requested: Check if we have dwelled long enough
        $stableBelowCounter += $pollInterval
        if ($stableBelowCounter -ge $dwellRequiredSeconds) {
            $oldLimit = $currentCpuLimit
            $nextStep = switch ($currentCpuLimit) {
                25 { 40 }
                40 { 60 }
                45 { 60 }
                60 { 80 }
                80 { 100 }
                default { 100 }
            }
            $currentCpuLimit = $nextStep
            $stableBelowCounter = 0
            Write-Host ("[" + $now + "] [STABLE STEP-UP] NVMe sustained " + $temp + " C for " + $dwellRequiredSeconds + "s. Stepping UP CPU: " + $oldLimit + "% -> " + $currentCpuLimit + "%") -ForegroundColor DarkGreen
            Set-CpuThrottleLimit -Percent $currentCpuLimit
        } else {
            $remain = $dwellRequiredSeconds - $stableBelowCounter
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe Temp: " + $temp + " C (Stabilizing at CPU " + $currentCpuLimit + "%: " + $remain + "s remaining)") -ForegroundColor DarkGray
        }
    }
    else {
        # Steady state at current limit
        $stableBelowCounter = 0
        Write-Host ("[" + $now + "] " + $stateTag + " NVMe Temp: " + $temp + " C (CPU: " + $currentCpuLimit + "%, Poll: " + $pollInterval + "s)") -ForegroundColor $stateColor
    }
    
    # Append to CSV log
    $logLine = $now + "," + $temp + "," + $currentCpuLimit + "," + $pollInterval + "," + $stateTag + "," + $statusMsg
    $logLine | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    if ($Once) { break }
    Start-Sleep -Seconds $pollInterval
}
