# HP ZBook 15u G5 Documentation & Recovery Artifacts

This folder contains documentation, disaster recovery reports, and maintenance records specifically for the **HP ZBook 15u G5** (AP-HP-G5 / lan-USB-g5).

---

## Document Index

* [DETAILED_RECOVERY_REPORT.md](DETAILED_RECOVERY_REPORT.md) — Detailed statement-by-statement report on recovering deleted WSL \xt4.vhdx\ from a Clonezilla full-disk backup image over remote NAS (\192.168.1.34\ on \/media/alan/home40\) using zero-disk-space sparse NBD architecture.
* [UBUNTU_RECOVERY_COMPLETE.md](UBUNTU_RECOVERY_COMPLETE.md) — Completion audit for WSL 2 Ubuntu restoration, VHDX header verification, filesystem checks, and relocation to \D:\WSL-distros\Ubuntu-24.04\.
* [REBOOT_STATE_CHECKPOINT.md](REBOOT_STATE_CHECKPOINT.md) — System pre-reboot checkpoint documenting WSL distributions, PC disk space metrics, and remote Linux NAS cleanup.
* [disk_space_audit.md](disk_space_audit.md) — Initial disk space audit on HP ZBook 15u G5 (Drive C & D breakdown and cleanup recommendations).
* [DEBIAN_SALVAGE_AND_DISK_RECOVERY.md](DEBIAN_SALVAGE_AND_DISK_RECOVERY.md) — Documentation of C: drive space diagnostic (Evernote cache), NTFS junction inspection rules, D:\Debian WSL1 data mining into GitHub (`legacy-debian-salvage`), and verified 5.61 GB full-system archive on F:.
* [MULTIBOOT_BACKUP_AND_SSH_CONFIG.md](MULTIBOOT_BACKUP_AND_SSH_CONFIG.md) — Documentation of the 28.64 GB multiboot USB raw image max-compression archive to D:\multiboot_image.tar.gz and MSYS2 SSH port 2222 key authentication setup.
* [STORAGE_MIGRATION_AND_SYSTEM_OPTIMIZATION_REPORT.md](STORAGE_MIGRATION_AND_SYSTEM_OPTIMIZATION_REPORT.md) — Comprehensive technical report on Evernote AppData relocation to D:, Google Drive ("My Drive", 4.72 GB) migration to F:, MATLAB multi-version offload to F:, transfer time estimation accuracy analysis (IOPS ceiling vs. bandwidth), drive F: space incident recovery, and VNC remote diagnostics.
* [artifacts/](artifacts/) — Version-controlled archive of all conversational artifacts, checklists, and diagnostic reports saved under human-friendly filenames.

