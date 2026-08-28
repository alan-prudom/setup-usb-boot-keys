$source = "C:\Users\alanp\My Drive"
$dest = "G:\My Drive"

Write-Output "Step 1: Moving $source to $dest..."
if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

Move-Item -Path "$source\*" -Destination $dest -Force
Remove-Item -Path $source -Recurse -Force

Write-Output "Step 2: Creating NTFS Junction at $source targeting $dest..."
New-Item -ItemType Junction -Path $source -Target $dest | Out-Null

Write-Output "=== Verification ==="
Get-Item -Path $source | Select-Object FullName, LinkType, Target | Format-List

Write-Output "=== Updated Disk Free Space on C: ==="
Get-PSDrive C, G | Select-Object Name, @{N='FreeGB';E={[math]::Round($_.Free/1GB, 2)}}
