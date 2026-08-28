$profileDirs = @(
    "C:\Users\alanp\Documents\PowerShell",
    "C:\Users\alanp\Documents\WindowsPowerShell"
)

$profileContent = @'
# Ensure User PATH entries (such as agy) are loaded for SSH remote sessions
$userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath) {
    foreach ($p in ($userPath -split ';' | Where-Object { $_ -and (Test-Path $_) })) {
        if ($env:PATH -split ';' -notcontains $p) {
            $env:PATH = "$p;$env:PATH"
        }
    }
}
'@

foreach ($dir in $profileDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $p1 = Join-Path $dir "profile.ps1"
    $p2 = Join-Path $dir "Microsoft.PowerShell_profile.ps1"
    Set-Content -Path $p1 -Value $profileContent -Encoding utf8
    Set-Content -Path $p2 -Value $profileContent -Encoding utf8
}

Write-Output "PowerShell profiles created successfully."
