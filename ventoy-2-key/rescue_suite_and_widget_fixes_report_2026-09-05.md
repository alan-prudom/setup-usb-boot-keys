# Engineering Report: Live Rescue Widget Fixes & Unified 5-Function Rescue Suite

**Date of Record:** September 5, 2026  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Target Device:** 128 GB SanDisk Multi-Boot USB (`/dev/sdb`, Ventoy 2)  
**Workspace:** [`devices/setup-usb-boot-keys/ventoy-2-key/`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/)  

---

## 1. Executive Summary

Following the activation of the Four-Tier Persistence overlay on Rescuezilla 2.6.1 Live, hardware testing revealed minor runtime defects and prompted an architectural extension:
1. **Desktop Widget Error:** Clicking desktop shortcuts triggered an error dialog: *"Desktop entry contains no valid Exec line"*.
2. **POSIX Shell Syntax Error:** Executing backup runners via `sh <script>` caused bash regex checks (`[[ "$choice" =~ ^[0-9]+$ ]]`) to fail with syntax errors under Dash.
3. **Rescue Suite Extension:** Consolidated all 5 core Rescuezilla operations (Backup, Restore, Clone, Verify, Image Explorer) alongside automated network storage mounting into a single interactive terminal suite.

---

## 2. Root Cause Analysis & Resolutions

### 2.1 The "Desktop entry contains no valid Exec line" Dialog
* **Finding:** A legacy prototype file, `mount-ntfs.desktop`, was present in the user's desktop directory. Because it was missing an executable binary path matching current mount conventions, PCManFM displayed the modal error.
* **Resolution:** Purged `mount-ntfs.desktop` and `mount-ntfs.service` across the repository, the active overlay, and updated `deploy_four_tier_persistence.sh` to remove legacy artifacts automatically.

### 2.2 Shell Portability (`/bin/sh` -> Dash Compatibility)
* **Finding:** When running scripts via `sh /media/ubuntu/SHARED_FAT/scripts/run_rescuezilla_backup_cli.sh`, Ubuntu maps `/bin/sh` to Dash. The bash-specific keyword `[[` failed on line 58 with `58: [[: not found`.
* **Resolution:** Refactored integer and option validation in `run_rescuezilla_backup_cli.sh`, `sda_rescue_backup.sh`, and `sda5_rescue_backup.sh` to use standard POSIX `case "$choice" in *[!0-9]*|"") ... ;; *) ... ;; esac`. Scripts now execute cleanly under both Bash and Dash.

---

## 3. Unified Rescue Suite Implementation (`rescue_suite_launcher.sh`)

To provide one-click access to the 5 core functions identified in live testing, [`rescue_suite_launcher.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/rescue_suite_launcher.sh) was developed:

```
+------------------------------------------------------------------------------------+
|                🛡️ RESCUEZILLA & CLONEZILLA UNIFIED RESCUE SUITE                    |
+------------------------------------------------------------------------------------+
|  [1] 📤 Backup Image           -> Automated CLI / Clonezilla / Rescuezilla         |
|  [2] 📥 Restore Image          -> Clonezilla ocs-sr restore & Rescuezilla restore  |
|  [3] 🔀 Clone Device-to-Device -> Direct disk-to-disk clone (ocs-onthefly)          |
|  [4] 🛡️ Verify Backup Image    -> Audit image files and checksums (ocs-chkimg)     |
|  [5] 🔍 Image Explorer         -> Mount & extract files from images (nbd / mount)  |
|  [6] 🌐 Connect Network        -> Mount 192.168.1.34:/media/alan/home40 via SSHFS  |
|  [7] 💾 Mount Local Storage    -> Mount SHARED FAT and Internal HDD (ro)           |
|  [8] 📋 Post-Backup Wizard     -> Inspect manifests, partclone logs & SMART        |
|  [9] 🖥️ Launch Rescuezilla GUI -> Opens standard Rescuezilla graphical window     |
+------------------------------------------------------------------------------------+
```

### Key Capabilities:
1. **Pre-Flight Network Mounting:** Automatically establishes SSHFS connection to `192.168.1.34:/media/alan/home40/Clonezilla` and bind-mounts it to `/home/partimag` before running any image operation.
2. **Desktop Integration:** Installed `Rescue_Suite.desktop` and `Mount_Network_home40.desktop` onto the persistent desktop with `--hold` window retention.

---

## 4. Verification & Audit Results

All 9 test suites in `verify_ventoy2.sh` passed cleanly:
- Block device, partition geometry, UUID, MBR boot code verified.
- Persistence container volume label verified as `writable`.
- Rescue Suite launcher and backup scripts verified on `/ntfs/scripts/`.
- Full Four-Tier architecture and desktop launchers verified in `/upper/` of `rescuezilla-persistence.dat`.
