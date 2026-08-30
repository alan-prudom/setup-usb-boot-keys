Write-Output "=========================================================="
Write-Output "       MSYS2 OpenSSH (Port 2222) & Mosh Audit             "
Write-Output "=========================================================="
Write-Output ""

# 1. Windows Service Check
Write-Output "=== 1. Windows Service Status ==="
$svc = Get-Service msys2_sshd -ErrorAction SilentlyContinue
if ($svc) {
    [PSCustomObject]@{
        ServiceName = $svc.Name
        DisplayName = $svc.DisplayName
        Status      = $svc.Status
        StartType   = $svc.StartType
    } | Format-Table -AutoSize
} else {
    Write-Output "[ERROR] 'msys2_sshd' service is not found in Windows Service Manager."
}

# 2. Port Listeners Check (TCP 2222 vs TCP 22)
Write-Output "=== 2. Active TCP Port Listeners ==="
$listeners = Get-NetTCPConnection -LocalPort 2222, 22 -ErrorAction SilentlyContinue
if ($listeners) {
    $listeners | Select-Object LocalAddress, LocalPort, State, @{N='Process';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}}, OwningProcess | Format-Table -AutoSize
} else {
    Write-Output "[WARN] Neither Port 2222 nor Port 22 are listening."
}

# 3. Windows Firewall Rules Check
Write-Output "=== 3. Windows Defender Firewall Inbound Rules ==="
$fwRules = Get-NetFirewallRule -DisplayName "*MSYS2*", "*Mosh*" -ErrorAction SilentlyContinue
if ($fwRules) {
    $fwRules | ForEach-Object {
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $_ -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            RuleName   = $_.DisplayName
            Protocol   = $portFilter.Protocol
            LocalPort  = $portFilter.LocalPort
            Action     = $_.Action
            Enabled    = $_.Enabled
        }
    } | Format-Table -AutoSize
} else {
    Write-Output "[WARN] No firewall rules found for MSYS2 or Mosh."
}

# 4. MSYS2 sshd_config & Host Keys Check
Write-Output "=== 4. MSYS2 /etc/ssh Configuration Audit ==="
$msysSshdConfig = "D:\msys64\etc\ssh\sshd_config"
$msysEtcSsh = "D:\msys64\etc\ssh"

if (Test-Path $msysSshdConfig) {
    Write-Output "[OK] Found MSYS2 sshd_config at $msysSshdConfig"
    $configLines = Get-Content $msysSshdConfig | Where-Object { $_ -match '^(Port|ClientAlive|TCPKeepAlive|AuthorizedKeysFile)' }
    $configLines | ForEach-Object { Write-Output "  -> $_" }
    
    $hostKeys = Get-ChildItem -Path $msysEtcSsh -Filter "ssh_host_*_key" -ErrorAction SilentlyContinue
    Write-Output ""
    Write-Output "Host Keys Generated: $($hostKeys.Count)"
    $hostKeys | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} else {
    Write-Output "[WARN] $msysSshdConfig not found at path."
}

# 5. Local Loopback Banner Test
Write-Output "=== 5. Local TCP Loopback Banner Test (Port 2222) ==="
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $async = $tcp.BeginConnect("127.0.0.1", 2222, $null, $null)
    $success = $async.AsyncWaitHandle.WaitOne(2000, $false)
    if ($success -and $tcp.Connected) {
        $stream = $tcp.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $banner = $reader.ReadLine()
        Write-Output "[OK] Successfully connected to 127.0.0.1:2222!"
        Write-Output "SSH Banner Returned: $banner"
        $tcp.Close()
    } else {
        Write-Output "[ERROR] TCP connection to 127.0.0.1:2222 timed out."
    }
} catch {
    Write-Output "[ERROR] Loopback connection test failed: $($_.Exception.Message)"
}

Write-Output ""
Write-Output "=========================================================="
Write-Output "             Verification Summary & Verdict               "
Write-Output "=========================================================="
if ($svc.Status -eq 'Running' -and ($listeners | Where-Object { $_.LocalPort -eq 2222 })) {
    Write-Output "ALL SYSTEMS GREEN: MSYS2 OpenSSH is running and listening on Port 2222!"
    Write-Output "You can now connect via:"
    Write-Output "  1. Standard SSH : ssh -p 2222 alanp@100.127.153.93"
    Write-Output "  2. Mosh Session : mosh --ssh='ssh -p 2222' alanp@100.127.153.93"
} else {
    Write-Output "ATTENTION NEEDED: Review the red/warning items above."
}
