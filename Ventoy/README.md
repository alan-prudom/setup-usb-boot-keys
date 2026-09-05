# Ventoy 1 USB Key — Specification, Architecture & Operational Runbook

**Device Node:** `/dev/sdb` (128 GB / 119.1 GiB USB Flash Storage)  
**Target Architecture:** HP ZBook 15u G5 (Legacy MBR / Hybrid BIOS)  
**Disk Identifier (MBR):** `4e210000` / `223cf3f8`  
**Working Identifier:** **Ventoy 1** (Primary Master Rescue Key)  
**Installed Ventoy Core:** `v1.0.99` (x86_64)  
**Status Date:** September 5, 2026 (Common Core & Device Profiles Baseline)  

---

## 1. Executive Summary

This physical USB drive (`/dev/sdb`) serves as the primary master recovery and live boot key for the HP ZBook 15u G5 and multi-machine fleet maintenance.

Following the September 5, 2026 consolidation, this environment incorporates the **Decoupled Common Core Architecture**:
1. **Dynamic Hardware Detection (`lib/lib_hardware_detect.sh`)**: Automatically abstracts block devices, filesystems (`ntfs-3g` vs `vfat`), and mount flags.
2. **Dedicated Device Profile (`profiles/key1_ntfs.conf`)**: Isolates the NTFS Partition 4 UUID (`2C95D29B2DF0500E`), Casper persistence label (`casper-rw`), and target ISO (`rescuezilla-2.6.2-64bit.noble.iso`).
3. **Unified Rescue Suite (`rescue_suite_launcher.sh`)**: Turnkey 5-function menu for Backup, Restore, Clone, Verify, and loopback Image Exploration.
4. **QEMU VM Test Harness (`run_test_vm.sh`)**: Host-level virtualization lab using non-destructive copy-on-write snapshots (`qcow2`) with kernel-enforced read-only storage safety.

---

## 2. Partition Geometry & Usage Matrix

*Audited via `lsblk -f` and `df -hT` on `/dev/sdb`:*

| Partition | Device Node | Filesystem | Volume Label | UUID | Total Size | Used | Avail | Use% | Role & Mount Target |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **P1** | `/dev/sdb1` | `exfat` | `Ventoy` | `4E21-0000` | 19.0 GB | 17.5 GB | 1.5 GB | 92% | Ventoy Bootloader, ISOs & persistence container |
| **P2** | `/dev/sdb2` | `vfat` (FAT16) | `VTOYEFI` | `223C-F3F8` | 32 MB | 27.4 MB | 4.6 MB | 86% | Ventoy Core EFI Bootloader binaries |
| **P3** | `/dev/sdb3` | `ext4` | `UbuntuUSB-Ventoy` | `e0d8ad1a-410b-4245-9192-66d2a16077b9` | 19.0 GB | 11.9 GB | 7.1 GB | 61% | Installed Ubuntu 22.04.5 LTS Rootfs (`/home/alan`) |
| **P4** | `/dev/sdb4` | `ntfs` | *(none)* | `2C95D29B2DF0500E` | 81.0 GB | 36.0 GB | 45.0 GB | 45% | High-capacity NTFS data partition & backup staging |

---

## 3. Storage Inventory & System Containers

### 3.1 Partition 1 Bootable Assets (`/dev/sdb1`)
* `rescuezilla-2.6.2-64bit.noble.iso` (Ubuntu 24.04 LTS Noble basis) — **Primary Live Rescue GUI**
* `rescuezilla-persistence.dat` — 512 MB `ext4` overlay loopback container (label: `casper-rw`). Verified headroom: **196 MB free (57% used)**.
* `supergrub2-classic-2.06s4-multiarch-CD.iso` — Multi-OS bootloader fallback.

### 3.2 Partition 4 Tooling & Staging (`/dev/sdb4`)
* Located at: `/media/devmon/sdb4-usb-Generic-_SD_MMC_` (symlinked at `~/ntfs_usb`).
* Houses pre-authenticated SSH credentials (`id_rsa`, `0600`), baseline diagnostic bundles, and local scripts.

---

## 4. Key Tooling & Script Directory

| Script / File | Role & Capabilities |
| :--- | :--- |
| **`lib/lib_hardware_detect.sh`** | Hardware Abstraction Layer library for dynamic USB device, partition, and driver detection. |
| **`profiles/key1_ntfs.conf`** | Geometric and hardware configuration profile for Key 1. |
| **`rescue_suite_launcher.sh`** | Unified 5-function Rescue Suite (Backup, Restore, Clone, Verify, Image Explorer). |
| **`run_test_vm.sh`** | QEMU virtual machine test harness supporting `--boot`, `--display`, and `--storage` flags. |
| **`deploy_four_tier_persistence.sh`** | Synchronizes tools, desktop launchers, and profiles into `rescuezilla-persistence.dat`. |
| **`run_rescuezilla_backup_cli.sh`** | Turnkey CLI backup runner invoking Clonezilla `ocs-sr` over SSHFS. |
| **`post-backup-wizard.sh`** | Telemetry parser, error analyzer, and diagnostic bundle extractor. |
| **`sda_rescue_backup.sh`** | Bad-sector rescue engine with pre-flight storage assertions and non-destructive imaging. |

---

## 5. Operations & Quick Reference

### Launch QEMU Emulation Lab
```bash
# Option A: Full Ventoy CoW snapshot with TigerVNC on :1 (localhost:5901)
sudo ./run_test_vm.sh --boot 1 --display 2 --storage 1

# Option A: Full Ventoy CoW snapshot with Native GTK Window
sudo ./run_test_vm.sh --boot 1 --display 1 --storage 1

# Option B: Direct Rescuezilla ISO Boot with Persistent Overlay
sudo ./run_test_vm.sh --boot 2 --display 1 --storage 1
```

### Deploy Updates to Live Persistence
```bash
sudo ./deploy_four_tier_persistence.sh
```

### Launch Unified Rescue Suite (Live Environment)
```bash
sudo /scripts/rescue_suite_launcher.sh
```
