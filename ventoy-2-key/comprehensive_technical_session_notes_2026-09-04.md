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
| `ventoy-2-key/troubleshooting_persistence_and_usb_boot_hang.md` | Root cause analysis and fixes for Rescuezilla persistence label (`casper-rw` -> `writable`) and USB Ubuntu Xorg display crash. | Repo |
| `ventoy-2-key/ventoy_grub.cfg` | Added Safe Graphics (`nomodeset`) and Text Console (`systemd.unit=multi-user.target`) recovery stanzas. | Repo, `/media/alan/Ventoy/` |
| `ventoy-2-key/verify_ventoy2.sh` | Added test for persistence container volume label 'writable'. | Repo |
| `ventoy-2-key/README.md` | Updated persistence label spec to `writable` and added Section 4.2 fallback recovery stanzas. | Repo |
| `ventoy-2-key/comprehensive_technical_session_notes_2026-09-04.md` | This document; full narrative and technical reference of all session decisions and actions. | Repo |

---

## 7. Topic 5: Rescuezilla Persistence Relabeling (`writable`) & USB Ubuntu Hang Resolution

### 7.1 Rescuezilla Persistence Label Upgrade
* **Background & Problem:** After deploying the Four-Tier Redundancy scripts, Rescuezilla 2.6.1 booted with persistence still showed an unmounted storage environment and did not retain changes across reboots.
* **Technical Root Cause:**
  1. `rescuezilla-2.6.1-64bit.oracular.iso` is built on Ubuntu 24.10 (Oracular Oriole).
  2. In modern Ubuntu live releases (Ubuntu 20.04+, and specifically 24.04/24.10), Casper deprecated the historical volume label `casper-rw` and requires persistent ext4 overlay filesystems to be labeled **`writable`**.
  3. `rescuezilla-persistence.dat` on Partition 1 (`/dev/sdb1`) was originally formatted with `LABEL="casper-rw"`. As a result, Casper skipped the persistence container during initramfs discovery and loaded purely into RAM.
* **Actions Taken:**
  1. Ran `/sbin/e2label /media/alan/Ventoy/rescuezilla-persistence.dat writable`.
  2. Verified filesystem with `blkid`:
     ```text
     /media/alan/Ventoy/rescuezilla-persistence.dat: LABEL="writable" UUID="309a9e74-4230-458f-b89e-c492dcd3506f" TYPE="ext4"
     ```
  3. Updated `verify_ventoy2.sh` to add an automated test verifying the persistence container volume label is `writable`.

### 7.2 USB Ubuntu Boot Hang & GDM / Xorg Crash
* **Background & Problem:** When booting the installed Ubuntu 22.04 LTS OS on the USB key via the Ventoy custom menu (**`F6`**), the boot process hung indefinitely before the login desktop appeared.
* **Investigation & Startup Log Audit:**
  Inspected `/var/log/boot.log` and `/var/log/syslog` from the USB root filesystem (`/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/`):
  1. **Remote Filesystem (`home40` / SSHFS):**
     - The entry `alan@192.168.1.34:/media/alan/home40` in `/etc/fstab` utilized `x-systemd.automount,_netdev`.
     - Systemd successfully set up the automount socket without blocking boot. However, background services (`gvfs-udisks2-volume-monitor`, `pool`) repeatedly queried the directory while offline, throwing continuous `status=1/FAILURE` error loops.
  2. **Display Server Fatal Crash (GDM3 / Xorg):**
     - The real hang was caused by a fatal Xorg display server crash.
     - When GDM launched `/usr/libexec/gdm-x-session`, hardware acceleration was attempted via Modesetting + Glamor/EGL on the Intel GPU (`/dev/dri/card1`).
     - `glamor_egl_init` crashed in `gbm_create_device` through `libLLVM-15.so.1`:
       ```text
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) Backtrace:
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 0: /usr/lib/xorg/Xorg (OsLookupColor+0x139)
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 1: /lib/x86_64-linux-gnu/libc.so.6 (__sigaction+0x50)
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 2: /lib/x86_64-linux-gnu/libLLVM-15.so.1
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 20: /lib/x86_64-linux-gnu/libgbm.so.1 (gbm_create_device+0x48)
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 21: /usr/lib/xorg/modules/libglamoregl.so (glamor_egl_init+0x67)
       alan-USB-zbook /usr/libexec/gdm-x-session[1257]: Fatal server error: (EE) Server terminated with error (1)
       alan-USB-zbook gdm3: Gdm: GdmLocalDisplayFactory: maximum number of X display failures reached: check X server log for errors
       ```
     - After multiple crash iterations, GDM reached its failure threshold and aborted, leaving the console frozen at Plymouth or a black screen.
* **Actions Taken:**
  1. **Cleaned `/etc/fstab`:** Removed the redundant SSHFS mount line from `/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/etc/fstab` (backed up to `fstab.bak`). Remote storage is now cleanly and solely managed after login by `~/.config/systemd/user/mount-home40.service`.
  2. **GDM Configuration:** Explicitly configured `WaylandEnable=false` in `/etc/gdm3/custom.conf` on the USB partition.
  3. **Resilient F6 Recovery Menu Stanzas (`ventoy_grub.cfg`):**
     Added two fallback entries to `ventoy_grub.cfg` (synced to both the repo and `/media/alan/Ventoy/`):
     - `🟢 Direct Linux Kernel Boot - Safe Graphics (nomodeset)`: Boots the full OS and desktop using software rendering / standard framebuffer without Intel KMS acceleration.
     - `🟢 Direct Linux Kernel Boot - Text Console (systemd.unit=multi-user.target)`: Boots directly into a text TTY console without loading GDM/Xorg, allowing user login and recovery commands (`sudo systemctl start gdm3` or `startx`).

---

## 8. Verification & Operational Instructions

### 8.1 Booting Rescuezilla via Ventoy
1. Reboot and select the USB drive via the BIOS/UEFI boot menu (`F9`).
2. In the Ventoy menu, select **`>>> Rescuezilla 2.6.1 Live GUI (+Persistence)`**.
3. Choose **Boot with persistence**.
4. Upon desktop initialization:
   * Casper loads and commits root overlay writes to `rescuezilla-persistence.dat` (labeled `writable`).
   * `mount_storage_startup.sh` executes via Openbox autostart.
   * `SHARED_FAT_Storage` and `Internal_HDD` shortcuts appear on `/home/ubuntu/Desktop`.
   * `Run_Backup_CLI` and `Post_Backup_Wizard` desktop shortcuts execute directly with terminal hold.

### 8.2 Normal & Recovery Booting into USB Ubuntu 22.04 LTS
1. At the Ventoy menu, press **`F6`**.
2. Select your boot method:
   * **`🟢 Boot Installed Ubuntu 22.04 LTS`**: Standard chainload of GRUB.
   * **`🟢 Direct Linux Kernel Boot - Safe Graphics (nomodeset)`**: Direct kernel boot with software rendering fallback if Intel GPU modesetting / Glamor fails. Directly displays the graphical login screen.
   * **`🟢 Direct Linux Kernel Boot - Text Console`**: Boots directly into a multi-user text terminal (`systemd.unit=multi-user.target`).
     * From the text console, log in as `alan`.
     * Start the graphical desktop with: `sudo systemctl start gdm3` or run a direct X session with `startx`.
3. Once logged in, `mount-home40.service` initializes automatically, mounting `home40` at `~/mnt/apelite`.
4. `~/GitHub` resolves immediately to all active repositories.

---

## 9. Topic 6: Persistence Overlay Forensics, Casper OverlayFS Architecture & Script Ecosystem Alignment

### 9.1 Problem & User Observation
During live testing of Rescuezilla 2.6.1 Live (+Persistence) on Ventoy 2, three specific anomalies were encountered:
1. **Perceived Persistence Failure:** The desktop loaded in its stock state without custom launchers (`Run_Backup_CLI`, `Post_Backup_Wizard`) or storage links, and the 87 GB FAT partition (`/dev/sdb4`) was not mounted automatically.
2. **Missing Operational Scripts:** After manually mounting `/dev/sdb4` (at `/media/ubuntu/SHARED FAT`), navigating to `/scripts/` revealed none of the expected Clonezilla runners (`run_rescuezilla_backup_cli.sh`, `sda_rescue_backup.sh`) or post-mortem diagnostic tools (`post-backup-wizard.sh`).
3. **Unrelated Peripheral Scripts:** Only `run_mosh/`, `tailscale_setup.sh`, `deploy_four_tier_persistence.sh`, and `mount_fat_and_hdd.sh` were present on the FAT drive, causing confusion.

### 9.2 Forensic Evidence Audit
1. **User Screenshot Audit (`/ntfs/Screenshot_2026-09-04_18-59-37.png`):**
   - Verified GNOME Disks (`gnome-disks`) captured inside the Rescuezilla live session at 18:59:37.
   - Showed `/dev/sdb4` (87 GB FAT32, `SHARED FAT`, UUID `C9D1-3C83`) unmounted with the Play (Mount) icon active.
   - Revealed active `nbd` devices (`/dev/nbd0` through `/dev/nbd15`), confirming Rescuezilla execution.
2. **Persistence Container Logs (`/upper/var/log/syslog` & `/upper/root/.bash_history`):**
   - **Kernel Mount Confirmed:** At `18:54:49`, the kernel mapped `rescuezilla-persistence.dat` as `dm-1` (`vtoy_persistent`) and mounted the ext4 filesystem (`UUID=309a9e74-4230-458f-b89e-c492dcd3506f`) read-write.
   - **Manual User Mount:** At `18:59:19`, `udisksd` mounted `/dev/sdb4` to `/media/ubuntu/SHARED FAT` on behalf of UID 1000.
   - **Execution of Helper:** At `19:02:38`, root executed `mount_fat_and_hdd.sh`, which mounted `/dev/sda5` read-only.

### 9.3 The Casper OverlayFS Invisibility Mechanism
* **Root Cause:** Modern Ubuntu Casper (Ubuntu 24.10 / Rescuezilla 2.6.1) constructs its live root filesystem using Linux **OverlayFS**:
  $$\text{Rootfs} = \text{OverlayFS}(\text{lowerdir}=\text{/rofs}, \; \text{upperdir}=\text{/cow/upper}, \; \text{workdir}=\text{/cow/work})$$
* The physical persistence container (`rescuezilla-persistence.dat`) is mounted by Casper at `/cow`.
* The earlier deployment script placed files directly into `$MNT/scripts/`, `$MNT/usr/local/bin/`, and `$MNT/home/ubuntu/Desktop/` (which correspond to `/cow/scripts/`, `/cow/home/ubuntu/Desktop/`).
* **Result:** Because the live rootfs exclusively displays files residing in `/cow/upper/`, all files outside `/upper/` were completely hidden from the running desktop and init process.

### 9.4 Architectural Fixes Deployed
1. **Dual-Target OverlayFS Deployment (`deploy_four_tier_persistence.sh`):**
   - Rewrote deployment logic to inject binaries, launchers, and configurations into both `$MNT/upper/` (for live OverlayFS) and `$MNT/` (for raw fallback).
   - Implemented triple-redundant storage auto-mounting:
     * **Layer A (Systemd Service):** `/upper/etc/systemd/system/mount-storage-startup.service` enabled in `multi-user.target.wants/` to mount storage before user login.
     * **Layer B (XDG Autostart):** `/upper/etc/xdg/autostart/mount-storage-startup.desktop`.
     * **Layer C (Openbox Native):** Added startup triggers to `/upper/home/ubuntu/.config/openbox/autostart`, `autostart.sh`, and `/upper/etc/xdg/openbox/autostart`.
   - Deployed desktop launchers with `--hold` retention to `/upper/home/ubuntu/Desktop/` (`Run_Backup_CLI.desktop`, `Post_Backup_Wizard.desktop`, `Mount_Storage.desktop`).
   - Synchronized `id_rsa` into `/upper/scripts/id_rsa` and `/upper/home/ubuntu/.ssh/id_rsa` (`chmod 600`).
2. **FAT Partition & Ventoy P1 Script Ecosystem Alignment:**
   - Copied all core backup scripts from `Ventoy/` to `/ntfs/scripts/` and `/media/alan/Ventoy1/scripts/`:
     * `run_rescuezilla_backup_cli.sh` (Interactive Clonezilla / Rescuezilla runner)
     * `post-backup-wizard.sh` (Post-mortem diagnostic and validation wizard)
     * `sda_rescue_backup.sh` (Emergency Clonezilla rescue runner for failing drive)
     * `sda5_rescue_backup.sh` (Targeted Clonezilla rescue runner for sda5)
     * `mount_home40_backup.sh` (SSHFS network share mount helper)
     * `mount_fat_and_hdd.sh` (Storage mount helper)
   - Isolated unrelated tools (`run_mosh` and `tailscale_setup.sh`) into a dedicated subfolder `network_and_remote_tools/`.
   - Added clear documentation in `/ntfs/scripts/README.md`.
3. **Sub-Repository Version Control Alignment (`ventoy-2-key/`):**
   - Added all operational backup scripts and `persistence_startup/` launchers directly to `ventoy-2-key/`.
   - Updated `README.md` with Sections 6.3 (OverlayFS Architecture) and 6.4 (Script Distribution Register).

### 9.5 Test Suite Expansion & Audit Results
Expanded `verify_ventoy2.sh` to 9 automated pre-boot test suites:
* **Test 8 (FAT Partition Backup Scripts):** Verified `run_rescuezilla_backup_cli.sh` and `post-backup-wizard.sh` exist on `/ntfs/scripts/`. (**PASS**)
* **Test 9 (Persistence Container OverlayFS Upper Layer):** Loop-mounted `rescuezilla-persistence.dat` and verified binaries in `/upper/scripts/` and launchers in `/upper/home/ubuntu/Desktop/`. (**PASS**)
* All 9 test cases passed cleanly.

### 9.6 Human-in-the-Loop (HITL) Artifact Review
* **Artifact 1 (`persistence_investigation_and_repair_report_2026-09-04.md`):** User approved copying to version control; committed as `03eb682`.
* **Artifact 2 (`screenshot_disks_fat_unmounted.png`):** User elected to skip; preserved on flash at `/ntfs/Screenshot_2026-09-04_18-59-37.png`.

### 9.7 Updated Git Commit Register

| Commit Hash | Message / Scope | Changed Files |
| :--- | :--- | :--- |
| `893ab79` | `fix(ventoy-2): fix OverlayFS persistence deployment, add Clonezilla & post-mortem scripts` | `deploy_four_tier_persistence.sh`, `verify_ventoy2.sh`, `README.md`, `run_rescuezilla_backup_cli.sh`, `post-backup-wizard.sh`, `sda_rescue_backup.sh`, `sda5_rescue_backup.sh`, `mount_home40_backup.sh`, `persistence_startup/` |
| `03eb682` | `docs(ventoy-2): add persistence investigation and repair report artifact` | `ventoy-2-key/persistence_investigation_and_repair_report_2026-09-04.md` |
