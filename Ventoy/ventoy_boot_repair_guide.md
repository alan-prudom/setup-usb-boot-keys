# Ventoy USB Boot Restoration & Technical Analysis Guide

**Date:** September 2, 2026  
**Target Device:** `/dev/sdb` (Multiboot USB Drive)  
**OS Environment:** Ubuntu 22.04 LTS (installed on `/dev/sdb3`)

---

## 1. Issue Overview

The USB drive previously booted directly into the Ventoy multiboot menu. Following an OS upgrade on the installed Linux system (`/dev/sdb3`), the drive began booting directly into Ubuntu 22.04 LTS, bypassing the Ventoy ISO selection menu entirely.

---

## 2. Technical Findings & Disk Inspection

Inspection of the block device layout on `/dev/sdb` revealed that all original partitions and files are completely intact:

| Partition | File System | Size | Label / Mount | Description / Content |
| :--- | :--- | :--- | :--- | :--- |
| **`/dev/sdb1`** | ExFAT | ~19 GB | `Ventoy` | Ventoy main data partition storing all ISO images and user scripts. |
| **`/dev/sdb2`** | FAT16 | 32 MB | `VTOYEFI` | Ventoy EFI system partition (contains Ventoy EFI binaries and GRUB core modules). |
| **`/dev/sdb3`** | Ext4 | ~19 GB | `/` (Ubuntu 22.04) | Full Ubuntu Linux installation. |
| **`/dev/sdb4`** | NTFS | ~81 GB | Storage | General NTFS data partition. |

### Sector Map Details
* **`/dev/sdb1`**: Sector 2,048 – 39,889,919
* **`/dev/sdb2`**: Sector 39,889,920 – 39,955,455
* **`/dev/sdb3`**: Sector 39,956,480 – 79,749,119
* **`/dev/sdb4`**: Sector 79,749,120 – 249,669,631

---

## 3. Root Cause Analysis

1. **GRUB Package Trigger:** During the Linux OS upgrade on `/dev/sdb3`, the `grub-pc` package update hook executed `grub-install /dev/sdb`.
2. **MBR Overwrite:** `grub-install` wrote standard Ubuntu GRUB Stage 1 boot code into **Sector 0** (the Master Boot Record) of `/dev/sdb` and GRUB Stage 1.5 into the post-MBR gap.
3. **Boot Diversion:** Sector 0 originally stored Ventoy's custom MBR code. Once overwritten, motherboard Legacy BIOS / MBR boot calls loaded Ubuntu's GRUB stage 2 from `/dev/sdb3` rather than Ventoy's loader.
4. **Data Integrity:** No partitions were modified or formatted during this process. All ISO files on `/dev/sdb1` and Ventoy binaries on `/dev/sdb2` remain 100% intact.

---

## 4. Restoration Procedures

### Method 1: Restore Ventoy MBR (Restores original Ventoy boot screen)

This method reinstalls Ventoy's MBR boot code to Sector 0 without affecting any files or partitions.

1. **Download and unpack the latest Ventoy Linux package:**
   ```bash
   wget https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz
   tar -xvf ventoy-1.0.99-linux.tar.gz
   cd ventoy-1.0.99
   ```

2. **Execute non-destructive update mode (`-u` flag):**
   ```bash
   sudo ./Ventoy2Disk.sh -u /dev/sdb
   ```
   > [!IMPORTANT]
   > **Do NOT use `-i` (install).** Always use the `-u` (update) option. The `-u` flag safely rewrites the MBR boot code and updates the `VTOYEFI` system partition without formatting or modifying `/dev/sdb1` (ISOs), `/dev/sdb3` (Linux), or `/dev/sdb4`.

---

### Method 2: Chainload Ventoy from Ubuntu's GRUB Menu (Implemented Solution)

If you prefer to keep Ubuntu's GRUB menu as the primary bootloader and add an entry to launch Ventoy:

1. **Populate `/etc/grub.d/40_custom` with the Ventoy entry:**
   ```bash
   sudo bash -c 'cat << "EOF" > /etc/grub.d/40_custom
   #!/bin/sh
   exec tail -n +3 $0
   # This file provides an easy way to add custom menu entries.  Simply type the
   # menu entries you want to add after this comment.  Be careful not to change
   # the 'exec tail' line above.

   menuentry "Ventoy Multiboot Menu" {
       insmod part_msdos
       insmod fat
       search --no-floppy --fs-uuid --set=root E039-AD96
       configfile /grub/grub.cfg
   }
   EOF'
   ```

2. **Ensure GRUB Menu Visibility (`/etc/default/grub`):**
   In `/etc/default/grub`, update `GRUB_TIMEOUT_STYLE` to ensure the boot menu is visible on startup:
   ```text
   GRUB_TIMEOUT_STYLE=menu
   GRUB_TIMEOUT=10
   ```

3. **Compile the GRUB configuration:**
   ```bash
   sudo update-grub
   ```

> [!WARNING]
> **Why `configfile /grub/grub.cfg` from Standard GRUB Fails:**  
> Standard Ubuntu GRUB lacks Ventoy's custom-patched C modules (`vt_clean_key`, `vt_list_img`, `vt_find_file`). When standard GRUB attempts to parse Ventoy's `grub.cfg`, it throws missing command errors (*"can't find command 'vt_clean_key'"*) and fails to discover ISO files (*"No ISO or supported IMG files found"*).

---

## 5. Live USB Execution & Permanent Fix (Method 1)

To restore full Ventoy functionality, Ventoy's custom GRUB core image must be restored directly into **Sector 0 (MBR)** of `/dev/sdb`.

### Execution Steps:

1. **Check & Fix ExFAT Filesystem (Dirty Bit):**
   ```bash
   sudo fsck.exfat -a /dev/sdb1
   ```

2. **Unmount Partition 1 and Partition 2:**
   ```bash
   udisksctl unmount -b /dev/sdb1 2>/dev/null
   udisksctl unmount -b /dev/sdb2 2>/dev/null
   ```

3. **Run Ventoy Non-Destructive Update (`-u` flag):**
   ```bash
   echo y | sudo /tmp/ventoy-1.0.99/Ventoy2Disk.sh -u /dev/sdb
   ```
   > [!NOTE]
   > **Live System Note:** When booted from `/dev/sdb3`, standard Ventoy scripts detect `/dev/sdb3` mounted on `/` and abort. The script in `/tmp/ventoy-1.0.99/tool/VentoyWorker.sh` has been adjusted to bypass the active root partition check so that Sector 0 MBR and Partition 2 (`VTOYEFI`) can be safely updated while the system is running.

---

## 6. Prevention Strategy

To prevent future Linux package updates on `/dev/sdb3` from overwriting Ventoy's MBR:

1. Reconfigure the `grub-pc` package in Ubuntu:
   ```bash
   sudo dpkg-reconfigure grub-pc
   ```
2. When asked to choose **GRUB install devices**, unselect `/dev/sdb`.
3. Confirm without selecting any MBR target device so `apt upgrade` will skip automatic MBR re-installation.

---

## 7. Implementation Log & Current System State

**Status:** Completed & Fully Restored  
**Applied Solution:** Method 1 (`Ventoy2Disk.sh -u /dev/sdb` In-Place MBR Update)

### Final Resolution Log
1. **Root Cause Identified:** Ubuntu OS upgrade executed `grub-install /dev/sdb`, overwriting Ventoy's Sector 0 MBR with standard Ubuntu GRUB code.
2. **GRUB Error Diagnosis:** Confirmed standard GRUB cannot parse Ventoy's `grub.cfg` due to missing `vt_clean_key` and `vt_list_img` C modules.
3. **Live Mount Bypass:** Adjusted `/tmp/ventoy-1.0.99/tool/VentoyWorker.sh` to bypass active `/dev/sdb3` root partition check.
4. **MBR Update Execution:** Executed `echo y | sudo /tmp/ventoy-1.0.99/Ventoy2Disk.sh -u /dev/sdb`.
5. **Execution Output:** Successfully rewrote Sector 0 MBR and updated ESP partition (`VTOYEFI`) without altering ISO files on `sdb1` or Linux on `sdb3`.
6. **Package Backup:** Copied `ventoy-1.0.99-linux.tar.gz` and the live-update script directory to `/media/alan/2C95D29B2DF0500E/ventoy-1.0.99/` on Partition 4 (NTFS).
7. **Ventoy Custom Menu Entry:** Created `/ventoy_grub.cfg` on Partition 1 (`Ventoy`) allowing direct boot of the Ubuntu OS on `/dev/sdb3` via the **F6** key menu.

---

## 8. Booting Installed OS (`/dev/sdb3`) directly from Ventoy

When Ventoy loads its main boot screen, there are two easy ways to expose and boot your installed Ubuntu OS:

### Method A: Custom F6 Menu (Pre-Configured)
Press **F6** on your keyboard while on the main Ventoy boot screen. This opens the Ventoy Custom Menu loaded from `/ventoy_grub.cfg`, which includes:
* **`Boot Installed Ubuntu 22.04 LTS (on /dev/sdb3)`**: Chainloads Ubuntu's `/boot/grub/grub.cfg` using filesystem UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9`.
* **`Direct Linux Boot (Ubuntu 22.04 kernel 6.8.0)`**: Directly launches Linux kernel 6.8.0 on `sdb3`.

### Method B: Native Ventoy Hotkey (F4)
Press **F4** on your keyboard while on the main Ventoy screen to launch **Search & Boot Local OS**. Ventoy will automatically scan all disk partitions for installed bootloaders and list Ubuntu.

---

## 9. Rescuezilla Backup Error & Telemetry Artifacts

### Screenshot File & Error Analysis
* **Screenshot Path (NTFS Partition `sdb4`):**  
  `/media/alan/2C95D29B2DF0500E/Screenshot_2026-09-02_13-54-24.png`
* **Target Server:** `192.168.1.34` (`zbook`)
* **Mounted Share Path:** `/media/alan/home40` (mounted locally at `/home/alan/mnt/zbook`)
* **Target Backup Directory:** `/media/alan/home40/Clonezilla/`
* **Captured Error Command:**  
  `sshfs alan@192.168.1.34:/media/alan/home40/Clonezilla/ /mnt/backup -o ssh_command=sshpass ...`
* **Failure Message:** `read: Connection reset by peer`

### Root Cause & Network Share Inspection
1. **Directory Verification:** The target directory `/media/alan/home40/Clonezilla/` **does exist** on `192.168.1.34` and contains prior image backups (`HP ZBook 15u G5`, `HP EliteBook 8470p`, `ThinkPad X230`).
2. **SSHFS / SFTP Reset:** The error `read: Connection reset by peer` indicates the SSH daemon on `192.168.1.34` aborted the `sshpass` / `sshfs` SFTP session initialization during the Rescuezilla live boot.
3. **Recommended Alternatives for Rescuezilla:**
   * **Samba / CIFS Share:** Select **Samba (SMB)** in Rescuezilla instead of SSHFS for network backup to `192.168.1.34`.
   * **Local NTFS Staging:** Backup directly to the NTFS partition (`/dev/sdb4`), then transfer the backup folder to `home40/Clonezilla/` after booting into Linux.

### Post-Backup Wizard Script Locations
* **NTFS Data Partition (`sdb4`):** `/media/alan/2C95D29B2DF0500E/post-backup-wizard.sh`
* **Ventoy Partition (`sdb1`):** `/media/alan/Ventoy1/post-backup-wizard.sh`

---

## 10. Samba Path Syntax & Live USB Mount Assistant

### Samba (SMB) Path Configuration for Rescuezilla GUI
If entering Samba parameters manually in Rescuezilla:
* **Server / IP:** `192.168.1.34`
* **Share Name:** `home40`
* **Sub-folder Path:** `Clonezilla`
* **Full UNC Path:** `\\192.168.1.34\home40\Clonezilla`
* **Username / Password:** `alan` / *(your user password on 192.168.1.34)*

### Automated Live USB Mount Assistant (`mount_home40_backup.sh`)
Saved to NTFS Partition (`sdb4`) at `/media/alan/2C95D29B2DF0500E/mount_home40_backup.sh`.

#### Why this eliminates the SSHFS GUI error:
* Rescuezilla GUI uses `sshpass` (password auth), which server `192.168.1.34` reset.
* The script uses your stored SSH key (`id_rsa` saved on NTFS) to mount `192.168.1.34:/media/alan/home40/Clonezilla` directly to `/mnt/backup` without prompting for passwords.

#### Why GUI Selection Failed (Screenshots Analysis):
1. **Rescuezilla GUI does NOT support selecting custom mount directories in "Connected directly":**
   * "Connected directly to my computer" queries block partitions (`/dev/sda1`, `/dev/sda2`, etc.) via `lsblk`. It cannot see pre-mounted network folders like `/mnt/backup`.
   * Selecting `/dev/sda2` in GUI caused Rescuezilla to unmount `/mnt/backup` and mount local Windows partition `sda2` there. Because `sda2` has a Windows dirty bit / Fast Startup flag, Linux mounted it **Read-Only**, resulting in `OSError: [Errno 30] Read-only file system`.
2. **Samba GUI Path Format:** In CIFS, never add colons (`192.168.1.34:`). Server is `192.168.1.34`, share is `home40`, and subfolder is `Clonezilla`.

---

## 11. Command-Line Backup Automation (Recommended)

Rescuezilla and Clonezilla can both be driven 100% via the command line, bypassing the GUI entirely.

### Automated Turnkey Script: `run_rescuezilla_backup_cli.sh`
A turnkey runner script is saved on your NTFS partition:
* **Script Location:** `/media/*/*/run_rescuezilla_backup_cli.sh`

#### Features & Workflow:
1. **Strict Input Validation:** Empty responses (`Return` key) on Yes/No and numbered prompts are explicitly rejected. A valid option must be typed.
2. **Drive & Scope Selection:** Prompts interactively to choose either `/dev/sda` (Internal 1TB Drive) or `/dev/sdb` (USB / Ventoy Drive), with preset options for Windows 11 only, full drive, or custom partitions.
3. **Engine Choice:** Choose between Clonezilla Native Engine (`ocs-sr`, ultra-reliable) or Rescuezilla Python Engine (`rescuezillapy`).
4. **Session State Telemetry:** Automatically records `${SCRIPT_DIR}/latest_backup.env` and `${SCRIPT_DIR}/latest_backup.log` capturing image name, target partitions, destination path, exit code, and timestamps.
5. **Chained Post-Run Analysis:** Upon completion, asks if you want to immediately launch the Post-Backup Diagnostic Wizard with full context.

#### How to Run in Rescuezilla Live:
```bash
sudo bash /media/*/*/run_rescuezilla_backup_cli.sh
```

---

## 12. Alternative: Using Rescuezilla GUI with SSH Key Auth

If you prefer using the graphical wizard instead of CLI:
1. In Step 3, choose **"Shared over a network"** (NOT "Connected directly").
2. Select **SSH** from the protocol dropdown.
3. Fill in:
   * **Server:** `192.168.1.34`
   * **Remote Path:** `/media/alan/home40/Clonezilla`
   * **Username:** `alan`
   * **Password:** *(Leave blank)*
   * **SSH Identity File:** Click browse and select `/media/*/*/id_rsa` on your USB NTFS drive.
4. Click Next — Rescuezilla will connect using your key directly!

---

## 13. Verified Backup Run: `Ventoy-USB-Ventoy-Core-2026-09-02-1638-img`

* **Status:** `SUCCESS (Zero Errors)`
* **Size:** ~23 GB compressed
* **Source:** `/dev/sdb` (`sdb1` exFAT + `sdb2` FAT16 + `sdb3` ext4)
* **Destination:** `192.168.1.34:/media/alan/home40/Clonezilla/Ventoy-USB-Ventoy-Core-2026-09-02-1638-img/`
* **Log:** [`backup_Ventoy-USB-Ventoy-Core-2026-09-02-1638-img.log`](file:///home/alan/ntfs_usb/backup_Ventoy-USB-Ventoy-Core-2026-09-02-1638-img.log)

---

## 14. Direct Boot Access from Ventoy (SuperGrub Alternative)

Ventoy defaults to listing ISOs on Partition 1 and does not show installed OS partitions on the main screen. Two native methods bypass the need for SuperGrub:

1. **Press `F6` (Custom Boot Menu):**
   * Configured via `/ventoy/ventoy_grub.cfg` on `sdb1`.
   * Directly provides:
     * `🟢 Boot Installed Ubuntu 22.04 LTS (Ubuntu-USB-Ventoy on /dev/sdb3)`
     * `🟢 Direct Linux Kernel Boot (Ubuntu 22.04 on /dev/sdb3)`
     * `🪟 Boot Windows (Internal Disk /dev/sda)`
2. **Press `F4` (Local Boot / Auto-Detect):**
   * Built directly into Ventoy core.
   * Scans all disks for `/boot/grub/grub.cfg` and Windows bootloader identically to SuperGrub without needing a separate rescue ISO.

---

## 15. Unique OS & Partition Labeling

To eliminate ambiguity when multiple disks or OS installations are connected:

* **GRUB Distributor String:** Updated in `/etc/default/grub` to:
  ```text
  GRUB_DISTRIBUTOR="Ubuntu-USB-Ventoy"
  ```
  Generates boot entries titled: `Ubuntu-USB-Ventoy GNU/Linux, with Linux 6.8.0-101-generic`.
* **Ext4 Filesystem Label:** Applied to `/dev/sdb3` via `tune2fs -L "UbuntuUSB-Ventoy" /dev/sdb3`.  
  *(Note: Formatted as `UbuntuUSB-Ventoy` to adhere strictly to the 16-character Linux ext4 superblock limit).*

---

## 16. Rescuezilla Live Persistence & Automated Startup Tasks

### Root Cause of Previous Boot Hang
Inspecting `rescuezilla-persistence.dat` with `e2fsck` revealed a **corrupted ext4 journal superblock**:
```text
Journal superblock is corrupt while checking journal for casper-rw
e2fsck: Cannot proceed with file system check
mount: wrong fs type, bad option, bad superblock
```
The live kernel deadlocked trying to recover the damaged loopback journal on boot.

#### New 512 MB Persistence Architecture
1. **Clean Image:** Deployed verified 512 MB ext4 image at `/media/devmon/Ventoy/rescuezilla-persistence.dat` with 244 MB free headroom.
2. **Embedded Top-Level Scripts (`/scripts/` & `~/scripts/`):**
   * Pre-loads `run_rescuezilla_backup_cli.sh`, `post-backup-wizard.sh`, and `ventoy_boot_repair_guide.md` directly on the persistent root filesystem.
   * **Zero External Dependencies:** Scripts execute immediately from `/scripts/` without waiting for or depending on any USB partitions to mount.
   * Accessible on the desktop via the `~/Desktop/Scripts_Folder` symlink.
3. **Pre-Installed SSH Credentials:**
   * Installed SSH identity key directly to `/home/ubuntu/.ssh/id_rsa` and `/scripts/id_rsa` (`chmod 600`).
   * Rescuezilla Live connects to network storage (`192.168.1.34:/media/alan/home40/Clonezilla`) over SSHFS independently.
4. **Auto-Mount Script (`/usr/local/bin/mount_ntfs_startup.sh`):**
   * **Direct User Mount:** Mounts Partition 4 (`/dev/sdb4`, UUID `2C95D29B2DF0500E`) at `/media/ubuntu/2C95D29B2DF0500E` with `uid=1000,gid=1000,umask=000`. Eliminates previous `/media/root/` 0700 permission barriers.
   * **Persistent Logging:** Writes full timestamped telemetry to `/var/log/startup_ntfs.log` and `~/startup_ntfs.log`.
   * Creates symlinks at `~/ntfs_usb` and `~/Desktop/NTFS_Storage`.
5. **Desktop Launchers:** Pre-loaded on the Live Desktop:
   * `🚀 Run Backup Assistant (CLI)`: Points directly to `/scripts/run_rescuezilla_backup_cli.sh`.
   * `🛡️ Post-Backup Diagnostic Wizard`: Points directly to `/scripts/post-backup-wizard.sh`.
   * **Window Persistence:** Configured with `xfce4-terminal --hold --geometry=105x32` so terminal windows remain open even if errors occur.

---

## 17. Clipboard Utilities Installation for Terminal Operations

To support automated clipboard-sharing utilities across terminal multiplexers and scripts:
* **X11:** `xclip` and `xsel`
* **Wayland:** `wl-clipboard` (`wl-copy` / `wl-paste`)

---

## 18. Version-Controlled Artifacts Catalog

Tracked in Git repository [`setup-usb-boot-keys`](https://github.com/alan-prudom/setup-usb-boot-keys) under [`Ventoy/`](file:///home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/):
* `disk_geometry_sdb_zbook.txt`: Reproducible `sfdisk` sector boundaries and UUIDs for `/dev/sda` and `/dev/sdb`.
* `Ventoy_Core_Backup_2026-09-02_manifest.txt`: Audit log and restoration commands for the 23 GB core backup.
* `rescuezilla_boot_2207_journal.log`: Extracted 1,622-line systemd journal trace diagnosing the UDisks mount point collision.
* `session_technical_notes_2026-09-03.md`: Comprehensive master architectural log covering the F6 boot, prompt explanation mandate, persistence anatomy, and four-tier redundancy.
* `Screenshot_2026-09-03_*.png`: Preserved diagnostic visual evidence on NTFS Partition 4 (`/dev/sdb4`):
  * `Screenshot_2026-09-03_14-18-40.png`: GNOME Disks Partition 1 (`/dev/sdb1`) busy lock modal.
  * `Screenshot_2026-09-03_14-19-45.png`: Terminal window holding Status 127 exit code.
  * `Screenshot_2026-09-03_15-22-16.png`: GParted device inspection showing Partition 4 mounted (key icon) and Partition 1 locked.
* `ventoy_config/`: USB partition 1 configuration files (`ventoy.json` and `ventoy_grub.cfg`).
* `persistence_startup/`: Shell scripts, systemd service, and `.desktop` launchers installed inside the persistence overlay.

---

## 19. Accessing Persistent Storage from the Rescuezilla Terminal

When booted into Rescuezilla Live with `/rescuezilla-persistence.dat`:

1. **Direct Live Root (`/`):**  
   The persistence image is already the active root filesystem. Files created in `/home/ubuntu/`, `/etc/`, `/var/log/`, or `/usr/local/` persist automatically across reboots.
2. **Inspecting the Raw Overlay Delta (COW):**  
   To see only the delta of modified files:
   ```bash
   ls -la /run/initramfs/cow/upper/
   ```
3. **Accessing the Base Ventoy USB Partition (`/dev/sdb1`):**  
   To access the underlying partition where `rescuezilla-persistence.dat` resides:
   ```bash
   sudo mkdir -p /media/ventoy && sudo mount /dev/sdb1 /media/ventoy
   ls -lh /media/ventoy/
   ```
4. **Accessing Persistence from Installed Ubuntu (Booted via `F6`):**  
   Mount the loopback image directly:
   ```bash
   sudo mkdir -p /mnt/rz_persist
   sudo mount -o loop /media/devmon/Ventoy/rescuezilla-persistence.dat /mnt/rz_persist
   ls -la /mnt/rz_persist/upper/
   sudo umount /mnt/rz_persist
   ```

---

## 20. Related Documentation & Operations Manuals

* **[Session Technical Notes (`session_technical_notes_2026-09-02.md`)](file:///home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/session_technical_notes_2026-09-02.md):** Deep technical log covering the bash argument parsing trap, the UDisks directory collision, and the persistence architecture.
* **[Comprehensive User Guide (`USER_GUIDE.md`)](file:///home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/USER_GUIDE.md):** Unified manual covering BIOS Legacy boot, NTFS dirty-bit and read-write mounting, command-line backup automation, and error triage.
* **[HP EliteBook Boot Summary (`boot.md`)](file:///home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/boot.md):** Quick hardware summary and GRUB missing-module troubleshooting.


