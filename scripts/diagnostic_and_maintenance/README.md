# Diagnostic, Forensic & Maintenance Scripts

This directory contains PowerShell and batch diagnostic scripts generated during the Windows 11 unexpected reboot investigation and system maintenance sessions on **AP-HP-G5 (HP ZBook 15u G5)**.

## Script Catalog

### Real-Time Protection & Hardware Safeguards
| Script | Description |
| :--- | :--- |
| [`nvme_thermal_watchdog.ps1`](nvme_thermal_watchdog.ps1) | **5% Adaptive Micro-Probe NVMe Thermal Governor**: Dynamically probes safe CPU power increments (+5%) with 30s stability gating, instant rollback on thermal rise, 60s probe penalty memory, and optional `-Aggressive` background I/O throttle. |

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
| [`verify_system_memory_and_services.ps1`](verify_system_memory_and_services.ps1) | Audits top memory consumers, background services, NVMe SRB error rates, and drive free space. |
| [`setup_powershell_ssh_profile.ps1`](setup_powershell_ssh_profile.ps1) | Creates user profile loaders to append PATH variables for remote SSH PowerShell sessions. |
| [`agy_wrapper.cmd`](agy_wrapper.cmd) | Command wrapper to enable system-wide execution of `agy` across all users in `cmd.exe`. |

### Storage Reclamation & Directory Migrations
| Script | Description |
| :--- | :--- |
| [`audit_large_directories_c_drive.ps1`](audit_large_directories_c_drive.ps1) | Scans `C:\` for top storage consumers across user profiles, caches, and appdata. |
| [`migrate_vscode_and_docker_to_d.ps1`](migrate_vscode_and_docker_to_d.ps1) | Cleans temp files and migrates `.vscode` and `Docker` AppData to `D:` with NTFS junctions. |
| [`migrate_syncthing_to_d.ps1`](migrate_syncthing_to_d.ps1) | Moves `C:\Sync` (Syncthing) to `D:\sync` and creates an NTFS junction. |
| [`migrate_google_drive_to_g.ps1`](migrate_google_drive_to_g.ps1) | Moves Google Drive cache from `C:` to SD Card (`G:`) and creates an NTFS junction. |
| [`archive_legacy_ubuntu16_rootfs.ps1`](archive_legacy_ubuntu16_rootfs.ps1) | Compresses `D:\Ubuntu16` (8.78 GB) into a `.tar.gz` archive, excluding dead WSL socket reparse points. |
