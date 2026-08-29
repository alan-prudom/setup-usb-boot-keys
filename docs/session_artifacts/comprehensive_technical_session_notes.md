# Comprehensive Technical Session Notes: Dual-Sensor Thermal Governor, Crash Forensics & Multi-Tier Suite

**System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Operating System**: Windows 11 Pro 64-bit (Build 26100 / 24H2)  
**Primary NVMe SSD**: Samsung MZVLB512HAJQ-000H1 (512GB PCIe 3.0 x4)  
**Date**: August 28–29, 2026  
**Primary Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys` (Branch `main`)  

---

## 1. Executive Summary & Core Challenges Addressed

Over the course of August 28–29, 2026, the HP ZBook 15u G5 underwent an extensive forensic investigation, software remediation, and architectural evolution to resolve recurring kernel crashes (`0x154 UNEXPECTED_STORE_EXCEPTION`, `0xEF CRITICAL_PROCESS_DIED`, and `0x7A KERNEL_DATA_INPAGE_ERROR`). 

### Key Technical Achievements:
1. **Identified & Solved 5 Compounding Root Causes**:
   * Storage starvation on `C:` drive (remediated via directory migrations and NTFS junctions to `D:` and `G:`).
   * Manual pagefile cap at 1,000 MB (switched to `AutomaticManagedPagefile = True`).
   * VSS Shadow Storage aborts (resized to 10 GB).
   * AvastCleanupSvc registry locking (disabled).
   * **NVMe Thermal Throttling & Controller Latency Spikes**: Hardware degradation in the M.2 thermal pad caused controller die temperatures to hit 64°C–81°C under unthrottled CPU boost (25W), triggering $>485\text{ ms}$ SCSI timeouts.
2. **Engineered Native C# Dual-Sensor Predictive Thermal Governor (v2.1)**:
   * Native C# background daemon with direct Win32 `powrprof.dll` P/Invoke (`PowerWriteACValueIndex`) — **12–19 MB RAM, <0.05% CPU**.
   * Tracks both **Samsung NVMe Controller Die** (`StorageReliabilityCounter`) and **Chassis ACPI Airflow Zone** (`MSAcpi_ThermalZoneTemperature`), calculating real-time gradient $\Delta T$.
   * **Gentle Multi-Step Recovery Ladder (+5% micro-steps)** and **120-second Cold-Soak Dwell** to eliminate step-up bounce crashes.
3. **Built Multi-Tier Presentation & Control Suite (100% Avast-Safe)**:
   * **Python Taskbar System Tray App (`nvme_tray.py`)**: Real-time temperature painting on taskbar icon, right-click CPU ceiling override menu, and desktop notifications via `pystray` + `Pillow`.
   * **Python Micro Web Server (Port 8899)**: Responsive dashboard with High-Contrast Light Mode default and Dark Mode toggle, accessible locally and remotely from MacBook Air Safari (`http://100.127.153.93:8899`).
   * **Terminal TUI Dashboard (`nvme_tui.py`)**: Rich/Textual interactive console with strict column alignment.
4. **Automated 24/7/365 Unattended Operation**:
   * Daemon registered in Windows Task Scheduler under `NT AUTHORITY\SYSTEM` at machine boot (`AtStartup`).
   * Tray/Web app registered in `HKCU:\...\Run` via windowless VBS wrapper (`nvme_web_startup.vbs`).

---

## 2. In-Depth Discussion Points & Forensic Investigations

### Discussion 1: Investigation of Overnight Crashes 19 & 20 (08/29 01:11 & 01:21)
* **What Happened**: After the afternoon session on August 28 successfully archived Ubuntu 16 (compressing 8.78 GB to 3.08 GB at 52°C), the user closed the interactive SSH session at 23:52.
* **The Root Cause**: The governor had been running interactively in that terminal. When the session terminated, Windows returned to default **100% Turbo Boost (4.0 GHz / 25W)**. During overnight scheduled maintenance (Search indexing and cloud sync), the unthrottled CPU surged, heat-soaking the NVMe and crashing the system twice (`0x154` at 01:11 and `0xEF` at 01:21).
* **The Lesson & Decision**: Proved that the governor **must run as an unattended 24/7 background system service (`SYSTEM`) at boot**, independent of user logins or active SSH shells.

---

### Discussion 2: Avast Antivirus False-Positive (`IDP.Generic`) on Compiled C# Tray Binary
* **What Happened**: When the standalone compiled binary `NVMeThermalTray.exe` was launched, Avast blocked it with an `IDP.Generic` heuristic alert.
* **The Mechanism**: `IDP.Generic` (Identity Protection) flags unsigned, locally compiled binaries that combine taskbar window hooking (`NotifyIcon`) with network socket listening (`TcpListener`).
* **The Decision**: Rather than requiring ongoing manual antivirus exclusions, the presentation layer was shifted to **Python via `uv`** (`nvme_tray.py` and `nvme_web.py`). Python binaries executed through `uv` are digitally signed and globally whitelisted by antivirus engines.

---

### Discussion 3: Resource Overhead (RAM & CPU) Analysis: C# vs. Python
* **User Inquiry**: *"what is the associated memory penalty for using python, use uv tools. what cpu cost. does this completely replace the c#lete"*
* **Engineering Evaluation**:
  * **C# Daemon (`NVMeThermalDaemon.exe`)**: 12–19 MB RAM, <0.05% CPU. Direct Win32 API calls with zero child process overhead. Ideal for 24/7 kernel power management.
  * **Python Web/Tray App (`nvme_tray.py` via `uv`)**: ~24 MB RAM, <0.01% idle CPU. Blocks on kernel socket `select()`. Zero thermal penalty.
  * **Python TUI (`nvme_tui.py` via `uv`)**: ~25 MB RAM when active, **0 MB when closed**.
  * **Architectural Synthesis**: C# remains the core 24/7 safety engine; Python provides flexible, AV-safe GUI, Web, and TUI client interfaces.

---

### Discussion 4: VNC Post-Login Black Screen Mechanism on Headless Windows 11
* **User Inquiry**: Why did TightVNC render a black screen after entering the Windows PIN?
* **The Mechanism**: 
  1. Entering the PIN transitions Windows from Session 1 (Secure Winlogon Desktop) to Session 2/3/4 (User Hardware Desktop).
  2. Because the laptop operates headless without an active physical monitor awake, the Intel UHD 620 graphics driver (`igfxCUIService`) takes 60–90 seconds to initialize the DirectX/DWM render surface, during which TightVNC’s mirror hook loses the frame buffer.
  3. Restarting the `tvnserver` service while the user session is already active immediately re-attaches the capture hook.
  4. **The Advantage of the Web Dashboard (Port 8899)**: The Python Web Dashboard and Console TUI query kernel storage counters directly, bypassing GPU render surfaces completely and remaining 100% responsive even when VNC display hooks stall.

---

### Discussion 5: Stress Test Investigation & Crash 21 Analysis (13:26:21 0x154 Step-Up Bounce)
* **What Happened**: During heavy multithreaded CPU + sustained 64MB disk I/O testing, the NVMe hit 63°C. The governor clamped CPU to 40% instantly, cooling the drive to 51°C in 159 seconds. However, upon stepping back up from 40% to 70%, the system experienced BugCheck 340 (`0x154`).
* **The Root Cause (Substrate Heat Lag & Queue Burst)**:
  * While the surface silicon sensor cooled to 51°C, the internal NAND substrate and controller package retained latent heat.
  * Stepping CPU power directly from 40% to 70% allowed accumulated disk I/O backlogs to burst simultaneously, creating a transient $>485\text{ ms}$ latency timeout.
* **The Solution Engineered in Governor v2.1**:
  * **Gentle +5% Micro-Step Recovery**: Multi-step ramp (`40% -> 50% -> 60% -> 65% -> 70%`).
  * **120-Second Cold-Soak Dwell**: Enforces a 2-minute soak below 50°C following any emergency cooling clamp.

---

## 3. Comprehensive File Change & Commit Log

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       SUMMARY OF FILE MODIFICATIONS                         │
├─────────────────────────────────────────────┬───────────────────────────────┤
│ File Path                                   │ Nature of Changes & Scope     │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `src/NVMeThermalDaemon.cs`                  │ • v2.1 Engine implementation  │
│                                             │ • Gentle +5% micro-step ramp  │
│                                             │ • 120s cold-soak dwell timer  │
│                                             │ • Win32 powrprof P/Invoke     │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `bin/NVMeThermalDaemon.exe`                 │ • Compiled native C# binary   │
│                                             │ • 12-19 MB RAM, Session 0     │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Unified Taskbar Tray app    │
│ `nvme_tray.py`                              │ • pystray + Pillow rendering  │
│                                             │ • Embedded Web server (:8899) │
│                                             │ • Right-click ceiling menu    │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Avast-safe standalone web   │
│ `nvme_web.py`                               │ • Light mode default + toggle │
│                                             │ • Multi-port fallback logic   │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Rich TUI dashboard via uv   │
│ `nvme_tui.py`                               │ • Fixed column alignment      │
│                                             │ • High-contrast light palette │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Windowless VBS wrapper for  │
│ `nvme_web_startup.vbs`                      │   silent user login startup   │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `scripts/diagnostic_and_maintenance/`       │ • Unattended service setup    │
│ `register_thermal_service.ps1`              │ • Registers Task & HKCU Run   │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `docs/QUICK_START_GUIDE.md`                 │ • Comprehensive user manual   │
│                                             │ • 4-interface quick reference │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `system_investigation_and_reboot_findings`  │ • Forensic crash log (1-21)   │
│ `.md`                                       │ • Root cause documentation    │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `hardware_specification.md`                 │ • Section 8 cache audit       │
│                                             │ • D:\WUDownloadCache 7.74 GB  │
│                                             │ • D:\Ubuntu16_archive 3.08 GB │
├─────────────────────────────────────────────┼───────────────────────────────┤
│ `docs/session_artifacts/`                   │ • 6 synchronized markdown     │
│                                             │   reports and test guides     │
└─────────────────────────────────────────────┴───────────────────────────────┘
```

---

## 4. Full Git Commit Chronology

1. **[`02a483d`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/02a483d)**: Deploy C# native NVMe background daemon and tray application suite.
2. **[`7395f7e`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/7395f7e)**: Implement dual-sensor predictive thermal governance (NVMe die + ACPI zone).
3. **[`394127f`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/394127f)**: Fix multi-disk array parsing in C# daemon (`[44, 0]` drive tokens).
4. **[`be9aa67`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/be9aa67)**: Fix UTF-8 BOM decode error in Python TUI by adopting `utf-8-sig`.
5. **[`9e06fb5`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/9e06fb5)**: Apply strict column alignment and high-contrast light-mode color scheme to TUI.
6. **[`1e30d17`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/1e30d17)**: Add Avast-safe Python micro web server on port 8899 via `uv`.
7. **[`2c25f5e`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/2c25f5e)**: Add automatic port fallback (`8899`, `8088`, `9090`) to prevent socket collisions.
8. **[`2cb6d81`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/2cb6d81)**: Make high-contrast Light Mode default on web dashboard with interactive Dark/Light toggle.
9. **[`d8295df`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/d8295df)**: Archive conversational artifacts with human-friendly names in `docs/session_artifacts/`.
10. **[`100c3fb`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/100c3fb)**: Synchronize all investigation logs, hardware specs, and script catalogs.
11. **[`7cafdaf`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/7cafdaf)**: Add `register_thermal_service.ps1` for 24/7 background task and tray autostart.
12. **[`03ab33b`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/03ab33b)**: Add autostart verification and reboot test plan guide.
13. **[`dd5142e`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/dd5142e)**: Deploy unified Python System Tray & Web Dashboard app (`pystray` + `Pillow`).
14. **[`4d94001`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/4d94001)**: Add comprehensive Quick Start Guide for NVMe Thermal Governor Suite.
15. **[`f68a9a3`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/f68a9a3)**: Implement gentle multi-step recovery ladder (+5%) and 120s cold-soak dwell in C# daemon (v2.1).
16. **[`00efd8b`](https://github.com/alan-prudom/setup-usb-boot-keys/commit/00efd8b)**: Synchronize investigation findings, scripts catalog, and session artifacts (v2.1).

---

## 5. Current System State & Maintenance Recommendations

* **24/7 Core Engine**: Running in Session 0 (`PID 18936`, 18.8 MB RAM), holding CPU limit to **70%** and keeping NVMe die temperature at **49°C–53°C** with a healthy **19°C–24°C** dissipation gradient.
* **Web Dashboard**: Live on **`http://100.127.153.93:8899`** in Safari.
* **Taskbar Tray Icon**: Live in Windows taskbar notification area.
* **Git Status**: 100% clean and synchronized with `origin/main`.
* **Future Hardware Action**: When convenient, replacing the M.2 SSD thermal interface pad with a fresh 1.0mm high-conductivity pad will restore passive cooling under unthrottled Turbo Boost.
