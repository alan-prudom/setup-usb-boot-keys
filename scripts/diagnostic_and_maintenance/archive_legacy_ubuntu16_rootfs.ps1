$archivePath = "D:\Ubuntu16_archive.tar.gz"
Write-Output "Starting compression of D:\Ubuntu16 (excluding dead WSL IPC sockets) into $archivePath..."

$tarExe = "C:\Windows\System32\tar.exe"
$process = Start-Process -FilePath $tarExe -ArgumentList "-czf", $archivePath, "--exclude=Ubuntu16/fsserver", "-C", "D:\", "Ubuntu16" -Wait -PassThru -NoNewWindow

if ($process.ExitCode -eq 0 -and (Test-Path $archivePath)) {
    $archiveSizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
    $archiveSizeGB = [math]::Round((Get-Item $archivePath).Length / 1GB, 2)
    Write-Output "Archive successfully created!"
    Write-Output "Archive File: $archivePath ($archiveSizeMB MB / $archiveSizeGB GB)"
} else {
    Write-Error "Archiving finished with exit code $($process.ExitCode)."
}
