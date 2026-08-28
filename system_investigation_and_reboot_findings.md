# Windows 11 Unexpected Reboot Investigation & System State Audit

**System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)
**Investigated Period**: July 31 – August 28, 2026
**Last Updated**: August 28, 2026
**Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys`

---

## 1. Executive Summary

This HP ZBook 15u G5 experienced recurring unexpected reboots spanning July 31 – August 28, 2026. Five compounding root causes were identified and remediated.

### Root Causes Summary

| # | Root Cause | Status |
| :--- | :--- | :--- |
| 1 | C: drive critically low on free space — pagefile, VSS, and crash dump all starved | Fixed |
| 2 | Pagefile manually hard-capped at 1,000 MB — kernel memory starvation | Fixed |
| 3 | VSS shadow storage hard-capped — snapshot abort freezing disk I/O | Fixed |
| 4 | AvastCleanupSvc holding exclusive registry locks during system operations | Fixed |
| 5 | NVMe thermal throttling — drive reaching 81C, causing 485ms read latency spikes | HARDWARE ACTION REQUIRED |

---

## 2. Crash Event Log

### 2.1 Historic Crashes (July 31 - August 4, 2026)

| Timestamp | Bugcheck | Hex | Name |
| :--- | :--- | :--- | :--- |
| 04/08/2026 13:16 | 239 | 0xEF | CRITICAL_PROCESS_DIED |
| 04/08/2026 13:10 | 122 | 0x7A | KERNEL_DATA_INPAGE_ERROR |
| 04/08/2026 11:37 | 340 | 0x154 | UNEXPECTED_STORE_EXCEPTION |
| 03/08/2026 23:24 | 340 | 0x154 | UNEXPECTED_STORE_EXCEPTION |
| 03/08/2026 19:09 | 30 | 0x1E | KMODE_EXCEPTION_NOT_HANDLED (0xC0000006) |
| 01/08/2026 03:13 | 30 | 0x1E | KMODE_EXCEPTION_NOT_HANDLED (0xC0000006) |
| 31/07/2026 00:50 | 239 | 0xEF | CRITICAL_PROCESS_DIED |

### 2.2 Active Crashes During August 28 Session

| Timestamp | Bugcheck | Hex | Name |
| :--- | :--- | :--- | :--- |
| 28/08/2026 10:28 | 340 | 0x154 | UNEXPECTED_STORE_EXCEPTION |
| 28/08/2026 10:44 | 340 | 0x154 | UNEXPECTED_STORE_EXCEPTION |
| 28/08/2026 10:59 | 340 | 0x154 | UNEXPECTED_STORE_EXCEPTION |
| 28/08/2026 11:15 | 122 | 0x7A | KERNEL_DATA_INPAGE_ERROR |
| 28/08/2026 11:29 | 30 | 0x1E | KMODE_EXCEPTION_NOT_HANDLED (0xC0000006) |

Every crash was accompanied by volmgr Event 161: Dump file creation failed (BugCheckProgress 0x00040049).
No minidumps were created throughout — the dump writer stalled on every crash.

---

## 3. Root Cause Analysis

### 3.1 C: Drive Critically Low on Free Space

Starting free space on August 27: 3.57 GB on a 216 GB volume.

Large directories migrated to free space:

| Path | Size | Action |
| :--- | :--- | :--- |
| C:\Sync | 13.77 GB | Moved to D:\sync + NTFS junction |
| C:\Users\alanp\My Drive | 18.2 GB | Moved to G:\My Drive + NTFS junction |
| C:\Users\alanp\.vscode | 4.73 GB | Moved to D:\.vscode + NTFS junction |
| C:\Users\alanp\AppData\Local\Docker | 5.70 GB | Moved to D:\Docker_AppData + NTFS junction |
| C:\Windows\SoftwareDistribution\Download | ~2 GB | Cleared |
| DISM Component Store | ~1.5 GB | Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase |
| AppData\Local\Temp + CrashDumps | ~1.3 GB | Purged |

Result: C: free space 3.57 GB to 30.69 GB (maintained at 17-19 GB with dynamic pagefile).

### 3.2 Pagefile Hard-Capped at 1,000 MB

Virtual Memory was manually locked:
  C:\pagefile.sys: 1000 MB minimum and maximum
  AutomaticManagedPagefile: False

Even with 30 GB free disk space, the pagefile could not expand beyond 1 GB.
When memory pressure exceeded this, the Windows Store Manager threw 0x154.

Fix: Set AutomaticManagedPagefile = True (requires admin session).
A reboot was required to apply the change. The 10:44 crash occurred during this transition.

After fix:
  PagingFiles: ?:\pagefile.sys
  AutomaticManagedPagefile: True

### 3.3 VSS Shadow Storage Hard-Capped

Volsnap Event 36 was recorded immediately before the 10:59 crash:
  The shadow copies of volume C: were aborted because the shadow copy storage
  could not grow due to a user imposed limit.

When System Restore triggered a snapshot and hit the cap, the Volsnap abort froze
in-flight NTFS I/O, causing a kernel store timeout.

Fix applied (admin terminal):
  vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10GB

Post-fix: No Volsnap Event 36 errors recorded.

### 3.4 AvastCleanupSvc Registry Lock

Application Log Event 1552 (User Profiles Service):
  User hive is loaded by another process (Registry Lock):
  C:\Program Files\AVAST Software\Cleanup\TuneupSvc.exe, PID 10028

AvastCleanupSvc held an exclusive lock on the user registry hive, blocking NTFS flush
operations. Additionally 3 concurrent TuneupUI.exe instances consumed ~128 MB RAM.

Fix applied (admin terminal):
  sc stop AvastCleanupSvc
  sc config AvastCleanupSvc start= disabled

Confirmed: Status Stopped, StartType Disabled.

### 3.5 NVMe Thermal Throttling — HARDWARE ACTION REQUIRED

SMART reliability data (via admin PowerShell Get-StorageReliabilityCounter):

  Device:          SAMSUNG MZVLB512HAJQ-000H1 (512 GB, Firmware EXA73H1Q)
  Wear:            0     -- NAND cells HEALTHY, drive is NOT worn out
  Temperature:     56C   -- current (at idle)
  TemperatureMax:  81C   -- maximum ever recorded  ** CRITICAL **
  ReadLatencyMax:  485ms -- catastrophically high (should be under 1ms)
  WriteLatencyMax: 82ms
  ReadErrorsUncorrected: none

What happens at 81C:
Samsung NVMe firmware throttles at ~70C, dropping throughput from ~2,000 MB/s to near zero.
Kernel page reads stall for up to 485ms, far beyond the I/O timeout threshold, triggering:
  - 0x154 UNEXPECTED_STORE_EXCEPTION
  - 0x7A  KERNEL_DATA_INPAGE_ERROR
  - 0x1E / 0xC0000006 STATUS_IN_PAGE_ERROR

This was confirmed by 10 consecutive Storage-ATAPort Event 507 errors (Completing a failed
non-ReadWrite SCSI SRB request) immediately before the 11:29 crash.

Why the drive reached 81C on August 28:
The session involved >40 GB of sustained NVMe writes (folder migrations), combined with
Firefox (3.3 GB RAM across 6 processes), Dropbox sync (1 GB RAM), and Avast Cleanup
all driving simultaneous I/O while the laptop sat flat on a desk.

Required hardware remediation:

  1. IMMEDIATE: Raise laptop on a stand to restore underside airflow.
  2. SHORT TERM: Blow compressed air through vents to clear dust from fan/heatsink.
  3. DEFINITIVE FIX: Open bottom panel and replace M.2 thermal pad.
     Use 1mm high-conductivity pad between NVMe card and chassis metal spreader.
     Expected temperature drop: 15-25C.

---

## 4. NTFS Observations — August 1 Update Crash

At 01/08/2026 11:48:23, 19 consecutive Ntfs Event 134 warnings were recorded:
  The transaction resource manager on volume Windows encountered an error during
  recovery. The resource manager will continue recovery.

NTFS found unclean transaction journals after the August 1 crash cascade and performed
automatic rollback recovery. No permanent corruption detected. A scheduled chkdsk C: /f
is recommended to confirm clean NTFS state.

---

## 5. Active NTFS Junctions (August 27-28, 2026)

All created using: New-Item -ItemType Junction -Path <src> -Target <dst>

| Junction on C: | Target | Size Reclaimed |
| :--- | :--- | :--- |
| C:\Sync | D:\sync | 13.77 GB |
| C:\Users\alanp\My Drive | G:\My Drive | 18.20 GB |
| C:\Users\alanp\.vscode | D:\.vscode | 4.73 GB |
| C:\Users\alanp\AppData\Local\Docker | D:\Docker_AppData | 5.70 GB |

---

## 6. Final Drive State (August 28, 2026)

| Volume | Letter | Total | Free Space | Status |
| :--- | :--- | :--- | :--- | :--- |
| Windows OS | C: | 216 GB | ~17-19 GB | Healthy |
| Data SSD | D: | 259.7 GB | ~22 GB | Healthy |
| SD Card | G: | 81 GB | ~45 GB | Healthy |

Note: C: free space varies as the automatic pagefile dynamically sizes under load.

---

## 7. System Configuration Changes Applied

### Virtual Memory
  Before: C:\pagefile.sys hard-capped at 1,000 MB (manual), AutomaticManagedPagefile False
  After:  AutomaticManagedPagefile True

### Volume Shadow Copy Storage
  Before: User-imposed limit causing Volsnap Event 36 abort
  After:  vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10GB

### Avast Cleanup Service
  Before: Auto-start, holding registry locks, performing background disk I/O
  After:  sc stop AvastCleanupSvc && sc config AvastCleanupSvc start= disabled

### Tailscale (August 27, 2026)
  Enabled unattended background start: tailscale.exe set --unattended
  VPN tunnel available pre-login at 100.127.153.93

---

## 8. Remote Connectivity & SSH Access

| Method | Address |
| :--- | :--- |
| Local LAN | ssh alanp@192.168.1.159 |
| Tailscale VPN | ssh alanp@100.127.153.93 |
| OpenSSH service | sshd - Automatic, Port 22 |

---

## 9. Outstanding Actions

| Action | Priority | Notes |
| :--- | :--- | :--- |
| Replace NVMe M.2 thermal pad | HIGH | Drive hitting 81C -- remaining crash risk under heavy load |
| Run chkdsk C: /f (scheduled) | Medium | Confirm NTFS journal clean after August 1 crash recovery |
| Archive D:\Ubuntu16 (8.78 GB, 243863 files) | Medium | tar -czf D:\Ubuntu16_archive.tar.gz -C D:\ --exclude=Ubuntu16/fsserver Ubuntu16 |
| Install Samsung Magician | Medium | Get full raw SMART attribute baseline (Power-On Hours, Wear Level) |
| Monitor D: free space | Medium | D: absorbed 24+ GB of junctions, now at ~22 GB free |
| Reduce concurrent Firefox sessions | Low | 6 processes = 3.3 GB RAM peak, drives heavy NVMe paging |
