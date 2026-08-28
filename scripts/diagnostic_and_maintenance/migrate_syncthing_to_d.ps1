$source = "C:\Sync"
$dest = "D:\Sync"

Write-Output "Step 1: Copying $source to $dest with Robocopy (/E /COPY:DAT /DCOPY:DAT)..."
if (-not (Test-Path $dest)) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
}

$robocopyArgs = @(
    $source,
    $dest,
    "/E",
    "/COPY:DAT",
    "/DCOPY:DAT",
    "/R:2",
    "/W:2",
    "/NFL",
    "/NDL",
    "/NP"
)

$process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
Write-Output "Robocopy finished with exit code: $($process.ExitCode)"

# Exit codes 0-7 mean copy succeeded (0=no change, 1=files copied, 2=extra files, etc.)
if ($process.ExitCode -le 7) {
    Write-Output "Step 2: Copy succeeded. Verifying file counts..."
    $srcCount = (Get-ChildItem -Path $source -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    $dstCount = (Get-ChildItem -Path $dest -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Output "Source item count: $srcCount | Destination item count: $dstCount"

    if ($dstCount -ge $srcCount -and $dstCount -gt 0) {
        Write-Output "Step 3: Removing original $source to reclaim space on C:..."
        Remove-Item -Path $source -Recurse -Force
        
        Write-Output "Step 4: Creating NTFS Junction from $source to $dest..."
        New-Item -ItemType Junction -Path $source -Target $dest | Out-Null
        
        Write-Output "SUCCESS: C:\Sync is now an NTFS junction pointing to D:\Sync."
        Get-Item -Path $source | Select-Object FullName, LinkType, Target | Format-List
        
        Write-Output "=== Updated Disk Free Space on C: ==="
        Get-PSDrive C | Select-Object Used, Free
    } else {
        Write-Error "Item count verification failed ($srcCount vs $dstCount). C:\Sync was NOT deleted."
    }
} else {
    Write-Error "Robocopy encountered an error (exit code $($process.ExitCode)). Migration aborted."
}
