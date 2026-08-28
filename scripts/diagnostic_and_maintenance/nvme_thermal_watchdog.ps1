<#
.SYNOPSIS
    5% Adaptive Micro-Probe NVMe Proportional Thermal Governor with -MaxCpu Override
.DESCRIPTION
    Continuously monitors Samsung NVMe SSD temperature and applies smooth,
    5% micro-probe stepping via powercfg with a configurable maximum ceiling (default 75%).
    Features 0s rollback on thermal rise, stability-gated +5% probing,
    and a 60s probe penalty timer to prevent hunting oscillations.
.PARAMETER MaxCpu
    Configures the absolute maximum CPU throttle percentage allowed (default 75, range 40-100).
.PARAMETER Aggressive
    Enables active stall-timeout escalation: if temperature remains >= 56°C for > 90s,
    deepens CPU throttling and de-prioritizes background sync I/O.
#>
[CmdletBinding()]
param(
    [ValidateRange(40, 100)]
    [int]$MaxCpu = 75,
    [switch]$Aggressive,
    [string]$LogFile = "D:\nvme_thermal_log.csv",
    [switch]$Once,
    [switch]$TestMode
)

$ErrorActionPreference = "SilentlyContinue"

# ABSOLUTE HARD SAFETY CEILING (Default 75%, or user override via -MaxCpu)
$globalMaxCeiling = $MaxCpu

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
    
    # Strictly enforce global ceiling
    if ($Percent -gt $globalMaxCeiling) {
        $Percent = $globalMaxCeiling
    }
    
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
                Write-Host ("[AGGRESSIVE] De-prioritizing background I/O process: " + $pName) -ForegroundColor DarkYellow
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
$currentCpuLimit = [math]::Min(70, $globalMaxCeiling) # Safe startup baseline
$stableBelowCounter = 0      # Seconds spent stably below next step-up threshold
$dwellRequiredSeconds = 30   # Must remain stable for 30s before probing +5%
$probePenaltyCounter = 0     # Cooldown timer after a rejected probe
$stalledHotCounter = 0       # Seconds spent stalled at >= 56°C (for -Aggressive mode)
$isAggressiveThrottled = $false

Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ("  5% Adaptive Micro-Probe NVMe Governor (" + $globalMaxCeiling + "% Max Ceiling)") -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ("  Max CPU Ceiling: " + $globalMaxCeiling + "% " + $(if ($MaxCpu -eq 75) { "(Default Safe Cap)" } else { "(User Override Specified)" })) -ForegroundColor DarkGreen
Write-Host "  Proportional Micro-Stepping (5% Increments):" -ForegroundColor Black
Write-Host ("    [OPTIMAL]   <= 50 C  -> Probing up to " + $globalMaxCeiling + "%  (Poll: 5s)") -ForegroundColor DarkGreen
Write-Host "    [SUSTAINED] 51-54 C  -> Target  65% - 70%  (Poll: 4s)" -ForegroundColor DarkYellow
Write-Host "    [ACTIVE]    55-56 C  -> Step Down to  60%  (Poll: 3s)" -ForegroundColor DarkMagenta
Write-Host "    [DEEP]      57-58 C  -> Step Down to  50%  (Poll: 2s)" -ForegroundColor DarkMagenta
Write-Host "    [CRITICAL]  >= 59 C  -> Floor Limit   40%  (Poll: 1s)" -ForegroundColor DarkRed
Write-Host "  Probe Gating   : 30s stable dwell + 60s rollback penalty memory" -ForegroundColor DarkGray
if ($Aggressive) {
    Write-Host "  Aggressive Mode: ACTIVE (Stall Timeout > 90s triggers deep throttle & I/O back-off)" -ForegroundColor DarkYellow
} else {
    Write-Host "  Aggressive Mode: OFF (Standard 5% Adaptive Mode)" -ForegroundColor DarkGray
}
Write-Host ("  Log File       : " + $LogFile) -ForegroundColor Black
if ($TestMode) { Write-Host "  MODE           : DRY RUN (TestMode)" -ForegroundColor DarkBlue }
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

# Set initial safe baseline
Set-CpuThrottleLimit -Percent $currentCpuLimit

while ($true) {
    $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $temp = Get-NVMeTemperature
    
    if ($null -eq $temp) {
        Write-Host ("[" + $now + "] [ERROR] Unable to read NVMe temperature. Retrying in 4s...") -ForegroundColor DarkYellow
        if ($Once) { break }
        Start-Sleep -Seconds 4
        continue
    }
    
    # Decrement probe penalty counter if active
    if ($probePenaltyCounter -gt 0) {
        $probePenaltyCounter = [math]::Max(0, $probePenaltyCounter - 4)
    }
    
    # 1. Determine Ceiling & Polling Rate from Live Temperature
    $pollInterval = 4
    $stateTag = "[SUSTAINED " + $currentCpuLimit + "%]"
    $stateColor = "DarkYellow"
    $statusMsg = "Sustained"
    
    if ($temp -ge 59) {
        $pollInterval = 1
        $stateTag = "[CRITICAL 40%]"
        $stateColor = "DarkRed"
        $statusMsg = "CRITICAL_FLOOR"
        if ($currentCpuLimit -gt 40) {
            $oldLimit = $currentCpuLimit
            $currentCpuLimit = 40
            $probePenaltyCounter = 90
            $stableBelowCounter = 0
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe is " + $temp + " C (>= 59 C)! EMERGENCY FLOOR: " + $oldLimit + "% -> 40%") -ForegroundColor DarkRed
            Set-CpuThrottleLimit -Percent 40
        }
    }
    elseif ($temp -ge 57) {
        $pollInterval = 2
        $stateTag = "[DEEP 50%]"
        $stateColor = "DarkMagenta"
        $statusMsg = "DEEP_COOLING"
        if ($currentCpuLimit -gt 50) {
            $oldLimit = $currentCpuLimit
            $currentCpuLimit = 50
            $probePenaltyCounter = 60
            $stableBelowCounter = 0
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe is " + $temp + " C! Rolling back CPU: " + $oldLimit + "% -> 50%") -ForegroundColor DarkMagenta
            Set-CpuThrottleLimit -Percent 50
        }
    }
    elseif ($temp -ge 55) {
        $pollInterval = 3
        $stateTag = "[ACTIVE 60%]"
        $stateColor = "DarkMagenta"
        $statusMsg = "ACTIVE_COOLING"
        if ($currentCpuLimit -gt 60) {
            $oldLimit = $currentCpuLimit
            $currentCpuLimit = 60
            $probePenaltyCounter = 60
            $stableBelowCounter = 0
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe reached " + $temp + " C! Instant Rollback: " + $oldLimit + "% -> 60% (60s probe penalty active)") -ForegroundColor DarkMagenta
            Set-CpuThrottleLimit -Percent 60
        }
    }
    else {
        # Temperature is <= 54 C (Safe Probing Zone)
        if ($temp -le 50) {
            $pollInterval = 5
            $stateTag = "[OPTIMAL " + $currentCpuLimit + "%]"
            $stateColor = "DarkGreen"
            $maxProbeCeiling = $globalMaxCeiling
        }
        else {
            # 51 - 54 C
            $pollInterval = 4
            $stateTag = "[SUSTAINED " + $currentCpuLimit + "%]"
            $stateColor = "DarkYellow"
            $maxProbeCeiling = [math]::Min($globalMaxCeiling, 70)
        }
        
        # Check if we are above the target ceiling (e.g. at startup from 100%)
        if ($currentCpuLimit -gt $maxProbeCeiling) {
            $oldLimit = $currentCpuLimit
            $currentCpuLimit = $maxProbeCeiling
            Write-Host ("[" + $now + "] " + $stateTag + " Clamping CPU to safe ceiling: " + $oldLimit + "% -> " + $currentCpuLimit + "%") -ForegroundColor DarkYellow
            Set-CpuThrottleLimit -Percent $currentCpuLimit
        }
        # Check if we can probe +5% higher
        elseif ($currentCpuLimit -lt $maxProbeCeiling -and $probePenaltyCounter -eq 0) {
            $stableBelowCounter += $pollInterval
            if ($stableBelowCounter -ge $dwellRequiredSeconds) {
                # Probe +5% Step
                $oldLimit = $currentCpuLimit
                $currentCpuLimit = [math]::Min($globalMaxCeiling, $currentCpuLimit + 5)
                $stableBelowCounter = 0
                Write-Host ("[" + $now + "] [ADAPTIVE PROBE +5%] NVMe stable at " + $temp + " C for " + $dwellRequiredSeconds + "s. Probing CPU UP: " + $oldLimit + "% -> " + $currentCpuLimit + "%") -ForegroundColor DarkGreen
                Set-CpuThrottleLimit -Percent $currentCpuLimit
            } else {
                $remain = $dwellRequiredSeconds - $stableBelowCounter
                Write-Host ("[" + $now + "] " + $stateTag + " NVMe Temp: " + $temp + " C (Stable: " + $remain + "s remaining to probe +" + 5 + "% to " + ($currentCpuLimit + 5) + "%)") -ForegroundColor DarkGray
            }
        }
        elseif ($probePenaltyCounter -gt 0) {
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe Temp: " + $temp + " C (Locked at CPU " + $currentCpuLimit + "%: Probe cooldown penalty " + $probePenaltyCounter + "s)") -ForegroundColor DarkGray
        }
        else {
            Write-Host ("[" + $now + "] " + $stateTag + " NVMe Temp: " + $temp + " C (Locked at optimal ceiling: " + $currentCpuLimit + "%, Poll: " + $pollInterval + "s)") -ForegroundColor $stateColor
        }
    }
    
    # Aggressive Stall Timeout Check
    if ($Aggressive) {
        if ($temp -ge 56) {
            $stalledHotCounter += $pollInterval
            if ($stalledHotCounter -ge 90 -and -not $isAggressiveThrottled) {
                $isAggressiveThrottled = $true
                $currentCpuLimit = [math]::Max(30, $currentCpuLimit - 10)
                Write-Host ("[" + $now + "] ⚠️ [AGGRESSIVE] Stalled >= 56 C for 90s! Forcing Deep Throttle to " + $currentCpuLimit + "% & De-prioritizing I/O...") -ForegroundColor DarkRed
                Set-CpuThrottleLimit -Percent $currentCpuLimit
                Set-BackgroundIoState -Suspend $true
            }
        } else {
            $stalledHotCounter = 0
            if ($isAggressiveThrottled -and $temp -le 52) {
                $isAggressiveThrottled = $false
                Write-Host ("[" + $now + "] [AGGRESSIVE] Temperature recovered <= 52 C. Restoring normal sync state.") -ForegroundColor DarkGreen
                Set-BackgroundIoState -Suspend $false
            }
        }
    }
    
    # Append to CSV log
    $logLine = $now + "," + $temp + "," + $currentCpuLimit + "," + $pollInterval + "," + $stateTag + "," + $statusMsg
    $logLine | Out-File -FilePath $LogFile -Append -Encoding utf8
    
    if ($Once) { break }
    Start-Sleep -Seconds $pollInterval
}
