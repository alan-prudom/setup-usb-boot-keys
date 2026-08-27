# Windows 11 Unexpected Reboot Investigation & System State Audit

**System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Investigated Period**: July 31 – August 27, 2026  
**Document Date**: August 27, 2026  
**Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys`

---

## 1. Executive Summary & Problem Context

In late July and early August 2026, this machine experienced recurring unexpected system reboots while running Windows 11 Pro. After being powered off following the last crash on August 4, 2026, the machine was powered on again on August 27, 2026 without immediate crash loops.

A deep forensic query of the Windows System Event Logs, Kernel-Power crash telemetry, storage volume filters, and drive capacities was conducted to establish the exact chain of failure and identify necessary preventative maintenance.

---

## 2. Windows Event Log Forensic Findings

### Critical Crash Events Recorded (Kernel-Power Event ID 41)

Between July 31 and August 4, 2026, multiple `Event 41 (Kernel-Power)` critical entries were logged:

| Timestamp | Event ID | Bugcheck Code | Hex Code | Bugcheck Name & Meaning |
| :--- | :--- | :--- | :--- | :--- |
| **04/08/2026 13:16:15** | 41 | `239` | `0x000000EF` | `CRITICAL_PROCESS_DIED` |
| **04/08/2026 13:10:01** | 41 | `122` | `0x0000007A` | `KERNEL_DATA_INPAGE_ERROR` |
| **04/08/2026 11:37:58** | 41 | `340` | `0x00000154` | `UNEXPECTED_STORE_EXCEPTION` |
| **04/08/2026 00:30:46** | 41 | `239` | `0x000000EF` | `CRITICAL_PROCESS_DIED` |
| **04/08/2026 00:27:20** | 41 | `3221226010` | `0xC000021A` | `STATUS_SYSTEM_PROCESS_TERMINATED` |
| **04/08/2026 00:13:24** | 41 | `3221226010` | `0xC000021A` | `STATUS_SYSTEM_PROCESS_TERMINATED` |
| **03/08/2026 23:24:48** | 41 | `340` | `0x00000154` | `UNEXPECTED_STORE_EXCEPTION` |
| **03/08/2026 19:09:31** | 41 | `30` | `0x0000001E` | `KMODE_EXCEPTION_NOT_HANDLED` (`0xC0000006 STATUS_IN_PAGE_ERROR`) |
| **03/08/2026 18:41:53** | 41 | `122` | `0x0000007A` | `KERNEL_DATA_INPAGE_ERROR` |
| **03/08/2026 17:28:55** | 41 | `340` | `0x00000154` | `UNEXPECTED_STORE_EXCEPTION` |
| **02/08/2026 14:31:53** | 41 | `340` | `0x00000154` | `UNEXPECTED_STORE_EXCEPTION` |
| **01/08/2026 03:13:31** | 41 | `30` | `0x0000001E` | `KMODE_EXCEPTION_NOT_HANDLED` (`0xC0000006 STATUS_IN_PAGE_ERROR`) |
| **01/08/2026 01:30:17** | 41 | `30` | `0x0000001E` | `KMODE_EXCEPTION_NOT_HANDLED` (`0xC0000006 STATUS_IN_PAGE_ERROR`) |
| **31/07/2026 00:50:45** | 41 | `239` | `0x000000EF` | `CRITICAL_PROCESS_DIED` |

---

## 3. Root Cause Analysis

### Mechanism of Failure: Disk Paging & Storage Saturation
All five observed bugcheck codes point to the exact same underlying mechanism:

1. **`volmgr` (Event 161)**:  
   *"Dump file creation failed due to error during dump creation."* The storage stack could not allocate space to write crash dumps.
2. **`Volsnap` (Events 24 & 35)**:  
   *"There was insufficient disk space on volume C: to grow the shadow copy storage for shadow copies of C:. The shadow copies of volume C: were aborted because the shadow copy storage failed to grow."*
3. **`Ntfs` (Event 134)**:  
   NTFS transaction resource manager recovery failures on volume `C:`.

### Why the Crashes Happened When They Did
* **August 1, 2026 Update Batch**:  
  A major batch of Windows updates was committed (`KB5101650`, `KB5120102`, `KB5054156`, `KB5100998`, `KB5121768`).
* During update application and background servicing, shadow copy growth and temporary staging files consumed remaining free space on `C:`.
* When free space dropped below critical thresholds (< 500 MB), Windows could not dynamically expand `pagefile.sys`.
* Essential kernel and system process memory pages failed to read from or write to disk, throwing `STATUS_IN_PAGE_ERROR` (`0xC0000006`) and `UNEXPECTED_STORE_EXCEPTION` (`0x154`), resulting in blue screens / unexpected reboots.

### Why the System Is Currently Stable
* Following the crash on **August 4 at 13:16**, the PC was shut down until **August 27**.
* The heavy transactional update staging has finished, returning disk space to ~5.04 GB free and avoiding immediate paging failures during idle operation.

---

## 4. Current System & Storage Audit (August 27, 2026)

### Hardware & OS State
* **Machine**: HP ZBook 15u G5
* **CPU**: Intel Core i7-8550U @ 1.80GHz (4 Cores / 8 Threads)
* **RAM**: 16 GB DDR4 (15.85 GB usable)
* **OS**: Windows 11 Pro (Build 26200)
* **NVMe SSD**: Samsung MZVLB512HAJQ-000H1 (512 GB) - **SMART Health: OK / Healthy**

### Live Drive Utilization

| Volume | Drive Letter | File System | Total Size | Free Space | % Free | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Windows OS** | `C:` | NTFS | 216.0 GB | 5.04 GB | **2.3%** | **High Risk / Action Required** |
| **Data Partition** | `D:` | NTFS | 259.7 GB | 10.69 GB | 4.1% | Warning |
| **SD Card Storage**| `G:` | NTFS | 81.0 GB | 56.54 GB | 69.8% | Healthy |
| **Ventoy USB** | `E:` | exFAT | 19.0 GB | 1.30 GB | 6.8% | Warning |

---

## 5. Summary of Actions & Maintenance Checklist

To permanently prevent the return of `UNEXPECTED_STORE_EXCEPTION` and `KERNEL_DATA_INPAGE_ERROR` crashes:

1. **Reclaim Component Store & Update Space**:
   ```cmd
   Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
   net stop wuauserv
   del /f /s /q C:\Windows\SoftwareDistribution\Download\*
   net start wuauserv
   ```
2. **Disable Hibernation (If not actively utilized)**:
   ```cmd
   powercfg /h off
   ```
---

## 6. Remote Connectivity & Service Daemon Endpoints (Audit 27 August 2026)

### IP Addresses for Remote Access & AgentsView
* **Local Subnet (Home / LAN)**: `192.168.1.159`
* **Tailscale Mesh VPN**: `100.127.153.93`
* **Local Machine / Host**: `127.0.0.1` (`localhost`)

### OpenSSH Server Status
* **Service Name**: `sshd` (OpenSSH SSH Server)
* **Status**: **Running** (Startup Type: `Automatic`)
* **Listening Endpoints**: Port 22 (`0.0.0.0:22` & `[::]:22`)
* **SSH Direct Login**:
  * Local LAN: `ssh alanp@192.168.1.159`
  * Tailscale: `ssh alanp@100.127.153.93`

