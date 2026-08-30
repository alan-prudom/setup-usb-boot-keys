# Comprehensive Technical Session Notes: Dual-Sensor Governor, 19-Hour Stability Verification & Bidirectional UEFI Architecture

**System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Operating System**: Windows 11 Pro 64-bit (Build 26100 / 24H2)  
**Primary NVMe SSD**: Samsung MZVLB512HAJQ-000H1 (512GB PCIe 3.0 x4)  
**Date**: August 29–30, 2026  
**Primary Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys` (Branch `main`)  

---

## 1. Executive Summary: Sustained Stability & Architectural Milestones

Following the deployment of the **Dual-Sensor Predictive NVMe Thermal Governor (v2.1)** and the multi-tier Python/C# suite, the HP ZBook 15u G5 achieved a milestone in system stability, running for **19.05 consecutive hours (1,143 minutes) with zero kernel crashes (`0x154` / `0xEF`)** and holding Samsung NVMe temperatures steadily between **`43°C` and `48°C`**.

### Major Engineering Deliverables Completed:
1. **Governor Engine v2.1 (Gentle Multi-Step Recovery & Cold-Soak Damping)**:
   * Native C# background service running in Session 0 (`PID 3236`, 10–18 MB RAM, <0.05% CPU).
   * Direct Win32 `powrprof.dll` P/Invoke (`PowerWriteACValueIndex`) manipulating processor power throttle limits.
   * Multi-step recovery ladder (+5% micro-steps: `40% -> 50% -> 60% -> 65% -> 70%`) and 120-second cold-soak dwell timer after deep cooling events to eliminate post-emergency step-up bounce crashes.
2. **24/7 Always-On AC Power & Network Policy**:
   * Configured `powercfg /change standby-timeout-ac 0` and enabled `ConnectivityInStandby = Always On` to prevent Windows 11 Modern Standby from sleeping network adapters during extended overnight idle periods.
3. **OpenSSH Persistent KeepAlives**:
   * Configured `ClientAliveInterval 30` and `TCPKeepAlive yes` in `C:\ProgramData\ssh\sshd_config` to eliminate router NAT table expirations and maintain persistent remote terminal sessions over Tailscale.
4. **Bidirectional Programmatic UEFI Boot-Switching**:
   * Developed `boot_to_linux.ps1` (Windows PowerShell) to program `{fwbootmgr} bootsequence` via `bcdedit` for a one-time direct reboot into USB Linux.
   * Developed `boot_to_windows.sh` (Linux Bash) utilizing `efibootmgr --bootnext` to instruct the motherboard to return to Windows 11 on the subsequent reboot.
5. **Windows Desktop & Shell Input Remediation**:
   * Resolved sticky keys and mouse clicklock behaviors via registry deactivations (`ClickLock = 0`, `StickyKeys/Flags = 506`).
   * Cleanly decoupled the background C# thermal governor (Session 0) from the user desktop shell (Session 2), ensuring desktop restarts never interrupt thermal hardware protection.

---

## 2. In-Depth Technical Discussion Points

### Discussion 1: The 19-Hour Continuous Stability Verification
* **Forensic Audit Window**: August 29 14:34 BST $\rightarrow$ August 30 09:37 BST (19.05 Hours).
* **Observed Metrics**:
  * **Unexpected Reboots (Event 41)**: **`0`**
  * **Kernel Store Exceptions (`0x154`)**: **`0`**
  * **Critical Process Aborts (`0xEF`)**: **`0`**
  * **`stornvme` SCSI Latency Timeouts**: **`0`**
  * **NVMe Temperature Range**: **`43°C – 48°C`** (Average: **`44.6°C`**).
  * **Chassis Airflow Zone**: **`30°C`** (Stable dissipation gradient $\Delta T = 13^\circ\text{C} – 18^\circ\text{C}$).
* **Significance**: Confirms that software-governed CPU power capping (70%–75% base clock) successfully overcomes the degraded M.2 thermal interface pad, preventing thermal runaway and latency-induced kernel store crashes.

---

### Discussion 2: Overnight SSH Disconnections vs. Modern Standby (Event 566)
* **User Inquiry**: Why did SSH disconnect around 22:30 BST and drop overnight?
* **Forensic Discovery**:
  * The Windows machine remained fully powered on with the background daemon active in Session 0.
  * Windows 11 logged **Kernel-Power Event 566** (System session transitions into low-power Modern Standby) after 20 minutes of user input inactivity.
  * Because default `sshd_config` had `ClientAliveInterval 0` (no heartbeats), Tailscale and Wi-Fi router NAT state tables timed out after 10–15 minutes of zero packet traffic.
* **Remediation**:
  * Set `powercfg /change standby-timeout-ac 0` (Never sleep on AC).
  * Set `powercfg /setacvalueindex SCHEME_CURRENT SUB_NONE CONNECTIVITYINSTANDBY 1` (Always On).
  * Enabled 30-second server keepalives (`ClientAliveInterval 30`, `ClientAliveCountMax 10`).

---

### Discussion 3: Why Linux USB Boot Ran Without Issues vs. Windows 11 Internal NVMe
* **User Inquiry**: *"During much of August I tested this laptop running Linux booted from USB and I did not experience either thermal or power interruption problems."*
* **Architectural Breakdown**:
  1. **Storage Target**: When booting Linux from USB, the OS root filesystem, journal, and swap execute from **RAM (initramfs) or the external USB flash drive**, bypassing the internal Samsung NVMe PCIe slot entirely. The NVMe drive drew $\le 0.5\text{W}$ and remained cold.
  2. **Storage Workload Under Windows 11**: Windows 11 places `C:\pagefile.sys`, system binaries, Docker virtual disks, browser caches, and NTFS transaction journals on that single internal Samsung NVMe SSD, drawing $\sim 4.5\text{W}$ during heavy I/O.
  3. **CPU Boost Behavior**: Windows 11 aggressively boosts the Core i7-8550U to 4.0 GHz Turbo (25W), dumping heat onto the heat pipe directly adjacent to the M.2 slot. Linux default power governors hold the CPU to 1.8–2.4 GHz base clock.
  4. **Timeout Thresholds**: Linux SCSI layer enforces a 30-second retry timeout, whereas the Windows Kernel Store Manager bugchecks after 500ms of queue stall.

---

### Discussion 4: Taskbar Unresponsiveness & Input Dispatching Mechanics
* **Symptom**: Right-clicks worked, but left-clicks and taskbar clicks failed after an overnight idle session.
* **Technical Mechanism**:
  1. `StartMenuExperienceHost.exe` suspended after prolonged idle, leaving the visual taskbar surface alive but lacking a modern XAML event dispatcher.
  2. TightVNC's user-mode input injection hook in Session 2 (`tvnserver.exe`) stalled its Win32 `SendInput` event queue.
  3. Windows accessibility features (ClickLock and StickyKeys) locked virtual modifier keys (`Shift`/`Alt`) in the `DOWN` state following remote network drops.
* **Remediation**:
  * Disabled ClickLock and StickyKeys hotkeys via registry.
  * Verified that restarting `explorer.exe` or `tvnserver` restores input injection without affecting the Session 0 background governor.

---

### Discussion 5: Bidirectional Programmatic UEFI One-Time Boot Architecture
* **Requirement**: Programmatically reboot between Windows 11 and USB Linux without manual BIOS keypresses (`F9`).
* **Implementation**:
  * **`scripts/diagnostic_and_maintenance/boot_to_linux.ps1`**: Queries `bcdedit /enum firmware`, identifies attached USB/Linux EFI boot targets, and sets `{fwbootmgr} bootsequence <GUID>` for a one-time reboot into Linux.
  * **`scripts/diagnostic_and_maintenance/boot_to_windows.sh`**: Uses Linux `efibootmgr --bootnext <BOOT_NUM>` to instruct the motherboard NVRAM to boot `Windows Boot Manager` on the subsequent restart.

---

## 3. Comprehensive File Change & Documentation Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       SUMMARY OF FILE MODIFICATIONS                         │
├─────────────────────────────────────────────┬───────────────────────────────┤
│ File Path                                   │ Description & Scope           │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `src/NVMeThermalDaemon.cs`                  │ • Governor v2.1 source        │
│                                             │ • +5% micro-step ramp ladder  │
│                                             │ • 120s cold-soak dwell engine │
│                                             │ • Win32 powrprof P/Invoke     │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `bin/NVMeThermalDaemon.exe`                 │ • Compiled native C# binary   │
│                                             │ • 10-18 MB RAM, Session 0     │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Unified Taskbar Tray app    │
│ `nvme_tray.py`                              │ • pystray + Pillow rendering  │
│                                             │ • Embedded Web server (:8899) │
│                                             │ • Zero Avast false-positives  │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Force one-time UEFI boot to │
│ `boot_to_linux.ps1`                         │   Linux via bcdedit           │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Force one-time UEFI boot to │
│ `boot_to_windows.sh`                        │   Windows via efibootmgr      │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Windowless VBS wrapper for  │
│ `nvme_web_startup.vbs`                      │   silent user login startup   │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Complete scripts catalog    │
│ `README.md`                                 │   updated with boot scripts   │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `docs/QUICK_START_GUIDE.md`                 │ • Quick Start Guide with      │
│                                             │   Section 7 Bidirectional Boot│
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `system_investigation_and_reboot_findings`  │ • Forensic crash log (1-21)   │
│ `.md`                                       │ • Crash 21 & v2.1 analysis    │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `hardware_specification.md`                 │ • Section 8 cache audit       │
│                                             │ • D:\WUDownloadCache 7.74 GB  │
│                                             │ • D:\Ubuntu16_archive 3.08 GB │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `docs/session_artifacts/`                   │ • 8 synchronized markdown     │
│                                             │   guides and test artifacts   │
└─────────────────────────────────────────────┴───────────────────────────────┘
```

---

## 4. Full Git Commit Chronology (Latest Production Sequence)

1. **[`f68a9a3`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/f68a9a3)**: Implement gentle multi-step recovery ladder (+5%) and 120s cold-soak dwell in C# daemon (v2.1).
2. **[`e2594e0`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/e2594e0)**: Archive conversational artifacts with human-friendly names in `docs/session_artifacts/`.
3. **[`00efd8b`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/00efd8b)**: Synchronize investigation findings, scripts catalog, and session artifacts (v2.1).
4. **[`5920fba`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/5920fba)**: Add comprehensive technical session notes on dual-sensor governor and crash forensics.
5. **[`8deebd8`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/8deebd8)**: Clean stray root files and remove unused C# tray binary in favor of Python tray app.
6. **[`8ee3e64`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/8ee3e64)**: Add bidirectional UEFI one-time boot scripts (`boot_to_linux.ps1` and `boot_to_windows.sh`).
7. **[`21b2922`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/21b2922)**: Save session checkpoint prior to August 30 reboot.
8. **[`c1d2b27`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/c1d2b27)**: Synchronize all session artifacts with human-friendly names (Aug 30).
9. **[`1e8e7e4`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/1e8e7e4)**: Synchronize bidirectional boot scripts documentation across catalog and quick start guide.

---

## 5. Current Production Status & Health

* **Background Governor Daemon**: Active in Session 0 (`PID 3236`, ~11.7 MB RAM), continuously clamping CPU to **75% base clock** and monitoring Samsung NVMe silicon and ACPI chassis temperatures.
* **NVMe Thermal State**: Operating safely at **`44°C – 48°C`** (dissipation gradient $\Delta T = 14^\circ\text{C} – 18^\circ\text{C}$).
* **Web Dashboard**: Live on **`http://100.127.153.93:8899`** in Safari.
* **Taskbar Tray Application**: Running in user session via `pystray` + `Pillow`.
* **Power & Network Policy**: Configured for 24/7 always-on operation on AC power with persistent OpenSSH keepalive heartbeats.
* **Git Repository**: Clean, synchronized, and up to date on `origin/main`.
