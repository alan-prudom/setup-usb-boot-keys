# Diagnostic, Forensic & Maintenance Scripts

This directory contains PowerShell and batch diagnostic scripts generated during the Windows 11 unexpected reboot investigation and system maintenance sessions on **AP-HP-G5 (HP ZBook 15u G5)**.

## Script Catalog

### Real-Time Protection & Hardware Safeguards
| Script / Binary | Description |
| :--- | :--- |
| [`../../src/NVMeThermalDaemon.cs`](../../src/NVMeThermalDaemon.cs) | **Dual-Sensor Predictive NVMe Thermal Governor (C# Source v2.1)**: Native C# background daemon with direct Win32 `powrprof.dll` P/Invoke, dual-sensor polling (NVMe die + ACPI zone), `D:\nvme_state.json` atomic stream, gentle multi-step recovery (+5%), 120s cold-soak dwell, and 7-day state-change daily CSV logging. |
| [`../../bin/NVMeThermalDaemon.exe`](../../bin/NVMeThermalDaemon.exe) | **Compiled Native Daemon Binary (v2.1)**: 12–19 MB RAM footprint, <0.05% CPU, runs 24/7 standalone or as a Windows Scheduled Task. |
| [`nvme_tray.py`](nvme_tray.py) | **Unified Python System Tray & Web Dashboard (via `uv`)**: Native Windows taskbar live temperature icon (`pystray` + `Pillow`), right-click CPU ceiling override menu, embedded Web Server on port 8899, and zero Avast false-positives. |
| [`nvme_web.py`](nvme_web.py) | **Python Micro Web Server (Port 8899 via `uv`)**: Serves responsive live HTML dashboard (Light mode default with interactive Dark/Light toggle) and `/api/state` for Safari on macOS. |
| [`nvme_tui.py`](nvme_tui.py) | **Python Terminal TUI Dashboard (via `uv`)**: Interactive Rich/Textual terminal dashboard with strict column alignment, ASCII/Unicode gauges, and live $\Delta T$ gradient. |
| [`nvme_thermal_watchdog.ps1`](nvme_thermal_watchdog.ps1) | **5% Adaptive Micro-Probe NVMe Thermal Governor (PowerShell)**: Standalone PowerShell implementation with `-MaxCpu` override and `-Aggressive` background I/O throttle. |



### Controlled Stress Testing & Thermal Verification
| Script | Description |
| :--- | :--- |
| [`simulate_multithreaded_thermal_stress.ps1`](simulate_multithreaded_thermal_stress.ps1) | High-intensity thermal stress tester spinning up 8 parallel SHA-512 CPU hashing threads + sustained 64MB unbuffered NVMe disk I/O with automatic safety cutoff at target temperature. |

### Crash Forensics & Hardware Diagnostics
| Script | Description |
| :--- | :--- |
| [`forensic_diskspd_crash_analysis.ps1`](forensic_diskspd_crash_analysis.ps1) | Parses Event 41 XML crash logs specifically correlated with DiskSpd 4K queue saturation tests. |
| [`deep_storage_and_smart_diagnostic.ps1`](deep_storage_and_smart_diagnostic.ps1) | Comprehensive storage diagnostic pulling WMI SMART, StorPort, NTFS event logs, and drive counters. |
| [`check_nvme_smart_reliability.ps1`](check_nvme_smart_reliability.ps1) | Checks `Get-StorageReliabilityCounter` (temperature, max latency, wear, error counts) and ATAPort SCSI SRB errors. |
| [`forensic_crash_log_query.ps1`](forensic_crash_log_query.ps1) | Parses Kernel-Power (Event ID 41) XML payload to extract exact BugCheck codes and parameters P1-P4. |
| [`check_latest_bugchecks_and_volsnap.ps1`](check_latest_bugchecks_and_volsnap.ps1) | Checks recent bugcheck events and inspects Volsnap shadow copy storage abort errors (Event 36). |
| [`check_application_hangs_and_crashes.ps1`](check_application_hangs_and_crashes.ps1) | Correlates system crashes with Application log events (e.g. Firefox hangs, Avast registry locks). |

### System Configuration & Service Management
| Script | Description |
| :--- | :--- |
| [`set_automatic_system_pagefile.ps1`](set_automatic_system_pagefile.ps1) | Configures Windows Virtual Memory to `AutomaticManagedPagefile = True`, removing manual pagefile caps. |
| [`verify_volsnap_and_drive_space.ps1`](verify_volsnap_and_drive_space.ps1) | Verifies Volume Shadow Copy storage status and drive free space after resizing. |
| [`find_and_inspect_avast_services.ps1`](find_and_inspect_avast_services.ps1) | Inspects running Avast / TuneUp services and maps process IDs to service names. |
### Bidirectional UEFI One-Time Boot Scripts
| Script | Description |
| :--- | :--- |
| [`boot_to_linux.ps1`](boot_to_linux.ps1) | **Force One-Time UEFI Boot to Linux (Windows PowerShell)**: Queries UEFI NVRAM via `bcdedit /enum firmware`, programs `{fwbootmgr} bootsequence` to attached USB/Linux EFI partitions, or launches Windows Advanced Startup menu (`shutdown /r /o`). |
| [`boot_to_windows.sh`](boot_to_windows.sh) | **Force One-Time UEFI Boot to Windows 11 (Linux Bash)**: Uses Linux `efibootmgr --bootnext` to dynamically locate `Windows Boot Manager` and set the one-time reboot sequence back to Windows 11. |

### Storage Reclamation & Directory Migrations
| Script | Description |
| :--- | :--- |
| [`audit_large_directories_c_drive.ps1`](audit_large_directories_c_drive.ps1) | Scans `C:\` for top storage consumers across user profiles, caches, and appdata. |
| [`migrate_vscode_and_docker_to_d.ps1`](migrate_vscode_and_docker_to_d.ps1) | Cleans temp files and migrates `.vscode` and `Docker` AppData to `D:` with NTFS junctions. |
| [`migrate_syncthing_to_d.ps1`](migrate_syncthing_to_d.ps1) | Moves `C:\Sync` (Syncthing) to `D:\sync` and creates an NTFS junction. |
| [`migrate_google_drive_to_g.ps1`](migrate_google_drive_to_g.ps1) | Moves Google Drive cache from `C:` to SD Card (`G:`) and creates an NTFS junction. |
| [`archive_legacy_ubuntu16_rootfs.ps1`](archive_legacy_ubuntu16_rootfs.ps1) | Compresses `D:\Ubuntu16` (8.78 GB) into a `.tar.gz` archive, excluding dead WSL socket reparse points. |
