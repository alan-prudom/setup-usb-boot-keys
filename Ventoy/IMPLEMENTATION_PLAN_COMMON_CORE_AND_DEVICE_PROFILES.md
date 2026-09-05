# Implementation Plan: Shared Common Core Engine, Isolated Hardware Profiles & QEMU Emulation Suite

**Author / Session Lead**: Alan P & Assistant  
**Date of Record**: September 5, 2026  
**Target Repository**: `devices/setup-usb-boot-keys` (Branch: `main`)  
**Deployment Scope**: Both physical keys (`Ventoy` Key 1 and `ventoy-2-key` Key 2)

---

## 1. Executive Summary & Goals

### 1.1 Objective
Establish an architectural separation between:
1. **Shared Common Core**: High-level tools, QEMU VM emulation harness, unified rescue suite, and Clonezilla automation scripts.
2. **Dynamic Hardware Detection & Device Profiles**: Hardware metadata, partition UUIDs, filesystem drivers (`ntfs-3g` vs `vfat`), volume labels, ISO filenames, and Casper persistence labels.

### 1.2 Target Outcomes
* **Zero Hardcoded UUIDs in Core Logic**: No core tool will have hardcoded strings like `2C95D29B2DF0500E` or `C9D1-3C83`.
* **Universal Portability**: Scripts will dynamically detect whether Partition 4 is NTFS or FAT32 and apply proper mount flags and drivers automatically.
* **QEMU Emulation Lab**: Enable virtual testing of the Ventoy bootloader, GRUB menu, and Rescuezilla persistence directly from the Ubuntu host using a safe copy-on-write (`qcow2`) overlay without rebooting.
* **Unified Rescue Suite**: Port the 5-function interactive launcher (`rescue_suite_launcher.sh`) covering Backup, Restore, Clone, Verify, and Image Explorer.

---

## 2. Hardware Profile Differences (Audit Matrix)

| Property | Key 1 (`Ventoy/`) | Key 2 (`ventoy-2-key/`) |
| :--- | :--- | :--- |
| **Working Directory** | `Ventoy/` | `ventoy-2-key/` |
| **Partition 4 Filesystem** | **NTFS** (`fuseblk` / `ntfs-3g`) | **FAT32** (`vfat`) |
| **Partition 4 UUID** | `2C95D29B2DF0500E` | `C9D1-3C83` |
| **Partition 4 Volume Label** | *(None / generic)* | `SHARED FAT` |
| **P4 Mount Driver & Options** | `mount -t ntfs-3g -o rw,umask=000,uid=1000,gid=1000,force` | `mount -t vfat -o rw,umask=000,uid=1000,gid=1000,iocharset=utf8` |
| **Rescuezilla ISO Name** | `rescuezilla-2.6.2-64bit.noble.iso` (24.04) | `rescuezilla-2.6.1-64bit.oracular.iso` (24.10) |
| **Casper Persistence Label** | `casper-rw` | `writable` |

---

## 3. Implementation Steps

### Phase 1: Dynamic Hardware Detection Library (`lib_hardware_detect.sh`)
Create a modular POSIX-compliant shell library that:
1. Detects device node (`/dev/sdb`, `/dev/sdc`, etc.) dynamically via `/sys/block` or `lsblk`.
2. Inspects Partition 4 with `blkid -s TYPE -o value` and resolves filesystem, UUID, and label.
3. Provides standardized helper functions:
   * `mount_data_partition [mountpoint]`
   * `get_persistence_container_path`
   * `get_active_iso_path`

### Phase 2: Device Configuration Profiles (`profiles/`)
Create lightweight configuration files:
* `profiles/key1_ntfs.conf`
* `profiles/key2_fat32.conf`

### Phase 3: Port & Adapt the Unified Rescue Suite (`rescue_suite_launcher.sh`)
Port `rescue_suite_launcher.sh` from `ventoy-2-key` into `Ventoy/`:
* Make it source `lib_hardware_detect.sh`.
* Ensure strict POSIX syntax compliance (no `[[` Dash errors).
* Support all 5 core functions:
  1. Backup Image (`ocs-sr` native CLI).
  2. Restore Image (with partition selection).
  3. Clone Disk-to-Disk (`ocs-onthefly`).
  4. Verify Image Integrity (`partclone` dry-run extraction).
  5. Image Explorer (loopback mount Partclone images for file browsing).
  6. Mount Network Storage (`home40`) only.
  7. Post-Backup Diagnostic Wizard.

### Phase 4: Port & Adapt the QEMU Test Harness (`run_test_vm.sh`)
Port `run_test_vm.sh` from `ventoy-2-key` into `Ventoy/`:
* Sources `lib_hardware_detect.sh` to auto-detect ISO and persistence files.
* Uses a temporary `qcow2` copy-on-write overlay over `/dev/sdb` (zero writes to physical USB).
* Offers Native GTK window or decoupled TigerVNC display.
* Offers read-only physical disk passthrough (`readonly=on`).

### Phase 5: Persistence Deployment Engine (`deploy_four_tier_persistence.sh`)
Adapt `deploy_four_tier_persistence.sh` to sync the common core, library, profiles, and desktop shortcuts into `rescuezilla-persistence.dat` (writing to both `/upper/` and root `/`).

### Phase 6: Verification & Synchronization
* Test hardware detection library across both profiles.
* Verify clean git status and push to GitHub.
