[CmdletBinding()]
param(
    [int]$TargetTemp = 58,
    [int]$DurationSeconds = 60
)

function Get-NVMeTemp {
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

Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  High-Intensity Multi-Threaded Thermal Stress Test" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host ("  Target Duration : " + $DurationSeconds + " seconds") -ForegroundColor Black
Write-Host ("  Safety Cutoff   : " + $TargetTemp + " C (Auto-aborts when reached)") -ForegroundColor DarkRed
Write-Host ("  Workload        : 8 Parallel CPU Threads + Sustained NVMe I/O") -ForegroundColor Black
Write-Host "  Press Ctrl+C to abort manually at any time." -ForegroundColor DarkGray
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

$startTemp = Get-NVMeTemp
Write-Host ("  Starting NVMe Temp: " + $startTemp + " C") -ForegroundColor DarkGreen

# 1. Start 8 Background Runspaces for CPU Saturation
$cpuScript = {
    $sha = [System.Security.Cryptography.SHA512]::Create()
    $buf = New-Object byte[] (64 * 1024)
    while ($true) {
        $hash = $sha.ComputeHash($buf)
    }
}

$threadCount = [System.Environment]::ProcessorCount
Write-Host ("Spinning up " + $threadCount + " parallel CPU saturation threads...") -ForegroundColor DarkCyan

$runspaces = @()
$pool = [RunspaceFactory]::CreateRunspacePool(1, $threadCount)
$pool.Open()

for ($i = 0; $i -lt $threadCount; $i++) {
    $ps = [PowerShell]::Create().AddScript($cpuScript)
    $ps.RunspacePool = $pool
    $handle = $ps.BeginInvoke()
    $runspaces += @{ PS = $ps; Handle = $handle }
}

# 2. Disk I/O Preparation
$testDir = "D:\_thermal_stress_io"
if (-not (Test-Path $testDir)) {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
}

$chunk = New-Object byte[] (16 * 1024 * 1024) # 16 MB chunk
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($chunk)

$startTime = Get-Date
$iteration = 0

try {
    while ($true) {
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
        if ($elapsed -ge $DurationSeconds) {
            Write-Host ("[COMPLETED] Reached maximum test duration of " + $DurationSeconds + "s.") -ForegroundColor DarkGreen
            break
        }
        
        # Write and flush 64 MB to NVMe
        $tempFile = Join-Path $testDir ("nvme_stress_" + ($iteration % 4) + ".dat")
        $fs = [System.IO.File]::Open($tempFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        for ($k = 0; $k -lt 4; $k++) {
            $fs.Write($chunk, 0, $chunk.Length)
        }
        $fs.Flush($true)
        $fs.Close()
        
        $iteration++
        
        # Read temperature every write cycle
        $curTemp = Get-NVMeTemp
        if ($null -ne $curTemp) {
            $msg = "[" + $elapsed + "s] NVMe Temp: " + $curTemp + " C"
            if ($curTemp -ge $TargetTemp) {
                Write-Host ($msg + " -> [SAFETY CUTOFF REACHED (>= " + $TargetTemp + " C)! Stopping test.]") -ForegroundColor DarkRed
                break
            } elseif ($curTemp -ge ($TargetTemp - 3)) {
                Write-Host $msg -ForegroundColor DarkYellow
            } else {
                Write-Host $msg -ForegroundColor DarkGreen
            }
        }
    }
} finally {
    # Clean up CPU worker threads
    Write-Host "Stopping background CPU worker threads..." -ForegroundColor DarkGray
    foreach ($r in $runspaces) {
        $r.PS.Stop()
        $r.PS.Dispose()
    }
    $pool.Close()
    $pool.Dispose()
    
    # Clean up temporary I/O files
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    $endTemp = Get-NVMeTemp
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("Stress Test Finished. Final NVMe Temp: " + $endTemp + " C (Started at " + $startTemp + " C)") -ForegroundColor DarkCyan
}
