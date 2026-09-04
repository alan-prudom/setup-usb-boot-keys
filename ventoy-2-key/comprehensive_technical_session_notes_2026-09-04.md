# Comprehensive Technical Session Notes: Disk Audit, Snap Pruning, Rescuezilla Persistence Repair & Storage Automation

**Author / Session Lead:** Alan P & Assistant  
**Date of Record:** September 4, 2026  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Storage Configuration:**  
* Target Drive 1 (Internal): 1 TB SSD/HDD (`/dev/sda`)
* Target Drive 2 (Booted USB): 128 GB SanDisk Multi-Boot USB (`/dev/sdb`, Ventoy 2)  
* Target Drive 3 (Remote Network): HP EliteBook (`alan@192.168.1.34:/media/alan/home40`)  
**Sub-Repository:** `ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/`

---

## 1. Executive Summary

This session addressed four interrelated system-level requirements on the HP ZBook multi-boot environment:
1. **Snap Runtime Pruning & Optimization:** Audited all active and disabled snap packages and identified core bases and runtimes to recover disk space on the 19 GB USB rootfs (`/dev/sdb3`).
2. **Deep Storage & Partition Investigation:** Resolved why the large internal 608 GB Linux partition (`/dev/sda5`) was unmounted, verified partition table health, and mapped the exact physical and network locations of all Git repositories.
3. **Rescuezilla Persistence Failure Resolution:** Diagnosed why persistent boot into Rescuezilla failed to mount the 82 GB FAT storage partition (`/dev/sdb4`) and showed an empty desktop. Implemented the Four-Tier Redundancy Architecture directly into `rescuezilla-persistence.dat`.
4. **Automated Remote Workspace Mounting (`home40`):** Created and enabled a persistent systemd user service (`mount-home40.service`) to auto-mount remote Git repositories via SSHFS on startup.
5. **Version Control Integration & Documentation Alignment:** Preserved all conversational artifacts, shell scripts, and system specifications in `ventoy-2-key/` with fine-grained documentation updates.

---

## 2. Topic 1: Snap Runtime Pruning & Base Audit

### 2.1 Problem & Objectives
The booted USB operating system operates on a 19 GB ext4 root partition (`/dev/sdb3`), where storage headroom is critical. Multiple disabled revisions and potentially redundant GNOME and Ubuntu core runtime snaps were consuming space.

### 2.2 Findings & Dependency Mapping
A deep audit of snap connections (`snap connections`) and snap metadata revealed the dependency tree:

| Snap Runtime / Base | Version / Rev | Dependent Packages | Safe Removal Decision |
| :--- | :--- | :--- | :--- |
| **`core18`** | 20260204 / 2999 | `gnome-3-28-1804` (which is required by `bitwarden`) | **Must Keep** (Required) |
| **`core20`** | 20260410 / 2866 | *(none)* | **Safe to Remove** |
| **`core22`** | 20260225 / 2411 | `bitwarden` base | **Must Keep** (Required) |
| **`core24`** | 20260410 / 1643 | `firefox`, `mesa-2404` | **Must Keep** (Required) |
| **`gnome-3-28-1804`** | 3.28.0 / 198 | `bitwarden` | **Must Keep** (Required) |
| **`gnome-3-38-2004`** | 0+git / 143 | *(none)* | **Safe to Remove** (Orphan) |
| **`gnome-42-2204`** | 0+git / 263 | `snap-store` only | **Safe to Remove** (if snap-store is removed) |
| **`gnome-46-2404`** | 0+git / 153 | `firefox`, `snapd-desktop-integration` | **Must Keep** (Required) |
| **`snap-store`** | 41.3 / 1216 | Redundant with CLI snap management | **User Requested Removal** |

### 2.3 Executed Actions
* Removed disabled snap revisions.
* Isolated safe removals: `snap-store`, `gnome-3-38-2004`, `gnome-42-2204`, and `core20`.

---

## 3. Topic 2: Hard Drive Partition & Git Repositories Investigation

### 3.1 Partition Layout Audit (`/dev/sda` vs `/dev/sdb`)
The system was inspected via `lsblk -b -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT`:

1. **Internal 1 TB Drive (`/dev/sda`):**
   * `/dev/sda1` (600 MB, NTFS): `System Reserved`
   * `/dev/sda2` (142 GB, NTFS): Windows System OS
   * `/dev/sda3` (111 GB, NTFS): `Data` partition
   * **`/dev/sda5` (608 GB / ~558 GB ext4, UUID `26448526-203a-40ab-ae59-980a7d107903`):** Internal Linux OS installation (Ubuntu).
2. **Booted 128 GB SanDisk USB (`/dev/sdb`):**
   * `/dev/sdb1` (20 GB, exFAT, `Ventoy`): Bootloader & ISO collection.
   * `/dev/sdb2` (32 MB, FAT16, `VTOYEFI`): EFI binaries.
   * `/dev/sdb3` (19 GB, ext4): Booted Ubuntu 22.04 LTS OS root (`/`).
   * `/dev/sdb4` (82 GB, FAT32 / vfat, `SHARED FAT`, UUID `C9D1-3C83`): Shared data partition mounted at `/ntfs`.

### 3.2 Root Cause: Why `/dev/sda5` Did Not Mount
* Fixed internal drives are not mounted automatically by live environments or secondary USB-installed systems without explicit entries in `/etc/fstab` or automated user-space mount commands.
* **Integrity Status:** Partition `/dev/sda5` is fully healthy. Testing mounts via `udisksctl mount -b /dev/sda5` confirmed clean access at `/media/alan/26448526-203a-40ab-ae59-980a7d107903/` with 429 GB used and 101 GB free.

### 3.3 Git Repository Register
A filesystem search mapped all Git repositories across drives:
* **Internal Drive (`/dev/sda5/home/alan/`):**
  * `GitHub/JD-and-ZK-tools`
  * `GitHub/ap-devices-and-pcs` (with extensive sub-devices: `ap-zbook-setup`, `run_mosh`, `setup-usb-boot-keys`, etc.)
  * `projects/` (`evernote-dump`, `_git/TDDProject1`, `Note-Systems`, `app1`, `remi-from-github`)
  * `ZKGIT/` (`ZK`, `JoplinGit`, `Foam-ZK`)
* **Shared USB Partition (`/ntfs/`):**
  * `/ntfs/From portable 5/Ventoy-git-project`
* **Current USB Environment (`/home/alan/`):**
  * Symlink `/home/alan/GitHub -> /home/alan/mnt/apelite/files_zbook/GitHub` (points to network host `home40`).

---

## 4. Topic 3: Rescuezilla Persistence & Storage Auto-Mount Failure

### 4.1 Root Cause Diagnosis
When booting Rescuezilla with persistence enabled via Ventoy:
1. **Empty `casper-rw` Container:** File `/media/alan/Ventoy1/rescuezilla-persistence.dat` contained only 11 inodes (unconfigured initial state).
2. **Openbox Window Manager Incompatibility:** Rescuezilla uses Openbox instead of GNOME or XFCE. XDG `.desktop` files in `~/.config/autostart/` are completely ignored by Openbox. Commands must be placed in `~/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
3. **Status 127 ("File Not Found") Collision:** Desktop launchers pointing to `/home/ubuntu/ntfs_usb/run_rescuezilla_backup_cli.sh` failed with exit code 127 whenever the partition was delayed or failed to mount.
4. **Filesystem / UUID Divergence:** Previous scripts assumed an NTFS filesystem with UUID `2C95D29B2DF0500E`. The actual partition `/dev/sdb4` is FAT32 (`UUID=C9D1-3C83`, `LABEL="SHARED FAT"`).

### 4.2 Four-Tier Redundancy Architecture Deployed
The architecture was deployed to `rescuezilla-persistence.dat` via `deploy_four_tier_persistence.sh`:

1. **Tier 1 (Embedded Root Binaries):**
   * Installed `run_rescuezilla_backup_cli.sh` and `post-backup-wizard.sh` into `/scripts/` and symlinked to `/usr/local/bin/`.
   * **Result:** Tools are 100% self-contained on the root overlay; zero partition mounting dependencies.
2. **Tier 2 (Storage Auto-Mounting Automation):**
   * Created `/usr/local/bin/mount_storage_startup.sh`.
   * Mounts `SHARED FAT` (`UUID=C9D1-3C83`) at `/media/ubuntu/SHARED_FAT` with `uid=1000,gid=1000,umask=000` (full user permissions).
   * Mounts internal HDD Linux partition `/dev/sda5` read-only at `/media/ubuntu/Internal_HDD` (prevents data contamination during backup runs).
3. **Tier 3 (Openbox-Native Autostart):**
   * Registered `/usr/local/bin/mount_storage_startup.sh &` in `/home/ubuntu/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
4. **Tier 4 (Desktop Launchers with Window Retention):**
   * Installed `Run_Backup_CLI.desktop` and `Post_Backup_Wizard.desktop` onto `/home/ubuntu/Desktop/` with `--hold` terminal retention.
   * Installed `id_rsa` to `/home/ubuntu/.ssh/id_rsa` and `/scripts/id_rsa` (`chmod 600`).

---

## 5. Topic 4: Automated Remote Workspace Mounting (`home40`)

### 5.1 Requirement
The symlink `/home/alan/GitHub -> /home/alan/mnt/apelite/files_zbook/GitHub` was disconnected on boot because `sshfs` in `/etc/fstab` did not automatically initialize across network state changes.

### 5.2 Implementation
Created and activated a user-level systemd service:
* **Service Unit:** `/home/alan/.config/systemd/user/mount-home40.service`
* **Configuration:**
  ```ini
  [Unit]
  Description=SSHFS Mount home40 for Git Folders
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=forking
  ExecStartPre=/bin/mkdir -p /home/alan/mnt/apelite
  ExecStart=/usr/bin/sshfs -o idmap=user,follow_symlinks,identityfile=/home/alan/.ssh/id_rsa,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 alan@192.168.1.34:/media/alan/home40 /home/alan/mnt/apelite
  ExecStop=/bin/fusermount -u /home/alan/mnt/apelite
  Restart=on-failure
  RestartSec=10
  RemainAfterExit=yes

  [Install]
  WantedBy=default.target
  ```
* **Validation:** Verified active and loaded (`systemctl --user status mount-home40.service`). The repository path `~/GitHub/ap-devices-and-pcs` is fully accessible.

---

## 6. Detailed File Changes Register

| File Path | Description of Changes | Target Destination(s) |
| :--- | :--- | :--- |
| `ventoy-2-key/mount_fat_and_hdd.sh` | Shell script to discover and mount `SHARED FAT` (`UUID=C9D1-3C83`) and `/dev/sda5` (read-only). | Repo, `/ntfs/scripts/`, `/media/alan/Ventoy1/scripts/` |
| `ventoy-2-key/mount-home40.service` | Systemd user service unit for resilient SSHFS connection to `home40`. | Repo, `~/.config/systemd/user/` |
| `ventoy-2-key/setup_rescuezilla_persistence.sh` | Standalone script for loop-mounting and initial population of `rescuezilla-persistence.dat`. | Repo, `/ntfs/scripts/`, `/media/alan/Ventoy1/scripts/` |
| `ventoy-2-key/deploy_four_tier_persistence.sh` | Master deployment tool injecting Tier 1-4 redundancy into the persistence overlay. | Repo, `/ntfs/scripts/`, `/media/alan/Ventoy1/scripts/` |
| `ventoy-2-key/session_notes_persistence_and_home40_mount.md` | Summary documentation of persistence repair and SSHFS service setup. | Repo |
| `ventoy-2-key/README.md` | Updated metadata status date to Sept 4, 2026 and appended Section 6 specification. | Repo |
| `ventoy-2-key/comprehensive_technical_session_notes_2026-09-04.md` | This document; full narrative and technical reference of all session decisions and actions. | Repo |

---

## 7. Verification & Operational Instructions

### 7.1 Booting Rescuezilla via Ventoy
1. Reboot and select the USB drive.
2. In the Ventoy menu, select **`>>> Rescuezilla 2.6.1 Live GUI (+Persistence)`**.
3. Choose **Boot with persistence**.
4. Upon desktop initialization:
   * `mount_storage_startup.sh` executes via Openbox autostart.
   * `SHARED_FAT_Storage` and `Internal_HDD` shortcuts appear on `/home/ubuntu/Desktop`.
   * `Run_Backup_CLI` and `Post_Backup_Wizard` desktop shortcuts execute directly with terminal hold.

### 7.2 Normal Booting into USB Ubuntu 22.04 LTS
1. At the Ventoy menu, press **`F6`** (or select installed Ubuntu on `/dev/sdb3`).
2. The system boots into the installed USB OS.
3. `mount-home40.service` initializes on user login, mounting `home40` at `~/mnt/apelite`.
4. `~/GitHub` resolves immediately to all active repositories.
