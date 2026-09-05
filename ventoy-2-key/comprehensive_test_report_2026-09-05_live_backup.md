# Forensic Engineering Report: Rescuezilla Live Boot, Image Backup Verification & Runtime Analysis

**Author / Session Lead:** Alan P & Assistant  
**Date of Record:** September 5, 2026 (10:15 UTC+1)  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Target Hardware:** 128 GB SanDisk Multi-Boot USB (`/dev/sdb`, Ventoy 2)  
**Status:** **DISCUSS ONLY (NO SCRIPT / SYSTEM CHANGES APPLIED)**  
**Target File:** `ventoy-2-key/comprehensive_test_report_2026-09-05_live_backup.md`

---

## 1. Executive Summary & Test Milestone

The recent live boot into Rescuezilla 2.6.1 Live with persistence on the 128 GB Ventoy 2 USB drive achieved a major technical success:
- **Full Operational Backup Created & Verified:** The automated Clonezilla/Rescuezilla CLI backup assistant successfully imaged partitions `/dev/sdb1` (Ventoy exFAT, ~19 GB) and `/dev/sdb2` (VTOYEFI, 32 MB) directly across the network to the central storage server at `192.168.1.34:/media/alan/home40/Clonezilla`.
- **Zero Image Corruption:** The created image `Ventoy-USB-Custom-2026-09-05-0811-img` finished with exit code 0 (`STATUS: BACKUP COMPLETED SUCCESSFULLY (Zero Errors)`), verified in both the live execution logs and the post-backup diagnostic wizard.
- **Persistence & Network Stability:** The Casper OverlayFS persistence layer (`rescuezilla-persistence.dat`) mounted cleanly, preserving history, SSH credentials, and startup configurations. SSHFS connected without interactive key failures.

Detailed forensic examination of the user-provided error logs, telemetry files, and screenshots on `/ntfs` (the 82 GB `SHARED FAT` partition) and the loop-mounted persistence container identified **four specific runtime issues** for discussion.

---

## 2. Forensic Analysis of Evidence & Logs

### 2.1 The Successful Backup Run (`backup_Ventoy-USB-Custom-2026-09-05-0811-img.log`)
From `/ntfs/scripts/backup_Ventoy-USB-Custom-2026-09-05-0811-img.log`:
- **Start Time:** 2026-09-05 08:12:42 UTC
- **Completion Time:** 2026-09-05 08:52:13 UTC (Duration: ~39 minutes)
- **Partitions Imaged:**
  - `sdb1`: Saved as `sdb1.exfat-ptcl-img.gz` via Partclone.
  - `sdb2`: Saved as `sdb2.dd-ptcl-img.gz` via `dd` / raw block copy.
  - Device geometry, block device attributes (`blkdev.list`, `blkid.list`), MBR boot record, DMI, and SMART telemetry saved cleanly.
- **Exit Code:** `0` (Success).

---

## 3. Detailed Root Cause Analysis of Remaining Issues

### 3.1 Issue 1: Desktop Modal Error ("Desktop entry contains no valid Exec line")
* **User Screenshot:** `/ntfs/Screenshot_2026-09-05_08-04-23 I get this when I click on desktop widgets.png`
* **Symptom:** Clicking specific desktop icons or starting the desktop environment displays a modal dialog: *"Desktop entry contains no valid Exec line"*.
* **Deep Forensic Discovery:**
  - In earlier passes, we eliminated `mount-ntfs.desktop`. However, desktop validation with `desktop-file-validate` on all shortcuts inside `/upper/home/ubuntu/Desktop/` revealed the true culprit:
    ```text
    /upper/home/ubuntu/Desktop/xfce4-terminal.desktop: error: required key "Exec" in group "Desktop Action preferences" is not present
    FAILED
    ```
  - **The Specific Bug:** In Rescuezilla's default live template (`/home/ubuntu/.local/share/applications/xfce4-terminal.desktop`), there is a section at the very end:
    ```ini
    [Desktop Action preferences]
    Name=Preferences
    ...
    Exec=
    ```
    The `Exec=` key is empty. PCManFM (the desktop file manager) parses all `.desktop` files in `~/Desktop/`. When it encounters `xfce4-terminal.desktop` (which is symlinked directly onto the desktop from `~/.local/share/applications/xfce4-terminal.desktop`), it throws *"Desktop entry contains no valid Exec line"*.
  - **Proposed Resolution:**
    1. Fix the `Exec=` key in `/home/ubuntu/.local/share/applications/xfce4-terminal.desktop` to `Exec=xfce4-terminal --preferences` (or remove the malformed `[Desktop Action preferences]` section).
    2. Alternatively, symlink standard `/usr/share/applications/xfce4-terminal.desktop` (which is valid and clean) instead of the customized local broken copy.

---

### 3.2 Issue 2: FAT Filesystem Symlink Rejection in Backup Assistant
* **Log Error (`error report 01.txt`):**
  ```text
  Now syncing - flush filesystem buffers...
  Ending /usr/sbin/ocs-sr at 2026-09-05 08:52:13 UTC...
  ln: failed to create symbolic link '/media/ubuntu/SHARED_FAT/scripts/latest_backup.log': Operation not permitted
  ```
* **Root Cause Analysis:**
  - On line 271 of `run_rescuezilla_backup_cli.sh`, the script attempts:
    ```bash
    ln -sf "$LOG_FILE" "${SCRIPT_DIR}/latest_backup.log"
    ```
  - When scripts are run from `/media/ubuntu/SHARED_FAT/scripts/` (the FAT32 partition `sdb4`), the underlying filesystem is FAT32. **FAT32 does not support POSIX symbolic links.** The Linux VFAT driver rejects the `symlink()` syscall with `EPERM` ("Operation not permitted").
* **Proposed Resolution:**
  - In `run_rescuezilla_backup_cli.sh`, detect whether `$SCRIPT_DIR` supports symlinks; if not, use `cp -f "$LOG_FILE" "${SCRIPT_DIR}/latest_backup.log"`, or rely on `latest_backup.env` (which writes cleanly and already works).

---

### 3.3 Issue 3: Rescuezilla Image Explorer CLI Usage Mismatch
* **Log Error (`error report 04.txt`):**
  ```text
  Enter your selection [0-9]: 5
  >>> Image Explorer (Mount & Browse Files Inside Image)...
  ...
  Launching Rescuezilla Image Explorer...
  usage: rescuezillapy mount [-h] [--source [SOURCE]] [--destination [DESTINATION]]
                             [source_positional_arg] [destination_positional_arg]
  rescuezillapy mount: error: one of the arguments --source source_positional_arg is required
  ```
* **Root Cause Analysis:**
  - Option 5 of `rescue_suite_launcher.sh` executed:
    ```bash
    sudo /usr/sbin/rescuezillapy mount &
    ```
  - In Rescuezilla 2.6.1, `rescuezillapy mount` is a command-line tool that **requires** the source image directory/file and destination mount point as positional arguments. When invoked without arguments, it exits with an error.
* **Proposed Resolution:**
  - For Option 5, present an interactive image selector listing available images in `/home/partimag/` (e.g. `Ventoy-USB-Custom-2026-09-05-0811-img`), ask the user which image they want to explore, and execute:
    ```bash
    mkdir -p /mnt/image_explorer
    sudo /usr/sbin/rescuezillapy mount --source "/home/partimag/<selected-image>" --destination /mnt/image_explorer
    pcmanfm /mnt/image_explorer &
    ```
  - Or, if the full graphical wizard is desired, launch `sudo rescuezilla` which opens the native Rescuezilla GUI.

---

### 3.4 Issue 4: Partition Selection Table in CLI Backup Wizard
* **User Screenshot:** `/ntfs/Screenshot_2026-09-05_08-09-35 Ideally should list all partitions with names, os and or type, size.png`
* **User Feedback:** *"Ideally should list all partitions with names, os and or type, size"*
* **Current Implementation:**
  - Currently prompts with generic presets:
    ```text
    [2/4] Target Drive Selection
      [1] /dev/sda (Internal 1TB Drive - Windows OS + User Data)
      [2] /dev/sdb (128GB USB / SD Drive - Ventoy Bootloader & Live OS)
    Select drive to backup [1-2]:
    ```
  - The user has to guess or recall partition layout instead of seeing a formatted table.
* **Proposed Enhancement:**
  - Dynamically query `lsblk` and format a clean table before asking for input:
    ```text
    ================================================================================
    DEVICE    SIZE   TYPE    FILESYSTEM  LABEL            MOUNTPOINT           INFO
    ================================================================================
    sda1      579M   part    ntfs        System Reserved                       Boot Loader
    sda2      141.5G part    ntfs                                              Windows OS
    sda3      110.8G part    ntfs        Data                                  User Data
    sda5      567.0G part    ext4                         /media/.../Internal  Linux Root
    --------------------------------------------------------------------------------
    ```
  - Allow the user to select partitions via comma- or space-separated list or convenient presets.

---

## 4. Verification of Other Features Tested

| Tested Feature | Status | Forensic Observation |
| :--- | :--- | :--- |
| **Option 4: Verify Backup Image** | **Operational** | Scanned and listed all 17 historical and fresh backup images in `/home/partimag` (`error report 03.txt`). |
| **Option 6: Connect Network Storage** | **Operational** | Verified remote mount at `192.168.1.34:/media/alan/home40/Clonezilla` without hanging. |
| **Post-Backup Diagnostic Wizard** | **Operational** | Automatically detected image completion, parsed telemetry, confirmed 0 errors, and offered diagnostic export options (`info report 02.txt`). |
| **Input Validation** | **Operational** | Empty inputs (Return key) cleanly rejected with warning message rather than crashing or skipping options. |
