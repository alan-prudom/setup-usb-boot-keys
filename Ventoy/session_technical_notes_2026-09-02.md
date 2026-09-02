# Comprehensive Technical Notes: Ventoy Multi-Boot, Backup Automation & System Architecture

**Author / Session Lead**: Alan P & Assistant  
**Date of Record**: September 2, 2026  
**Target Hardware**: HP ZBook 15u G5 (`alan-USB-g5`)  
**Storage Environment**: 128 GB Multi-Boot USB (`/dev/sdb`) & Internal 1 TB NVMe/SATA SSD (`/dev/sda`)  
**Network Backup Target**: `192.168.1.34:/media/alan/home40/Clonezilla/`

---

## 1. Core Discussion Points & Root Cause Investigations

### 1.1 Why the Installed OS Disappeared from Ventoy & Why SuperGrub Was Needed
* **The Symptom:** After updating or booting from the 128 GB USB stick, the laptop loaded the Ventoy blue menu. However, the installed Ubuntu OS on Partition 3 (`/dev/sdb3`) was not listed anywhere in the menu. The only way to boot back into this Ubuntu environment was to boot into `supergrub2-classic-2.06s4-multiarch-CD.iso`, run "Detect and show boot methods", and select the kernel.
* **The Root Cause:**
  1. Ventoy’s installation overwrites the Master Boot Record (MBR) of `/dev/sdb`. Previously, the USB's MBR contained GRUB code pointing directly to `/dev/sdb3`.
  2. Ventoy is architected strictly as an ISO/image file launcher. By default, its GRUB engine scans only Partition 1 (`/dev/sdb1`, formatted exFAT) for files matching `.iso`, `.img`, `.vhd`, and `.wim`.
  3. Partition 3 (`/dev/sdb3`) is a full, installed Linux ext4 root filesystem—not an ISO image. Therefore, Ventoy completely ignored it during standard menu generation.
* **The Implemented Solutions:**
  1. **Ventoy Menu Extension Plugin (`F6`):** Created `/ventoy/ventoy_grub.cfg` on Partition 1. When the Ventoy screen loads, pressing **`F6`** opens a custom GRUB menu that directly searches for UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9` and executes `configfile /boot/grub/grub.cfg`. This boots the installed OS in ~2 seconds.
  2. **Ventoy Localboot (`F4`):** Documented that pressing **`F4`** triggers Ventoy's native disk scanner, which detects and boots `/boot/grub/grub.cfg` and Windows bootloaders identically to SuperGrub without loading an external ISO.
  3. **SuperGrub Prominence:** Added an alias in `ventoy.json` (`>>> Super Grub2 Disk (Auto-Detect All OSes)`) for quick identification in the ISO list.

---

### 1.2 Analysis of `diag2.md`: Why the PC Backup Failed vs. Why the USB Backup Succeeded
* **The Disconnect:** Reviewing `diag2.md` revealed that an earlier attempt to back up this machine resulted in errors, whereas later a 23 GB image was successfully saved.
* **Failure Mode 1 (Rescuezilla GUI Crash):**
  * In the GUI wizard (Screenshot 4), `/mnt/backup` had been manually mounted over SSHFS. In Step 3 ("Connected directly"), `/dev/sda2` was clicked. Rescuezilla attempted to mount `/dev/sda2` at `/mnt/backup`.
  * Because Windows Fast Startup was active, Linux mounted `/dev/sda2` as **Read-Only**. Python’s `os.mkdir` failed with `[Errno 30] Read-only file system`.
* **Failure Mode 2 (Rescuezilla CLI Wrapper Bug in `diag2.md`):**
  * The first CLI script called `/usr/sbin/rescuezilla` (a bash wrapper).
  * Line 115 in `backup_Ventoy_USB.log` executed:
    ```bash
    /usr/lib/udisks2/udisks2-inhibit /usr/sbin/rescuezillapy backup \
        --source /dev/sda --partitions sdb1 sdb2 sbd3 \
        --destination /mnt/backup/Ventoy_USB \
        --description CLI Backup created on 2026-09-02-1536 \
        --compression-format gzip
    ```
  * Because `--description` contained unquoted spaces in the wrapper, the shell split the string into extra positional arguments, triggering:
    ```text
    rescuezillapy backup: error: argument source_positional_arg: not allowed with argument --source
    ```
  * In addition, `--source /dev/sda` collided with partitions `sdb1 sdb2 sbd3` (which belonged to the USB stick, not the internal disk, with a typo `sbd3`). The backup halted before writing any data.
* **The Successful Backup:**
  * At 16:38 UTC, the updated script was executed targeting `/dev/sdb` using Clonezilla's native CLI engine (`ocs-sr`).
  * Backed up `sdb1` (exFAT), `sdb2` (FAT16 EFI), `sdb3` (ext4 OS), and MBR into `Ventoy-USB-Ventoy-Core-2026-09-02-1638-img` (23 GB compressed, zero errors).
* **Takeaway:** The internal PC drive (`/dev/sda` — Windows 11) **has not yet been backed up**. The updated runner is configured to image `/dev/sda` (Windows 11 OS partitions `sda1` + `sda2`) whenever ready.

---

### 1.3 Why Rescuezilla Persistence Froze on Boot
* **The Problem:** The user reported: *"I did get Rescuezilla iso to boot. But only if I did not select the persistant memeory."*
* **Investigation Findings:**
  1. **Filesystem Corruption:** Inspecting the original 1 GB `rescuezilla-persistence.dat` with `e2fsck` revealed:
     ```text
     e2fsck: The journal superblock is corrupt while checking journal for casper-rw
     e2fsck: Cannot proceed with file system check
     mount: wrong fs type, bad option, bad superblock on /dev/loop0
     ```
     The ext4 journal was severely corrupt. When the kernel booted Rescuezilla and tried to replay the loopback journal during initramfs, the ext4 driver deadlocked.
  2. **Casper Label Specification:** `rescuezilla-2.6.2-64bit.noble.iso` is built on Ubuntu 24.04 (Noble Numbat). Ubuntu 24.04 deprecated the legacy `casper-rw` label in favor of `writable`.
* **The Fix Implemented:**
  1. Created a fresh, verified **512 MB** ext4 persistence file at `/media/devmon/Ventoy/rescuezilla-persistence.dat` (`e2fsck` verified 0 errors).
  2. Embedded an automated startup service (`mount_ntfs_startup.sh`) that automatically mounts the USB NTFS partition (`/dev/sdb4`), creates convenience symlinks, sets `chmod 600 id_rsa`, and places Desktop launchers for the backup scripts.

---

### 1.4 Partition and GRUB Naming Constraints (Ext4 Superblock Limit)
* **The Goal:** Change the generic name `"Ubuntu"` so the USB environment is clearly identifiable in SuperGrub, GRUB, and partition managers.
* **The Technical Constraint:**
  * The user requested the label: `Ubuntu-USB-Ventoy` (17 characters).
  * The Linux ext4 filesystem specification allocates a fixed 16-byte field in the superblock for the volume name (`s_volume_name[16]`). `tune2fs` returned `Warning: label too long, truncating.`
* **The Solution Implemented:**
  * **Superblock Volume Label:** Set to **`UbuntuUSB-Ventoy`** (exactly 16 characters). This displays cleanly in GNOME Disks, GParted, and SuperGrub's disk list without truncation.
  * **GRUB Distributor String:** Updated `/etc/default/grub` to `GRUB_DISTRIBUTOR="Ubuntu-USB-Ventoy"` (GRUB has no 16-byte restriction). Generated menu entries now read:
    `🟢 Ubuntu-USB-Ventoy GNU/Linux, with Linux 6.8.0-101-generic`.

---

### 1.5 Interactive CLI Prompt Design & Strict Input Validation
* **User Directive:** *"Please improve UI to make return on y/n answers be rejected. a valid response must be typed... please explain the reasons behind why you are asking for each prompt. remember this instruction."*
* **Implementation:**
  1. Built a `prompt_yes_no()` helper that loops indefinitely upon empty input (pressing Return/Enter), displaying:
     `⚠️ Empty response (Return key) is not accepted. You must explicitly type 'y' or 'n'.`
  2. Built a `prompt_choice()` helper enforcing valid integer selections (`[1-2]`, `[1-3]`) and rejecting bare Return presses.
  3. Added an in-terminal `ℹ️ Why we ask this:` explainer directly above each prompt in `run_rescuezilla_backup_cli.sh`:
     * *Drive Selection:* Explains the risk of confusing the internal 1TB SSD with the USB stick.
     * *Scope Selection:* Explains time and storage savings (Windows OS only vs. full 1TB disk).
     * *Image Naming:* Explains preventing overwrite of previous snapshots and character sanitization for exFAT/Samba.
     * *Engine Selection:* Explains Clonezilla's battle-tested CLI stability vs. Rescuezilla's experimental CLI.
     * *Execution Confirmation:* Explains the magnitude of disk read/network write operations before committing.

---

### 1.6 Linux System Clipboard Subsystem
* **The Problem:** Tooling reported: `no supported clipboard tool found (install wl-clipboard or xclip)`.
* **The Fix:**
  * Fixed an unmet dependency in `apt` (`firefox-locale-en` downgrade conflict).
  * Installed both primary Linux clipboard providers:
    * `/usr/bin/xclip` and `/usr/bin/xsel` for X11 / Openbox environments.
    * `/usr/bin/wl-copy` and `/usr/bin/wl-paste` (`wl-clipboard`) for Wayland sessions.

---

## 2. Comprehensive File & Artifact Register

All files created, edited, and synchronized across physical partitions and version control:

| File Path / Target | Purpose & Contents | Synchronization Locations | Git Status |
| :--- | :--- | :--- | :--- |
| **`Ventoy/ventoy_boot_repair_guide.md`** | Comprehensive runbook & technical troubleshooting manual (Sections 1–18). | Repo, NTFS USB root, NTFS USB `docs/`, Ventoy partition, secondary clone. | Committed (`91a0098`), Pushed to `origin/main` |
| **`Ventoy/run_rescuezilla_backup_cli.sh`** | Turnkey CLI backup automation runner with strict input validation and prompt explanations. | Repo, NTFS USB root, Ventoy partition, secondary clone. | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/post-backup-wizard.sh`** | Post-backup diagnostic inspector, automated log locator, and bundle exporter. | Repo, NTFS USB root, Ventoy partition, secondary clone. | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/mount_home40_backup.sh`** | Standalone network mount helper for `192.168.1.34:/media/alan/home40/Clonezilla`. | Repo, NTFS USB root. | Committed (`1c0b0c0`), Pushed to `origin/main` |
| **`Ventoy/disk_geometry_sdb_zbook.txt`** | Exact `sfdisk` sector boundaries, UUIDs, and partition layouts for `/dev/sda` and `/dev/sdb`. | Repo, secondary clone. | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/Ventoy_Core_Backup_2026-09-02_manifest.txt`** | Detailed manifest of the successful 23 GB Clonezilla backup with restoration commands. | Repo, secondary clone. | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/ventoy_config/ventoy.json`** | Persistence mapping for Rescuezilla and SuperGrub menu alias. | Repo, Ventoy partition (`/ventoy/ventoy.json`). | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/ventoy_config/ventoy_grub.cfg`** | Custom `F6` boot menu entries for `Ubuntu-USB-Ventoy` (`sdb3`) and Windows (`sda`). | Repo, Ventoy partition (`/ventoy/ventoy_grub.cfg`). | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/persistence_startup/mount_ntfs_startup.sh`** | Live persistence startup script to auto-mount NTFS and link `~/ntfs_usb`. | Repo, deployed inside `rescuezilla-persistence.dat`. | Committed (`7567f92`), Pushed to `origin/main` |
| **`Ventoy/persistence_startup/*.desktop`** | Autostart entry and desktop shortcuts for CLI backup and diagnostics wizards. | Repo, deployed inside `rescuezilla-persistence.dat`. | Committed (`7567f92`), Pushed to `origin/main` |
| **`/media/devmon/Ventoy/rescuezilla-persistence.dat`** | Clean, verified 512 MB ext4 persistence overlay filesystem (`e2fsck` verified 0 errors). | Ventoy partition (`/dev/sdb1`). | Active Binary on Flash |
| **`/etc/default/grub`** | Configured `GRUB_DISTRIBUTOR="Ubuntu-USB-Ventoy"`. | Installed Linux OS (`/dev/sdb3`). | Active OS Config |
| **`/home/alan/ntfs_usb/latest_backup.env`** | Shared session state file passed between CLI backup runner and diagnostic wizard. | NTFS USB partition (`/dev/sdb4`). | Operational State |

---

## 3. Standard Operating Procedures (Quick Reference)

### SOP 1: Booting the Installed OS on ZBook
1. Insert the USB drive and power on the ZBook.
2. When the Ventoy screen appears, press **`F6`**.
3. Select **`🟢 Boot Installed Ubuntu 22.04 LTS (Ubuntu-USB-Ventoy on /dev/sdb3)`** and hit Enter.

### SOP 2: Backing Up the Internal PC (Windows 11)
1. Boot into Rescuezilla Live or stay in the current live environment.
2. Open a terminal and run:
   ```bash
   sudo bash /media/*/*/run_rescuezilla_backup_cli.sh
   ```
   *(Or click the desktop launcher `🚀 Run Backup Assistant (CLI)` if in Rescuezilla Live).*
3. Select:
   * Target Drive: `[1] /dev/sda (Internal 1TB Drive)`
   * Scope: `[1] Windows 11 Only: sda1 + sda2 [Recommended]`
   * Engine: `[1] Clonezilla Native Engine (ocs-sr)`
4. Type `y` to confirm when prompted.

### SOP 3: Using Rescuezilla with Persistent Storage
1. At the Ventoy menu, select `rescuezilla-2.6.2-64bit.noble.iso`.
2. Select **`Boot with /rescuezilla-persistence.dat`**.
3. On desktop load, the NTFS partition will auto-mount at `/media/ubuntu/2C95D29B2DF0500E`, desktop shortcuts will appear, and all changes will persist across reboots.
