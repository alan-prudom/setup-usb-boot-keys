# G5 Storage Maintenance, VHDX Automount & Small File Audit

**System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Operating System**: Windows 11 Pro 64-bit  
**Date**: September 5, 2026  
**Target Drive**: `F:\` (1TB SanDisk SSD, exFAT, 931 GB total)  
**Primary Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys` (Branch `main`)  

---

## 1. Executive Summary

Following an unexpected hard shutdown via the physical power button, a diagnostic and optimization sequence was performed on external SSD drive `F:`:
1. **Filesystem Integrity Check**: Executed `chkdsk F:` verifying zero filesystem corruption and 0 KB bad sectors.
2. **Virtual Disk (`archives.vhdx`) Initialization**:
   - Initialized `F:\archives.vhdx` (300 GB dynamic virtual disk).
   - Formatted as **NTFS** with label `Archives`.
   - Assigned persistent drive letter **`V:`** (299.88 GB free).
3. **Automount Infrastructure**:
   - Developed `F:\mount-vhdx.ps1` (mounts `archives.vhdx` -> `V:` and `MATLAB.vhdx` -> `M:`).
   - Developed `F:\dismount-vhdx.ps1` (clean dismount helper).
   - Developed `F:\register-automount-task.ps1` (Windows Scheduled Task running on boot & user logon).
4. **Storage Density & Cluster Efficiency Audit**:
   - Scanned 280,000+ files on `F:` to locate clusters of small files suffering from exFAT allocation overhead.
   - Identified `Evernote 2023` containing **234,427 files < 1 MB** (97.2% of its 35.2 GB footprint) as the primary candidate for NTFS migration.

---

## 2. CHKDSK Verification on F:

`chkdsk F:` output summary:
* **Result**: Windows has scanned the file system and found no problems.
* **Bad sectors**: 0 KB.
* **Total disk space**: 976,721,920 KB (~931.5 GB).
* **In files / indexes**: 390,922,240 KB in 279,317 files; 37,865,472 KB in indexes.
* **Available free space**: 547,932,160 KB (~522.5 GB).
* **Allocation Unit Size**: 1,048,576 bytes (1 MB cluster size).

---

## 3. VHDX Virtual Hard Disk Configuration

The 1 MB cluster size of exFAT imposes significant slack-space overhead for small files. To provide native 4 KB cluster NTFS storage within the portable SSD, dynamic VHDX virtual disks are utilized:

| VHDX Path | Virtual Size | File System | Drive Letter | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `F:\archives.vhdx` | 300 GB | NTFS | **`V:`** | General archive & high-density small file storage |
| `F:\MATLAB.vhdx` | 50 GB | NTFS | **`M:`** | MATLAB installation and runtime files |

### Initialization Commands Executed:
```powershell
$disk = Get-VHD -Path F:\archives.vhdx | Get-Disk
Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru | 
    New-Partition -UseMaximumSize -DriveLetter V | 
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Archives" -Confirm:$false
```

---

## 4. Automation & Maintenance Scripts on F:

Three operational scripts are maintained in the root of `F:\`:

### 1. `F:\mount-vhdx.ps1`
Inspects `archives.vhdx` and `MATLAB.vhdx`. If detached, attaches them cleanly without duplicating drive mappings.

### 2. `F:\dismount-vhdx.ps1`
Iterates through attached VHDX disks and dismounts them cleanly prior to disconnecting the USB drive or initiating a reboot.

### 3. `F:\register-automount-task.ps1`
Registers a scheduled task (`AutoMountVHDX`) under `NT AUTHORITY\SYSTEM` with triggers for both `AtStartup` and `AtLogOn`.

---

## 5. Small File Audit Results (Drive F:)

A directory-by-directory recursive scan of all top-level folders on `F:` yielded the following density breakdown:

| Directory | Total Files | Files < 1 MB | % Small Files | Total Size | Avg File Size |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`Evernote 2023`** | **241,179** | **234,427** | **97.2%** | **35.2 GB** | **149.4 KB** |
| **`Evernote import`** | **12,023** | **11,575** | **96.3%** | **2.6 GB** | **219.7 KB** |
| **`From elitebook`** | **12,576** | **11,399** | **90.6%** | **28.1 GB** | **2.3 MB** |
| **`panic backup`** | **5,975** | **5,879** | **98.4%** | **2.6 GB** | **452.6 KB** |
| **`R-NotebookLM`** | **3,741** | **3,654** | **97.7%** | **2.5 GB** | **697.2 KB** |
| **`Sync backup`** | **2,843** | **2,787** | **98.0%** | **1.5 GB** | **528.1 KB** |
| **`ENEX`** | 70 | 35 | 50.0% | 3.4 GB | 49.5 MB |
| **`Junes stuff`** | 30 | 8 | 26.7% | 9.5 GB | 324.8 MB |
| **`from G5`** | 3 | 2 | 66.7% | 4.9 MB | 1.7 MB |
| **`My Drive from Chromebit`** | 2 | 2 | 100.0% | 0.6 MB | 284.4 KB |
| **`md5tree`** | 1 | 1 | 100.0% | 0.6 MB | 657.0 KB |

### Analysis:
On exFAT with 1 MB allocation units, storing 234,000 files averaging ~150 KB wastes considerable physical storage due to cluster slack. Moving `Evernote 2023`, `Evernote import`, and `panic backup` into `V:\` (NTFS 4 KB clusters) eliminates slack-space bloat and improves directory traversal performance.
