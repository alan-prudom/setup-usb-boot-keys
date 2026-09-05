# Comprehensive Technical Session Notes: Live Persistence Debugging, Dash Compatibility, Rescue Suite Launcher & HITL Commit Register

**Author / Session Lead:** Alan P & Assistant  
**Date of Record:** September 5, 2026  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Storage Configuration:**  
* **Target Drive 1 (Internal):** 1 TB SSD/HDD (`/dev/sda`)  
  - `/dev/sda1` (600 MB, NTFS): System Reserved  
  - `/dev/sda2` (142 GB, NTFS): Windows System OS  
  - `/dev/sda3` (111 GB, NTFS): Data partition  
  - `/dev/sda5` (608 GB, ext4, UUID `26448526-203a-40ab-ae59-980a7d107903`): Internal Linux OS (Ubuntu)  
* **Target Drive 2 (Booted USB):** 128 GB SanDisk Multi-Boot USB (`/dev/sdb`, Ventoy 2)  
  - `/dev/sdb1` (20 GB exFAT, `Ventoy`, UUID `4E21-0000`): ISO storage & persistence images  
  - `/dev/sdb2` (32 MB FAT16, `VTOYEFI`, UUID `223C-F3F8`): Ventoy EFI core  
  - `/dev/sdb3` (19 GB ext4, UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9`): Installed Ubuntu 22.04 LTS Rootfs (`/home/alan`)  
  - `/dev/sdb4` (82 GB FAT32, `SHARED FAT`, UUID `C9D1-3C83`): Shared data, archives & scripts  
* **Target Drive 3 (Remote Network Storage):** HP EliteBook (`alan@192.168.1.34:/media/alan/home40/Clonezilla`)  
**Active Sub-Repository:** [`/home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/)  
**Meta-Repository:** [`/home/alan/ap-devices-and-pcs/`](file:///home/alan/ap-devices-and-pcs/)  

---

## 1. Executive Summary

This session finalized the stabilization of the multi-boot Rescuezilla 2.6.1 Live environment with persistence on the 128 GB Ventoy 2 USB drive (`/dev/sdb`), resolved runtime shell and desktop environment defects, expanded functionality to cover the five core Rescuezilla operations with automated network storage, and completed a Human-in-the-Loop (HITL) version control audit of all diagnostic artifacts.

Key milestones achieved:
1. **Desktop Widget Defect Eradication:** Identified and eliminated the cause of the *"Desktop entry contains no valid Exec line"* dialog triggered by obsolete desktop prototypes (`mount-ntfs.desktop`).
2. **POSIX Shell Portability Refactoring:** Fixed bashism syntax errors (`line 58: [[: not found`) occurring when users or launchers invoke scripts via Dash (`/bin/sh`).
3. **Unified 5-Function Rescue Suite (`rescue_suite_launcher.sh`):** Created and deployed a unified terminal launcher covering Backup, Restore, Clone, Verify, Image Explorer, SSHFS network mounting, and post-backup validation.
4. **Network Storage Automation:** Integrated passwordless SSHFS mounting to remote storage (`192.168.1.34:/media/alan/home40/Clonezilla`) with automated bind-mounting to `/home/partimag`.
5. **Four-Tier Persistence Overlay Deployment:** Deployed launchers, binaries, and systemd units directly into `/upper/` within `rescuezilla-persistence.dat` to satisfy Casper OverlayFS requirements.
6. **HITL Conversational Artifact Review & Commit:** Evaluated all conversational screenshots and diagnostic reports with interactive human prompts, cataloging approved artifacts into version control and pushing cleanly to GitHub `origin/main`.

---

## 2. Forensic Investigation & Defect Resolution

### 2.1 Investigation of User-Reported Defects
Following an earlier test boot into Rescuezilla Live with persistence enabled, the user reported:
> *"that was better. Persistance available. Some scripts and screen widgets dont work properly. see screenshots on USB, investigate all logs"*
> *"I added the select options screen shot as a reminder that you need to add scripts that setup network access and launch these additional 5 functions"*

Inspection of screenshots, bash history, and system logs identified three specific issues:

### 2.2 Defect 1: Desktop Entry Modal Error ("Desktop entry contains no valid Exec line")
* **Symptom:** Clicking desktop shortcut widgets or logging into the desktop spawned a modal error message from PCManFM / Openbox: *"Desktop entry contains no valid Exec line"*.
* **Root Cause Analysis:** During initial persistence prototyping, a file named `mount-ntfs.desktop` was created in `persistence_startup/` with a broken or obsolete command path. When copied to `/upper/home/ubuntu/Desktop/mount-ntfs.desktop`, the desktop environment attempted to parse it and rejected the missing executable.
* **Remediation:**
  1. Deleted `ventoy-2-key/persistence_startup/mount-ntfs.desktop` and associated `mount-ntfs.service`.
  2. Updated [`deploy_four_tier_persistence.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/deploy_four_tier_persistence.sh) to explicitly delete any stale `mount-ntfs.desktop` or `mount-ntfs.service` from `/upper/` and `/` of `rescuezilla-persistence.dat`.
  3. Re-generated clean desktop entries with valid absolute paths and `--hold` retention flags.

### 2.3 Defect 2: Shell Syntax Error (`line 58: [[: not found`)
* **Symptom:** Running scripts from the terminal or via desktop shortcuts threw:
  ```text
  /media/ubuntu/SHARED_FAT/scripts/run_rescuezilla_backup_cli.sh: 58: [[: not found
  ```
* **Root Cause Analysis:** On Debian and Ubuntu systems, `/bin/sh` symlinks to Dash. When scripts are launched with `sh script.sh` instead of `bash script.sh`, or invoked through desktop wrappers that delegate to `/bin/sh`, Bash syntax extensions such as `[[ "$choice" =~ ^[0-9]+$ ]]` cause a fatal syntax parsing failure.
* **Remediation:** Refactored integer and option validation across all backup scripts to strict POSIX-compliant syntax:
  ```sh
  # Previous Bash-only syntax (failed under Dash):
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le 7 ]; then

  # Refactored POSIX-compliant syntax (runs on Bash, Dash, BusyBox ash, etc.):
  case "$choice" in
      *[!0-9]*|"")
          echo "Invalid input: numbers only"
          ;;
      *)
          if [ "$choice" -ge 1 ] && [ "$choice" -le 7 ]; then
              # valid option
          fi
          ;;
  esac
  ```
  Modified files:
  - [`run_rescuezilla_backup_cli.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/run_rescuezilla_backup_cli.sh)
  - [`sda_rescue_backup.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/sda_rescue_backup.sh)
  - [`sda5_rescue_backup.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/sda5_rescue_backup.sh)

---

## 3. Architecture & Implementation of the Unified Rescue Suite

### 3.1 Motivation & Feature Scope
The user provided a screenshot of the official Rescuezilla 2.6.1 function selection interface, highlighting the necessity to automate access to all five core functions:
1. **Backup:** Save partitions or entire drives into Clonezilla-compatible images.
2. **Restore:** Write Clonezilla or Rescuezilla images back to target partitions or drives.
3. **Clone:** Perform direct drive-to-drive cloning (`ocs-onthefly`) without creating intermediate images.
4. **Verify:** Check image integrity and SHA/MD5 block checksums (`ocs-chkimg`).
5. **Image Explorer:** Mount existing image files via network block devices (`nbd`) or loop mounts to browse and extract individual files.

In addition, the suite required immediate, automated integration with the central network repository:
`alan@192.168.1.34:/media/alan/home40/Clonezilla`.

### 3.2 Launcher Design: [`rescue_suite_launcher.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/rescue_suite_launcher.sh)
A modular interactive launcher was built, featuring:
* **Interactive Explanations (Instructional Rule):** Every interactive prompt explains why information is being requested before taking input.
* **Automated SSHFS Network Mount:** Connects to `192.168.1.34`, verifies SSH key availability (`/scripts/id_rsa`, `/root/.ssh/id_rsa`, `/home/ubuntu/.ssh/id_rsa`), mounts `/media/alan/home40/Clonezilla` to `/mnt/home40_clonezilla`, and bind-mounts it to Clonezilla's default storage repository `/home/partimag`.
* **Integrated Operations:**
  - **Option 1 (Backup):** Calls `run_rescuezilla_backup_cli.sh` (or fallback Clonezilla wizard / `rescuezilla backup`).
  - **Option 2 (Restore):** Validates `/home/partimag` repository contents and launches `ocs-sr -g auto -e1 auto -e2 -c -r -j2 -p true restoredisk` or targeted partition restore.
  - **Option 3 (Clone Device-to-Device):** Launches `ocs-onthefly` with interactive source and destination drive selectors and safety confirmations.
  - **Option 4 (Verify Backup Image):** Scans `/home/partimag` for image directories and executes `ocs-chkimg -s` to test image consistency.
  - **Option 5 (Image Explorer):** Provides step-by-step CLI image mounting using `qemu-nbd` or Rescuezilla's Python image explorer backend (`rescuezillapy`).
  - **Option 6 (Connect Network):** Standalone network storage mounter.
  - **Option 7 (Mount Local Storage):** Auto-mounts `/dev/sdb4` (`SHARED FAT`) and `/dev/sda5` (read-only).
  - **Option 8 (Post-Backup Wizard):** Runs [`post-backup-wizard.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/post-backup-wizard.sh) to inspect manifests, logs, and SMART data.
  - **Option 9 (Launch Rescuezilla GUI):** Launches the native Rescuezilla Python/GTK graphical interface.

### 3.3 Desktop Entry Manifests
Created and deployed two dedicated desktop shortcuts in `/home/ubuntu/Desktop/`:
1. **`Rescue_Suite.desktop`**:
   ```ini
   [Desktop Entry]
   Version=1.0
   Type=Application
   Name=Rescue Suite (5 Functions)
   Comment=Rescuezilla and Clonezilla Unified 5-Function Rescue Suite
   Exec=x-terminal-emulator -e sudo /usr/local/bin/rescue_suite_launcher.sh
   Icon=utilities-system-monitor
   Terminal=true
   Categories=System;Utility;
   ```
2. **`Mount_Network_home40.desktop`**:
   ```ini
   [Desktop Entry]
   Version=1.0
   Type=Application
   Name=Mount Network Storage (home40)
   Comment=Connect to 192.168.1.34:/media/alan/home40 via SSHFS
   Exec=x-terminal-emulator -e sudo /usr/local/bin/mount_home40_backup.sh
   Icon=network-server
   Terminal=true
   Categories=System;Network;
   ```

---

## 4. Live Persistence Overlay Synchronization (`deploy_four_tier_persistence.sh`)

### 4.1 OverlayFS Architecture Enforcement
* **Mechanics:** The Rescuezilla 2.6.1 Live environment uses Casper OverlayFS (`lowerdir=/rofs,upperdir=/cow/upper,workdir=/cow/work`).
* The physical persistence container (`rescuezilla-persistence.dat`) on `/dev/sdb1` is mounted at `/cow`.
* Any files deployed into the raw root of the container (e.g. `/cow/scripts/`) remain completely hidden from the live session.
* **Deployment Rule:** All files must be placed directly into `$MNT/upper/` (and mirrored to `$MNT/` for fallback inspection).

### 4.2 Tri-Tier Script Distribution Register
All operational scripts are synchronized across three locations:
1. **Persistence Overlay (`/upper/`):** Inside `rescuezilla-persistence.dat` at `/scripts/`, `/usr/local/bin/`, and `/home/ubuntu/Desktop/`.
2. **Shared FAT32 Partition (`/dev/sdb4`):** `/ntfs/scripts/` (mounted at `/media/ubuntu/SHARED_FAT/scripts/` in live session).
3. **Ventoy Partition 1 (`/dev/sdb1`):** `/media/alan/Ventoy1/scripts/`.

### 4.3 Automated Pre-Boot Verification (`verify_ventoy2.sh`)
The verification suite was updated to 9 automated pre-flight checks:
* **Test 1:** USB block device `/dev/sdb` presence and geometry.
* **Test 2:** Ventoy MBR boot code signature (`0x199e46a9`).
* **Test 3:** Partition layout and expected UUID verification.
* **Test 4:** F6 custom GRUB configuration syntax check.
* **Test 5:** `ventoy.json` persistence mapping syntax check.
* **Test 6:** Ubuntu 22.04 rootfs kernel and GRUB files on `/dev/sdb3`.
* **Test 7:** Persistence file volume label check (`writable`).
* **Test 8:** Operational backup scripts presence on `/ntfs/scripts/`.
* **Test 9:** Loop-mount inspection of `rescuezilla-persistence.dat` verifying `/upper/` binaries, desktop entries, and systemd units.
* **Result:** 9 of 9 tests pass cleanly.

---

## 5. Human-in-the-Loop (HITL) Artifact Review & Version Control Register

### 5.1 Review Protocol
In strict compliance with user instructions:
> *"Can you save the conversational 'Artifacts' as files in version control? Can you copy them using a human-friendly name? Let the HITL decide if each artifact is relevant. Present one at a time with a brief summary and a yes/no copy prompt"*

Each artifact was presented individually with an explanation and prompt:

| Artifact Name | Type / Size | Summary | HITL Decision | Repository Destination / Status |
| :--- | :--- | :--- | :--- | :--- |
| `media_1788564738940.png` | PNG (10 KB) | Modal error: *"Desktop entry contains no valid Exec line"* | **No (Skip)** | Not committed (defect resolved) |
| `media_1788564749376.png` | PNG (93 KB) | Dash shell syntax error: *`line 58: [[: not found`* | **No (Skip)** | Not committed (defect resolved) |
| `media_1788564759215.png` | PNG (52 KB) | Rescuezilla 5 Functions Screen (Backup, Restore, Clone, Verify, Image Explorer) | **Yes (Copy & Commit)** | [`ventoy-2-key/docs/screenshots/rescuezilla_5_functions_select_options.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/rescuezilla_5_functions_select_options.png) |
| `screenshot_disks_fat_unmounted.png` | PNG (94 KB) | GNOME Disks screenshot of unmounted FAT partition | **No (Skip)** | Preserved on flash at `/ntfs/` |

### 5.2 Git Commit History for Recent Changes

All commits in [`devices/setup-usb-boot-keys`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys) on branch `main`:

```
190167a (HEAD -> main, origin/main) docs(ventoy-2): add screenshot artifact of Rescuezilla 5 functions screen
4073ed7 docs(ventoy-2): add rescue suite and widget fixes report artifact
408cf2a feat(ventoy-2): add unified Rescue Suite launcher for 5 core functions and network storage
fcfc461 fix(ventoy-2): resolve desktop widget 'no valid Exec line', POSIX regex syntax, and autostart deduplication
e3c3a37 docs(ventoy-2): synchronize TEST_PLAN, persistence_startup README, and troubleshooting docs with OverlayFS and FAT32 specs
cf32b8d docs(ventoy-2): document OverlayFS forensics, script alignment and HITL review in session notes
03eb682 docs(ventoy-2): add persistence investigation and repair report artifact
893ab79 fix(ventoy-2): fix OverlayFS persistence deployment, add Clonezilla & post-mortem scripts
```

All commits have been pushed to GitHub (`origin/main`). The local working tree is clean across all tracked paths.

---

## 6. Comprehensive File Changes Summary

| Relative Path | Role & Changes |
| :--- | :--- |
| [`ventoy-2-key/rescue_suite_launcher.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/rescue_suite_launcher.sh) | **NEW:** Interactive 5-function suite; handles automated SSHFS network mounting, repository linking, POSIX validation, and execution wrappers for Backup, Restore, Clone, Verify, and Explorer. |
| [`ventoy-2-key/persistence_startup/Rescue_Suite.desktop`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/persistence_startup/Rescue_Suite.desktop) | **NEW:** Desktop entry launching `rescue_suite_launcher.sh` in a persistent terminal window. |
| [`ventoy-2-key/persistence_startup/Mount_Network_home40.desktop`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/persistence_startup/Mount_Network_home40.desktop) | **NEW:** Desktop entry for standalone SSHFS network storage connection. |
| [`ventoy-2-key/deploy_four_tier_persistence.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/deploy_four_tier_persistence.sh) | **MODIFIED:** Added automatic purging of legacy `mount-ntfs.*` files; deployed `Rescue_Suite.desktop` and `Mount_Network_home40.desktop`; injected `rescue_suite_launcher.sh` into `/upper/usr/local/bin/` and `/upper/scripts/`. |
| [`ventoy-2-key/run_rescuezilla_backup_cli.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/run_rescuezilla_backup_cli.sh) | **MODIFIED:** Refactored bash `[[ ... =~ ... ]]` to standard POSIX `case` blocks; fixed Dash compatibility. |
| [`ventoy-2-key/sda_rescue_backup.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/sda_rescue_backup.sh) | **MODIFIED:** Refactored regex validation to POSIX syntax. |
| [`ventoy-2-key/sda5_rescue_backup.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/sda5_rescue_backup.sh) | **MODIFIED:** Refactored regex validation to POSIX syntax. |
| [`ventoy-2-key/verify_ventoy2.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/verify_ventoy2.sh) | **MODIFIED:** Added verification assertions for `rescue_suite_launcher.sh`, `Rescue_Suite.desktop`, and `Mount_Network_home40.desktop`. |
| [`ventoy-2-key/persistence_startup/mount-ntfs.desktop`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/persistence_startup/mount-ntfs.desktop) | **DELETED:** Obsolete prototype desktop file that caused PCManFM modal errors. |
| [`ventoy-2-key/persistence_startup/mount-ntfs.service`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/persistence_startup/mount-ntfs.service) | **DELETED:** Obsolete prototype service replaced by `mount-storage-startup.service`. |
| [`ventoy-2-key/rescue_suite_and_widget_fixes_report_2026-09-05.md`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/rescue_suite_and_widget_fixes_report_2026-09-05.md) | **NEW:** Technical engineering report detailing root causes and verification for widget and shell fixes. |
| [`ventoy-2-key/docs/screenshots/rescuezilla_5_functions_select_options.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/rescuezilla_5_functions_select_options.png) | **NEW:** Visual reference artifact documenting the five core Rescuezilla functions. |

---

## 7. Operational Runbook for Next Live Boot

1. **Reboot:** Reboot host system and select the Ventoy 2 USB drive (`F9` -> Boot Device Options).
2. **Boot Option:** Choose `rescuezilla-2.6.1-64bit.oracular.iso` -> **Boot with persistence**.
3. **Desktop Verification:**
   - Confirm desktop renders cleanly without any *"Desktop entry contains no valid Exec line"* dialog.
   - Confirm desktop displays four primary launchers:
     * `Rescue Suite (5 Functions)`
     * `Mount Network Storage (home40)`
     * `Run Backup CLI`
     * `Post Backup Wizard`
4. **Rescue Suite Execution:**
   - Double-click `Rescue Suite (5 Functions)`.
   - Test Option 6 (`Connect Network`) or Option 1 (`Backup Image`) to confirm automated SSHFS connection to `192.168.1.34:/media/alan/home40/Clonezilla`.
   - Confirm terminal window stays open cleanly upon operation completion.
