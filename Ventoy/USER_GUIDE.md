# User Guide: Booting, NTFS Partition Mounting, Backup & Error Investigation

**Environment:** HP EliteBook / ZBook / Linux Live USB (Rescuezilla / Clonezilla / Ventoy)  
**Target Architecture:** Legacy MBR / BIOS & Multiboot USB (`/dev/sdb`), Local Storage (`/dev/sda`), Network Share (`192.168.1.34`)

---

## Table of Contents
1. [Boot Configuration & Ventoy Multiboot](#1-boot-configuration--ventoy-multiboot)
2. [Mounting NTFS Partitions & Resolving Lock/Dirty Flags](#2-mounting-ntfs-partitions--resolving-lockdirty-flags)
3. [Backup Workflows (CLI & GUI)](#3-backup-workflows-cli--gui)
4. [Error Investigation & Diagnostic Toolkit](#4-error-investigation--diagnostic-toolkit)
5. [Quick Reference Cheat Sheet](#5-quick-reference-cheat-sheet)

---

## 1. Boot Configuration & Ventoy Multiboot

### HP EliteBook / ZBook BIOS Settings
When configuring or troubleshooting boot on HP EliteBook / ZBook machines, ensure the following configuration in the BIOS Setup Utility (`F10` during startup):

| BIOS Option | Setting | Explanation |
| :--- | :--- | :--- |
| **Customized Boot** | `Enabled` | Allows custom boot configurations and device priority overrides. |
| **SecureBoot** | `Disabled` | Allows booting unsigned live kernels, rescue ISOs, and custom OS builds without enrolling MOK keys. |
| **Key Mode** | `HP Factory Keys` | Default cryptographic key storage state. |
| **Boot Mode** | `Legacy` | Enforces traditional Master Boot Record (MBR) partition booting. |
| **UEFI Mode** | `Disabled` | Disables UEFI Native and UEFI Hybrid with CSM. |
| **UEFI Boot Order** | `Inactive` | Greyed out because Legacy mode is active. |

> [!IMPORTANT]
> Under **Legacy Boot Mode**, the system exclusively executes the MBR bootstrap code located in **Sector 0** of the drive. GPT-only drives without legacy protective MBR loaders will not boot.

---

### Multiboot Layout on the Ventoy USB (`/dev/sdb`)
A typical multi-partition setup on the USB drive includes:

* **`sdb1` (ExFAT, ~19 GB):** Ventoy primary data partition (holds ISOs, scripts, and `ventoy_grub.cfg`).
* **`sdb2` (FAT16, 32 MB):** `VTOYEFI` (Ventoy EFI binaries and GRUB core modules).
* **`sdb3` (Ext4, ~19 GB):** Full installed Ubuntu Linux OS.
* **`sdb4` (NTFS, ~81 GB):** General high-capacity NTFS data and backup staging partition.

### Restoring Ventoy MBR if Overwritten by Ubuntu Updates
If an `apt upgrade` or `grub-pc` update on `sdb3` accidentally overwrites Sector 0 (causing the system to bypass the Ventoy ISO menu and boot directly into Ubuntu):

1. **Unmount Ventoy partitions:**
   ```bash
   udisksctl unmount -b /dev/sdb1 2>/dev/null
   udisksctl unmount -b /dev/sdb2 2>/dev/null
   ```
2. **Execute non-destructive in-place Ventoy update (`-u` flag):**
   ```bash
   sudo ./Ventoy2Disk.sh -u /dev/sdb
   ```
   *(Always use `-u` (update), NEVER `-i` (install), so your ISOs, partitions, and data are untouched).*

### Booting the Installed OS (`sdb3`) from the Ventoy Screen
* **Custom Menu (F6):** Press `F6` at the Ventoy boot menu to load `/ventoy_grub.cfg` and select **Boot Installed Ubuntu 22.04 LTS**.
* **Direct Scanner (F4):** Press `F4` to run Ventoy's native **Search & Boot Local OS** engine.

---

## 2. Mounting NTFS Partitions & Resolving Lock/Dirty Flags

### The Problem: Read-Only NTFS Mounts & `OSError: [Errno 30]`
When Windows shuts down with **Fast Startup** (hybrid hibernation) enabled, or after an improper shutdown, the NTFS filesystem is flagged with a **dirty / hibernated bit**. When booted into a Linux live environment (like Rescuezilla), the Linux kernel automatically mounts the NTFS partition as **Read-Only** to prevent data corruption. Any attempt to write backups, logs, or files to it will fail.

### Step 1: Repair / Clear NTFS Dirty Flags in Linux
To safely reset the logfile and clear the dirty/inconsistent state on an NTFS drive:

```bash
# Example for partition /dev/sda2 or /dev/sdb4
sudo ntfsfix -d /dev/sdXn
```
* `-d`: Clears the dirty flag and forces Windows to run chkdsk on next boot if necessary.
* `-b`: Clears bad sector flags (optional).

*(For ExFAT partitions like `sdb1`, use `sudo fsck.exfat -a /dev/sdb1`).*

### Step 2: Manual Read-Write Mounting
Once the dirty flag is cleared:

```bash
# 1. Create mount target directory
sudo mkdir -p /mnt/ntfs_data

# 2. Mount with read-write permissions
sudo mount -t ntfs-3g -o rw,uid=1000,gid=1000,umask=0022 /dev/sdXn /mnt/ntfs_data

# 3. Verify read-write functionality
touch /mnt/ntfs_data/.write_test && rm -f /mnt/ntfs_data/.write_test && echo "✓ NTFS Read-Write Confirmed"
```

### Step 3: Clean Unmounting
Before unplugging or rebooting, always flush buffers and cleanly unmount:
```bash
sync
sudo umount /mnt/ntfs_data
```

---

## 3. Backup Workflows (CLI & GUI)

### A. Automated Command-Line Backup (`run_rescuezilla_backup_cli.sh`)
This runner script handles SSH key verification, remote SSHFS mounting, drive/partition discovery, execution, logging, and error trapping.

#### How to Run:
```bash
sudo bash run_rescuezilla_backup_cli.sh
```

#### Workflow:
1. **Network Mount:** Automatically mounts remote backup target (`192.168.1.34:/media/alan/home40/Clonezilla`) to `/mnt/backup` via SSH key authentication (`id_rsa`).
2. **Drive Selection:**
   * `[1] /dev/sda` — Internal 1TB Drive (Windows 11 OS + Data).
   * `[2] /dev/sdb` — USB Drive (Ventoy + Installed Linux).
3. **Partition Scope:**
   * Windows 11 only: `sda1` (System Reserved) + `sda2` (OS partition).
   * Full Drive: All partitions.
   * Custom Selection: Space-separated partition list.
4. **Engine Selection:**
   * **Clonezilla Native (`ocs-sr`)** *(Recommended)*: Uses Partclone directly with multi-threaded gzip compression.
   * **Rescuezilla Engine (`rescuezillapy`)**: Runs Python-driven partition imaging.
5. **Telemetry Export:** Automatically writes `${SCRIPT_DIR}/latest_backup.env` and creates a symlink `latest_backup.log`.

---

### B. Rescuezilla GUI Backup Workflow
If using the graphical Rescuezilla application:

1. **Step 1 - Operation:** Click **Backup**.
2. **Step 2 - Source Drive:** Select source drive (e.g., `/dev/sda` or `/dev/sdb`) and choose desired partitions.
3. **Step 3 - Destination Type:**
   * Select **"Shared over a network"** *(Do NOT select "Connected directly to my computer" for network shares)*.
4. **Step 4 - Network Protocol:**
   * **Protocol:** Select **SSH**.
   * **Server:** `192.168.1.34`
   * **Remote Path:** `/media/alan/home40/Clonezilla`
   * **Username:** `alan`
   * **Password:** *(Leave blank)*
   * **SSH Identity File:** Click browse and point to `id_rsa` on your NTFS USB partition (`sdb4`).
5. **Step 5 - Compression & Launch:** Select `gzip` or default compression and click **Start Backup**.

---

## 4. Error Investigation & Diagnostic Toolkit

### Post-Backup Diagnostic Wizard (`post-backup-wizard.sh`)
Run this tool immediately after any backup or whenever a process reports an error:

```bash
sudo bash post-backup-wizard.sh [optional_path_to_log]
```

### Wizard Menu Capabilities:
* **`[1]` Inspect Error Summary & Root Cause:** Scans logs with strict regex filters to isolate fatal I/O errors, corruption, or missing device blocks while stripping benign GRUB/udev noise.
* **`[2]` Export Diagnostic Bundle to NTFS:** Packages session logs, `dmesg -T` (kernel events), `journalctl -b`, `lsblk`, `fdisk -l`, `df -h`, and SMART disk logs into a timestamped directory on the NTFS data drive.
* **`[3]` Save to Persistent Home Directory:** Saves the full bundle to `~/saved_logs`.
* **`[4]` Export via SSH / SCP:** Transmits diagnostic bundles across the LAN to a remote server.
* **`[5]` SMART Drive Health Telemetry:** Queries disk controllers using `smartctl -H` to verify drive hardware health.

---

### Common Errors & Solutions Matrix

| Error Message / Symptom | Root Cause | Resolution |
| :--- | :--- | :--- |
| **`can't find command 'vt_clean_key'` / `No ISO found`** | Standard GRUB loaded instead of Ventoy GRUB; missing Ventoy C modules. | Run `sudo ./Ventoy2Disk.sh -u /dev/sdX` to restore Ventoy MBR in Sector 0. |
| **`OSError: [Errno 30] Read-only file system`** | NTFS partition was locked by Windows Fast Startup or unmounted uncleanly. | Run `sudo ntfsfix -d /dev/sdXn` and remount with `-o rw`. |
| **`sshfs: read: Connection reset by peer`** | Password authentication / `sshpass` rejected or throttled by remote SSH server. | Use SSH Key authentication (`id_rsa` with `chmod 600`) instead of passwords. |
| **`input/output error` / `bad block`** | Underlying storage sector degradation or failing drive controller. | Check drive with `sudo smartctl -a /dev/sdX` and inspect `dmesg -T \| grep -i ata`. |
| **Rescuezilla GUI cannot see `/mnt/backup`** | GUI "Connected directly" only queries block devices via `lsblk`, ignoring virtual mount points. | Use the CLI script `run_rescuezilla_backup_cli.sh` or select "Shared over a network" in GUI. |

---

## 5. Quick Reference Cheat Sheet

```bash
# --- 1. BOOT & MBR REPAIR ---
sudo ./Ventoy2Disk.sh -u /dev/sdb               # Non-destructive Ventoy MBR repair

# --- 2. NTFS FIX & MOUNT ---
sudo ntfsfix -d /dev/sdb4                       # Clear NTFS dirty/hibernation bit
sudo mkdir -p /mnt/ntfs_data                    # Create mount point
sudo mount -t ntfs-3g -o rw /dev/sdb4 /mnt/ntfs_data # Mount Read-Write

# --- 3. RUN BACKUP CLI ---
sudo bash run_rescuezilla_backup_cli.sh          # Full automated backup runner

# --- 4. RUN DIAGNOSTIC WIZARD ---
sudo bash post-backup-wizard.sh                 # Inspect logs and export diagnostic bundle

# --- 5. DRIVE HEALTH CHECK ---
sudo smartctl -H /dev/sda                       # Check health status of internal drive
sudo smartctl -H /dev/sdb                       # Check health status of USB drive
```
