# Post-Reboot State & Recovery Plan

**Timestamp:** 2026-09-05 17:15 (Pre-Reboot)  
**Host:** AP-HP-G5  

---

## 1. Current State Summary

### A. MATLAB Migration (Completed Successfully)
- **Host Container:** `F:\MATLAB.vhdx` (28.88 GB on disk).
- **Mounted Drive:** `M:\` (NTFS, 4 KB cluster size, 50 GB capacity, ~21.20 GB free).
- **Installed Versions on `M:\`:**
  - `M:\~R2017b`
  - `M:\~R2018b`
  - `M:\~R2020a`
  - `M:\~R2020b`
  *(All 284,436+ files verified copied).*
- **NTFS Junctions on Drive `D:\Program Files\MATLAB`:**
  - `D:\Program Files\MATLAB\~R2017b` &rarr; `M:\~R2017b`
  - `D:\Program Files\MATLAB\~R2018b` &rarr; `M:\~R2018b`
  - `D:\Program Files\MATLAB\~R2020a` &rarr; `M:\~R2020a`
  - `D:\Program Files\MATLAB\~R2020b` &rarr; `M:\~R2020b`
- **Reclaimed Space on `D:`:** ~26 GB freed, bringing `D:` up to ~50 GB free space.

### B. Why Explorer & CMD Hung Prior to Reboot
- When creating `F:\archives.vhdx`, PowerShell's `Initialize-Disk` cmdlet prompted for an interactive confirmation in the background.
- Force-cancelling while the Windows Storage Management / Virtual Disk Service (VDS) held an exclusive disk lock caused the volume manager to block subsequent query calls.
- In addition, intensive deletion of ~280k files exhausted the Windows Desktop Heap (`0xC0000142` DLL initialization error).
- **A system reboot cleanly clears the VDS lock and resets the desktop heap.**

---

## 2. Immediate Steps Upon Reboot

### Step 1: Mount `F:\MATLAB.vhdx` to `M:\`
Upon reboot, virtual disks do not auto-attach by default until configured. To mount MATLAB:
```powershell
Mount-VHD -Path "F:\MATLAB.vhdx"
```
*(If drive letter `M:` is not auto-assigned, it will remember its partition label and letter).*

### Step 2: Configure Auto-Mount at Windows Boot (Optional)
To make `F:\MATLAB.vhdx` mount automatically on every system boot:
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -Command Mount-VHD -Path 'F:\MATLAB.vhdx'"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "AutoMountMATLAB" -Action $action -Trigger $trigger -Principal $principal
```

### Step 3: Clean up & Create `F:\archives.vhdx`
1. Check if an incomplete `F:\archives.vhdx` file was created on `F:`. If present but unformatted:
   ```powershell
   # Dismount if attached
   Dismount-VHD -Path "F:\archives.vhdx" -ErrorAction SilentlyContinue
   Remove-Item "F:\archives.vhdx" -Force -ErrorAction SilentlyContinue
   ```
2. Create, initialize, and format cleanly in a single script with `-Confirm:$false`:
   ```powershell
   $vhdPath = "F:\archives.vhdx"
   New-VHD -Path $vhdPath -SizeBytes 300GB -Dynamic
   $disk = Mount-VHD -Path $vhdPath -PassThru
   Initialize-Disk -Number $disk.DiskNumber -PartitionStyle GPT -Confirm:$false
   New-Partition -DiskNumber $disk.DiskNumber -UseMaximumSize -DriveLetter V
   Format-Volume -DriveLetter V -FileSystem NTFS -AllocationUnitSize 4096 -NewFileSystemLabel "Archives" -Confirm:$false
   ```
3. Drive **`V:\`** will then be ready for you to manually copy and rearrange folders (like `/f/From elitebook/juneb`) at your own pace.
