# Comprehensive Technical Notes: Common Core Architecture, Device Profiles, QEMU Emulation Harness & Artifact Review

**Author / Session Lead**: Alan P & Assistant  
**Date of Record**: September 5, 2026 (23:45 UTC+1)  
**Primary Environment**: HP ZBook 15u G5 running Ubuntu 22.04 LTS from USB (`/dev/sdb3`)  
**Repositories**:
* Primary Sub-Repo: `devices/setup-usb-boot-keys` (Branch: `main`)
* Secondary Mirror: `~/Documents/setup-usb` (Branch: `main`)
* Parent Repo: `/home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs`  

---

## 1. Executive Summary

This session executed a major architectural consolidation between the two parallel USB projects:
1. **`Ventoy/` (Key 1 — HP ZBook / Toshiba 128 GB)**: NTFS Partition 4 (`2C95D29B2DF0500E`), Casper label `casper-rw`, ISO `rescuezilla-2.6.2-64bit.noble.iso` (Ubuntu 24.04).
2. **`ventoy-2-key/` (Key 2 — SanDisk Ultra 128 GB)**: FAT32 Partition 4 (`C9D1-3C83`), Casper label `writable`, ISO `rescuezilla-2.6.1-64bit.oracular.iso` (Ubuntu 24.10).

All advanced capabilities developed in `ventoy-2-key`—specifically the **Unified 5-Function Rescue Suite**, the **Hardware Abstraction Layer**, and the **QEMU Virtual Machine Test Harness**—have been successfully ported and integrated into `Ventoy/` under a shared common core design. Furthermore, the QEMU test harness was upgraded with non-interactive CLI flags and verified live in emulation. Finally, a complete human-in-the-loop (HITL) review of conversational screenshot artifacts was completed.

---

## 2. Key Discussion Points & Strategic Decisions

### 2.1 Decoupled Architecture: Common Core vs. Hardware Profiles
* **Problem**: Previous scripts contained hardcoded UUIDs (`2C95D29B2DF0500E`), fixed mount options (`ntfs-3g`), and hardcoded ISO filenames (`noble.iso`), preventing cross-key portability.
* **Solution**: Separated high-level execution logic from hardware and geometry configurations:
  * **Dynamic Hardware Detection Library** (`Ventoy/lib/lib_hardware_detect.sh`): Auto-detects USB block devices (`/dev/sdb`), queries Partition 4 with `blkid -s TYPE`, and dynamically chooses mount commands (`ntfs-3g -o rw,umask=000,uid=1000,gid=1000,force` for NTFS vs `vfat -o rw,umask=000,uid=1000,gid=1000,iocharset=utf8` for FAT32).
  * **Isolated Hardware Profiles** (`Ventoy/profiles/`): Defined declarative profiles (`key1_ntfs.conf` and `key2_fat32.conf`) storing UUIDs, volume labels, Casper persistence labels, and target ISO versions.

### 2.2 ZBook Internal SSD Degradation & Isolation
* **Hardware Status**: Internal Crucial 1TB SSD (`/dev/sda`) remains severely worn:
  * Wear level: 6% lifetime remain (94% consumed).
  * Uncorrectable errors: 1,030.
  * Reallocated event count: 16 (spare pool exhausted).
* **Isolation Guardrails**: 
  * `deploy_four_tier_persistence.sh` was updated to omit any auto-mounting of internal `/dev/sda5`.
  * `/etc/udev/rules.d/99-block-failing-sda-partitions.rules` is active on `/dev/sda9`, masking `sda2` and `sda5` from udisks and systemd.
  * In the QEMU test runner, `--storage 1` (Sandbox) was set as default to keep `/dev/sda` completely inaccessible from the virtual machine.

### 2.3 Conversational Artifacts Decision (HITL Audit)
* **Context**: Ten temporary image artifacts (`.tempmediaStorage/*.png`) existed from diagnostic troubleshooting sessions.
* **HITL Decision**: Each artifact was presented individually with proposed filenames and summaries. The user voted **"No - Skip" on all 10 artifacts**.
* **Outcome**: In strict accordance with HITL instructions, zero binary image files were committed to Git, keeping the repository purely lightweight and text-focused.

---

## 3. Detailed File Changes & Additions

### 3.1 New Components Created

#### 1. `Ventoy/lib/lib_hardware_detect.sh`
* **Purpose**: Hardware Abstraction Layer for USB key autodetection.
* **Key Functions**:
  * `detect_usb_device`: Finds the parent disk node (`/dev/sdb`, etc.) matching `Ventoy` or `UbuntuUSB-Ventoy`.
  * `detect_data_partition`: Locates Partition 4 and checks filesystem type (`ntfs`, `vfat`, `ext4`).
  * `mount_data_partition [mountpoint]`: Dynamically issues the correct `mount` command with appropriate flags.
  * `find_rescuezilla_iso`: Scans standard mount points for `rescuezilla*.iso`.
  * `find_persistence_file`: Resolves `rescuezilla-persistence.dat`.

#### 2. Hardware Profile Configurations (`Ventoy/profiles/`)
* **`Ventoy/profiles/key1_ntfs.conf`**:
  * Device: Key 1 (ZBook / Toshiba 128 GB)
  * Partition 4: NTFS, UUID `2C95D29B2DF0500E`
  * Persistence Label: `casper-rw`
  * Default ISO: `rescuezilla-2.6.2-64bit.noble.iso`
* **`Ventoy/profiles/key2_fat32.conf`**:
  * Device: Key 2 (ThinkPad / SanDisk 128 GB)
  * Partition 4: FAT32, Label `SHARED FAT`, UUID `C9D1-3C83`
  * Persistence Label: `writable`
  * Default ISO: `rescuezilla-2.6.1-64bit.oracular.iso`

#### 3. `Ventoy/IMPLEMENTATION_PLAN_COMMON_CORE_AND_DEVICE_PROFILES.md`
* Full 4-phase architectural blueprint detailing the common core, library design, POSIX validation requirements, and QEMU integration.

---

### 3.2 Existing Components Ported & Enhanced

#### 1. `Ventoy/rescue_suite_launcher.sh`
* Ported from `ventoy-2-key` with strict POSIX compliance (no unquoted `[[` bashisms).
* Sources `lib_hardware_detect.sh`.
* Provides an interactive ANSI terminal menu with 7 actions:
  1. 💾 Backup Image (`ocs-sr` native CLI).
  2. 🔄 Restore Image (with partition picker).
  3. ⚡ Disk-to-Disk Clone (`ocs-onthefly`).
  4. 🔍 Verify Image Integrity (`partclone` test mode).
  5. 📂 Image Explorer (read-only loopback mount of Partclone archives).
  6. 🌐 Mount Network Storage (`home40`).
  7. 🛡️ Post-Backup Diagnostic Wizard.

#### 2. `Ventoy/deploy_four_tier_persistence.sh`
* Ported and adapted for Key 1.
* Mounts `rescuezilla-persistence.dat` via loopback.
* Deploys:
  * `/scripts/lib/lib_hardware_detect.sh`
  * `/scripts/rescue_suite_launcher.sh`
  * `/scripts/run_rescuezilla_backup_cli.sh`
  * `/scripts/post-backup-wizard.sh`
  * `/scripts/sda_rescue_backup.sh`
  * Pre-authenticated SSH private key (`id_rsa`, `0600`) for headless network mounts.
  * Desktop launchers in `/home/ubuntu/Desktop/` and `/upper/home/ubuntu/Desktop/`.
* Audit verified headroom: **196 MB free (57% utilized)**.

#### 3. `Ventoy/run_test_vm.sh` (Major Enhancement)
* **CLI Arguments Added**:
  * `--boot 1|2`: `1` for Ventoy CoW overlay; `2` for Direct Rescuezilla ISO.
  * `--display 1|2`: `1` for native GTK window; `2` for TigerVNC server on `:1` (`localhost:5901`).
  * `--storage 1|2|3`: `1` for sandbox; `2` for `/dev/sda` (RO); `3` for `/dev/sda5` (RO).
* **Display Handling Improvements**:
  * Auto-detects host `$DISPLAY` and `$XAUTHORITY` (supports Mutter/Xwayland auth and GDM Xauthority).
  * Safely handles non-TTY environments (`clear 2>/dev/null || true`).
* **CoW Isolation**:
  * Option A creates a transient `qcow2` snapshot (`/tmp/ventoy_sdb_snapshot_$$.qcow2`) backed by `/dev/sdb`.
  * Trap handlers guarantee automatic deletion of the temporary overlay on script termination.

---

## 4. Verification & Testing Matrix

| Test Item | Command / Procedure | Result | Status |
| :--- | :--- | :--- | :---: |
| **QEMU Option A Launch** | `sudo ./run_test_vm.sh --boot 1 --display 2 --storage 1` | Spawned PID 19173, VNC on `:5901`, SSH on `2222` | ✅ **PASS** |
| **Transient CoW Cleanup** | Monitored process exit and checked `/tmp/` | Overlay `/tmp/ventoy_sdb_snapshot_19152.qcow2` purged | ✅ **PASS** |
| **Block Device Integrity** | `lsblk -f` on host | Physical `/dev/sdb` partitions untouched | ✅ **PASS** |
| **Persistence Container Check**| Inspected `rescuezilla-persistence.dat` | Headroom 196 MB, zero leakage | ✅ **PASS** |
| **Git Tree Synchronization** | Committed to `origin/main`, mirrored to `~/Documents/setup-usb` | Clean working tree, commits `617f84c` & `3e69217` | ✅ **PASS** |
| **Artifact Review** | 10 screenshots reviewed with HITL prompts | All 10 skipped; zero binaries in repo | ✅ **PASS** |

---

## 5. Commit History for this Session

* **`617f84c`**: `Implement decoupled common core, dynamic hardware detection library, device profiles, and QEMU test harness`
* **`3e69217`**: `feat(harness): add non-interactive CLI flags and robust display handling to run_test_vm.sh`
