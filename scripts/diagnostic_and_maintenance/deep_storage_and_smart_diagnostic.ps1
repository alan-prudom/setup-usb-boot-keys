Write-Output "=== 1. Physical Disk Details ==="
Get-Disk | Format-List *

Write-Output "=== 2. SMART Failure Predict Status (WMI) ==="
try {
    $fp = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop
    $fp | Format-List InstanceName, PredictFailure, Reason
} catch { Write-Output "Access denied or not available: $_" }

Write-Output "=== 3. SMART Failure Predict Data (Raw Attributes) ==="
try {
    $fa = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictData -ErrorAction Stop
    foreach ($d in $fa) {
        Write-Output "Drive: $($d.InstanceName)"
        $bytes = $d.VendorSpecific
        # SMART attributes are 12-byte structs starting at byte 2
        for ($i = 2; $i -lt $bytes.Length - 12; $i += 12) {
            $attrId  = $bytes[$i]
            if ($attrId -eq 0) { continue }
            $flags   = [BitConverter]::ToUInt16($bytes, $i+1)
            $current = $bytes[$i+3]
            $worst   = $bytes[$i+4]
            $rawVal  = [BitConverter]::ToInt32($bytes, $i+5)
            $known   = switch ($attrId) {
                1   { "Raw Read Error Rate" }
                5   { "Reallocated Sectors Count" }
                9   { "Power-On Hours" }
                12  { "Power Cycle Count" }
                177 { "Wear Leveling Count" }
                179 { "Used Reserved Block Count Total" }
                180 { "Unused Reserved Block Count Total" }
                181 { "Program Fail Count Total" }
                182 { "Erase Fail Count Total" }
                183 { "Runtime Bad Block" }
                187 { "Reported Uncorrectable Errors" }
                190 { "Airflow Temperature Celsius" }
                195 { "ECC Error Rate" }
                196 { "Reallocation Event Count" }
                197 { "Current Pending Sector Count" }
                198 { "Uncorrectable Sector Count" }
                199 { "UltraDMA CRC Error Count" }
                233 { "Media Wearout Indicator" }
                235 { "POR Recovery Count" }
                241 { "Total LBAs Written" }
                242 { "Total LBAs Read" }
                default { "Attr_$attrId" }
            }
            Write-Output ("  [{0:D3}] {1,-35} Current={2,3} Worst={3,3} Raw={4}" -f $attrId, $known, $current, $worst, $rawVal)
        }
    }
} catch { Write-Output "Access denied or not available: $_" }

Write-Output ""
Write-Output "=== 4. NVMe Error Log: All Event 507 SRB Failures (Last 7 Days) ==="
$since = (Get-Date).AddDays(-7)
$srb = Get-WinEvent -LogName "Microsoft-Windows-Storage-ATAPort/Operational" -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 507 -and $_.TimeCreated -gt $since }
Write-Output "Total Event 507 failures in last 7 days: $($srb.Count)"
$srb | Group-Object { $_.TimeCreated.ToString("yyyy-MM-dd HH:mm") } |
    Select-Object Name, Count | Sort-Object Name | Format-Table -AutoSize

Write-Output "=== 5. StorPort Operational Errors (Last 7 Days) ==="
Get-WinEvent -LogName "Microsoft-Windows-StorPort/Operational" -ErrorAction SilentlyContinue |
    Where-Object { $_.Level -le 2 -and $_.TimeCreated -gt $since } |
    Select-Object -First 20 | Format-Table TimeCreated, Id, LevelDisplayName, Message -Wrap

Write-Output "=== 6. NTFS / Disk Error Events (All time) ==="
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk','ntfs','Ntfs','NTFS'} -MaxEvents 20 -ErrorAction SilentlyContinue |
    Format-Table TimeCreated, ProviderName, Id, LevelDisplayName, Message -Wrap

Write-Output "=== 7. CHKDSK Results (Application Log) ==="
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Microsoft-Windows-Chkdsk','Wininit'} -MaxEvents 5 -ErrorAction SilentlyContinue |
    Format-Table TimeCreated, Id, Message -Wrap
