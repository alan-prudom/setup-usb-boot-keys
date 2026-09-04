# Ventoy 2 USB Key — Specification, Architecture & Operational Runbook

**Device Node:** `/dev/sdb` (128 GB / 119.1 GiB USB Flash Storage)  
**Disk Identifier (MBR):** `199e46a9`  
**Working Identifier:** **Ventoy 2** (Secondary / Legacy Rescue Key)  
**Installed Ventoy Core:** `v1.0.99` (x86_64)  
**Reference Model:** Primary Ventoy Key (documented in `Ventoy/` sub-repository)  
**Status Date:** September 3, 2026 (Post-Upgrade Synchronized Baseline)  

---

## 1. Executive Summary

This physical USB drive (`/dev/sdb`) has been upgraded in-place to **Ventoy 2**. It provides full feature parity with the primary Ventoy 1 key:
1. **Up-to-date Ventoy Core:** Refreshed in-place to `v1.0.99` on Sector 0 MBR and Partition 2 (`VTOYEFI`).
2. **Instant F6 Direct Boot:** Custom GRUB configuration chainloads the installed Ubuntu 22.04 LTS OS on Partition 3 (`/dev/sdb3`), direct kernel fallback, and internal Windows (`/dev/sda`).
3. **Rescuezilla Live GUI with Persistence:** Includes Rescuezilla 2.6.1 Live GUI accompanied by a formatted 512 MB `ext4` persistence overlay (`rescuezilla-persistence.dat` labeled `casper-rw`).
4. **Optimized Partition Capacity:** Archived legacy ISOs to Partition 4, maintaining **3.3 GB clean headroom** on Partition 1.

---

## 2. Real-Time Partition Geometry & Usage Matrix

*Audited via `lsblk` and `df -hT` post-upgrade:*

| Partition | Device Node | Filesystem | Volume Label | UUID | PARTUUID | Total Size | Used | Avail | Use% | Role & Mount Target |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **P1** | `/dev/sdb1` | `exfat` | `Ventoy` | `4E21-0000` | `199e46a9-01` | 20 GB | 16 GB | 3.3 GB | 83% | Ventoy Bootloader & ISOs (`/media/alan/Ventoy`) |
| **P2** | `/dev/sdb2` | `vfat` | `VTOYEFI` | `223C-F3F8` | `199e46a9-02` | 32 MB | 28 MB | 4.6 MB | 86% | Ventoy Core EFI Bootloader binaries |
| **P3** | `/dev/sdb3` | `ext4` | *(none)* | `e0d8ad1a-410b-4245-9192-66d2a16077b9` | `199e46a9-03` | 19 GB | 16 GB | 2.4 GB | 87% | Installed Ubuntu 22.04.5 LTS Rootfs (`/home/alan`) |
| **P4** | `/dev/sdb4` | `vfat` | `SHARED FAT` | `C9D1-3C83` | `199e46a9-04` | 82 GB | 60 GB | 22 GB | 74% | Cross-platform FAT32 shared data & archives |

---

## 3. Storage Inventory & Asset Registry

### 3.1 Active Bootable ISOs on Partition 1 (`/dev/sdb1`)

| File Name | File Size | Role & Category |
| :--- | :--- | :--- |
| `ubuntu-24.04.3-live-server-amd64.iso` | 3.3 GB | Modern Ubuntu Server installer |
| `pop-os_22.04_amd64_intel_49.iso` | 2.6 GB | Pop!_OS desktop environment |
| `debian-live-10.10.0-amd64-xfce.iso` | 2.4 GB | Lightweight Debian XFCE live |
| `Fedora-Workstation-Live-x86_64-33-1.2.iso` | 2.0 GB | Fedora live desktop |
| `PeppermintOS-Debian-64.iso` | 1.5 GB | Peppermint OS |
| `rescuezilla-2.6.1-64bit.oracular.iso` | 1.4 GB | Rescuezilla GUI Disk Backup & Recovery (**+Persistence**) |
| `HBCD_PE_x64 2018.iso` | 1.3 GB | Hiren's BootCD PE (Windows repair utilities) |
| `gparted-live-1.6.0-10-amd64.iso` | 576 MB | Dedicated disk partition editor |
| `clonezilla-live-3.2.0-5-amd64.iso` | 457 MB | Bare-metal disk imaging CLI (`ocs-sr`) |
| `alpine-standard-3.21.0-x86_64.iso` | 251 MB | Minimal security-oriented Alpine Linux |
| `mini.iso` | 67 MB | Minimal network bootloader |
| `DPMS.ISO` | 47 MB | Driver Pack Mass Storage (legacy driver utility) |
| `supergrub2-classic-2.06s4-multiarch-CD.iso` | 24 MB | Universal multi-boot scanner fallback |

### 3.2 System Containers & Configurations on Partition 1 (`/dev/sdb1`)

1. **`rescuezilla-persistence.dat`**:
   - Size: 512 MB
   - Filesystem: `ext4`, Volume Label: `casper-rw`
   - UUID: `309a9e74-4230-458f-b89e-c492dcd3506f`
   - Automatically mapped to Rescuezilla via `ventoy.json`.
2. **`ventoy/ventoy_grub.cfg` & `ventoy_grub.cfg`**:
   - Custom F6 direct-boot configuration.
   - Searches for UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9` to chainload `/boot/grub/grub.cfg` or direct kernel (`/boot/vmlinuz`).
   - Chainloads internal Windows (`/bootmgr`).
3. **`ventoy/ventoy.json`**:
   - Plugin mapping for persistence containers.
   - Menu alias substitutions for clean UI rendering.
4. **`Project Link.txt`**:
   - Preserved reference link: `https://gemini.google.com/app/8cec7eb529b19078`.
5. **`ventoy-1.1.10-windows.zip`**:
   - Preserved portable Windows binary archive.

### 3.3 Archived ISOs on Partition 4 (`/dev/sdb4`)
Located in `/media/alan/SHARED FAT/Archived_ISOs/`:
* `CentOS-7-x86_64-Minimal-1810.iso` (918 MB)
* `ubuntu-20.04.2.0-desktop-amd64.iso` (2.7 GB)

---

## 4. Boot & Operational Runbook

### 4.1 Normal Ventoy Boot
1. Insert USB drive and power on system (press `F9` for HP Boot Device Options).
2. Select the USB drive under **Legacy Boot** or **UEFI Boot**.
3. Ventoy 1.0.99 graphical menu displays.
4. Select any ISO to boot directly. If selecting **Rescuezilla**, choose **Boot with persistence** to retain data.

### 4.2 Instant F6 Boot to Installed Linux OS (`/dev/sdb3`)
1. At the Ventoy boot menu, press **`F6`**.
2. Select:
   * **`🟢 Boot Installed Ubuntu 22.04 LTS (Ubuntu-USB-Ventoy on /dev/sdb3)`**
3. System instantly chainloads `/boot/grub/grub.cfg` from UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9` without needing SuperGrub scanning.

### 4.3 Windows Chainload
1. At the Ventoy boot menu, press **`F6`**.
2. Select **`🪟 Boot Windows (Internal Disk /dev/sda)`**.
3. GRUB chainloads the internal system's `/bootmgr`.

---

## 5. Maintenance & Verification Toolkit

All scripts and configuration templates are tracked in git under `devices/setup-usb-boot-keys/ventoy-2-key/`:

* **`verify_ventoy2.sh`**: Runs partition, UUID, GRUB syntax, and JSON syntax checks:
  ```bash
  ./devices/setup-usb-boot-keys/ventoy-2-key/verify_ventoy2.sh
  ```
* **`upgrade_ventoy2.sh`**: Non-destructive upgrade wizard (`Ventoy2Disk.sh -u`) for future updates.


---

## 6. Persistence & Live Rescue Architecture (September 4, 2026 Baseline)

### 6.1 Four-Tier Redundancy Architecture
1. **Tier 1: Embedded Root Binaries (`/scripts/` & `/usr/local/bin/`)**
   - Completely decoupled from external disk mounting to eliminate Status 127 errors.
   - Includes `run_rescuezilla_backup_cli.sh` and `post-backup-wizard.sh`.
2. **Tier 2: Automatic Storage Detection & Mounting**
   - Script `/usr/local/bin/mount_storage_startup.sh` auto-mounts `SHARED FAT` (`UUID=C9D1-3C83`) with `uid=1000,gid=1000,umask=000` at `/media/ubuntu/SHARED_FAT`.
   - Mounts internal HDD Linux partition `/dev/sda5` (read-only) at `/media/ubuntu/Internal_HDD`.
3. **Tier 3: Openbox-Native Autostart**
   - Registered in both `/home/ubuntu/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
4. **Tier 4: Desktop Launchers with Window Retention (`--hold`)**
   - Launchers on `/home/ubuntu/Desktop/` maintain terminal logs open on exit.

### 6.2 Automatic Network Storage (`home40`)
- Systemd user service `mount-home40.service` auto-mounts `192.168.1.34:/media/alan/home40` via SSHFS on boot, restoring access to linked Git workspaces.
