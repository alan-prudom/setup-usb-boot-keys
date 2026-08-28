$ErrorActionPreference = 'SilentlyContinue'

Write-Output "=== 1. Purging User Temp & CrashDumps ==="
Get-ChildItem -Path "C:\Users\alanp\AppData\Local\Temp" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Users\alanp\AppData\Local\CrashDumps" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "Temp files cleaned."

Write-Output "=== 2A. Migrating .vscode (4.73 GB) to D:\.vscode ==="
$vscodeSrc = "C:\Users\alanp\.vscode"
$vscodeDst = "D:\.vscode"

if (Test-Path $vscodeSrc) {
    if (-not (Test-Path $vscodeDst)) {
        New-Item -ItemType Directory -Path $vscodeDst -Force | Out-Null
    }
    Move-Item -Path "$vscodeSrc\*" -Destination $vscodeDst -Force
    Remove-Item -Path $vscodeSrc -Recurse -Force
    New-Item -ItemType Junction -Path $vscodeSrc -Target $vscodeDst | Out-Null
    Write-Output "Junction created: $vscodeSrc -> $vscodeDst"
}

Write-Output "=== 2B. Migrating Docker AppData (5.70 GB) to D:\Docker_AppData ==="
$dockerSrc = "C:\Users\alanp\AppData\Local\Docker"
$dockerDst = "D:\Docker_AppData"

if (Test-Path $dockerSrc) {
    if (-not (Test-Path $dockerDst)) {
        New-Item -ItemType Directory -Path $dockerDst -Force | Out-Null
    }
    Move-Item -Path "$dockerSrc\*" -Destination $dockerDst -Force
    Remove-Item -Path $dockerSrc -Recurse -Force
    New-Item -ItemType Junction -Path $dockerSrc -Target $dockerDst | Out-Null
    Write-Output "Junction created: $dockerSrc -> $dockerDst"
}

Write-Output "=== Verification of Junctions ==="
Get-Item "C:\Users\alanp\.vscode", "C:\Users\alanp\AppData\Local\Docker" | Select-Object FullName, LinkType, Target | Format-List

Write-Output "=== Final Disk Space Summary ==="
Get-PSDrive C, D, G | Format-Table Name, Used, Free
