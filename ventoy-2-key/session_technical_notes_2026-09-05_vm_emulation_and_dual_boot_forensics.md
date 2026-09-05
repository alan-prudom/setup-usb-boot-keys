# Comprehensive Technical Session Notes: VM Emulation Lab, Dual Boot Forensics, SSH Automation & HITL Artifact Register

**Author / Session Lead:** Alan P & Assistant  
**Date of Record:** September 5, 2026 (12:45 UTC+1)  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Host Operating System:** Ubuntu 22.04 LTS (`x86_64`), Intel VT-x Virtualization (`/dev/kvm`), 15 GB RAM  
**Target Device:** 128 GB SanDisk Multi-Boot USB (`/dev/sdb`, Ventoy 2)  
**Storage Architecture Under Test:**  
* **Internal Drive (`/dev/sda`):** 1 TB (Windows OS, Data, and Ubuntu Linux on `/dev/sda5`)  
* **Ventoy 2 USB (`/dev/sdb`):**  
  - `/dev/sdb1` (20 GB exFAT): Ventoy bootloader, ISOs, `rescuezilla-persistence.dat` (512 MB ext4, `writable`)  
  - `/dev/sdb2` (32 MB FAT16): `VTOYEFI` core  
  - `/dev/sdb3` (19 GB ext4): Installed Ubuntu 22.04 LTS Rootfs (`/home/alan`)  
  - `/dev/sdb4` (82 GB FAT32): `SHARED FAT` cross-platform data & scripts  
* **Remote Network Storage:** HP EliteBook (`alan@192.168.1.34:/media/alan/home40/Clonezilla`)  
**Workspace:** [`/home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/)  

---

## 1. Executive Summary

This session advanced from bare-metal hardware testing to establishing a local **Virtual Machine (VM) Test Harness and Emulation Lab** on the running host OS, resolving runtime defects identified in earlier tests, analyzing dual-mode virtual boot pipelines, automating SSH test connectivity, and cataloging visual test artifacts into version control.

Key milestones accomplished:
1. **Four Core Runtime Defects Resolved:**
   - **Desktop Modal Error (*"no valid Exec line"*):** Repaired malformed `[Desktop Action preferences]` in `xfce4-terminal.desktop` and updated `deploy_four_tier_persistence.sh`.
   - **FAT32 Symlink Rejection:** Refactored `run_rescuezilla_backup_cli.sh` with safe `cp -f` fallback for `latest_backup.log` on FAT filesystems.
   - **Image Explorer Syntax:** Enhanced Option 5 in `rescue_suite_launcher.sh` to dynamically enumerate backup images in `/home/partimag`, prompt for selection, and mount via `rescuezillapy mount` with PCManFM launch.
   - **Dynamic Partition Tables:** Implemented dynamic `lsblk` layout overview tables in `run_rescuezilla_backup_cli.sh` during drive and partition scope selection.
2. **VM Test Harness Implementation (`run_test_vm.sh` & `stimulate_vm_tests.sh`):**
   - Installed `qemu-system-x86`, `tigervnc-viewer`, and `qemu-utils`.
   - Built interactive launcher supporting Option A (Full Ventoy MBR with safe `qcow2` copy-on-write overlay) and Option B (Direct ISO boot).
   - Supported dual display interfaces: Native GTK desktop window and TigerVNC viewer (`localhost:5901`).
   - Enabled safe physical partition passthrough (`/dev/sda` or `/dev/sda5`) with kernel-enforced `readonly=on`.
3. **Forensic Analysis of Initial VM Runs:**
   - **Option B Initial Run:** Revealed that booting the raw ISO bypassed the `persistent` kernel parameter, mounting a RAM `tmpfs` as `/cow` instead of `/dev/vda`.
   - **Option A Initial Run:** Confirmed 100% successful activation of the persistence overlay, desktop launchers, and storage mounts with zero error dialogs.
   - **SSH Connectivity:** Identified that `ssh.service` was inactive by default in the live ISO, causing port 2222 timeouts.
4. **Targeted VM & Persistence Fixes Applied:**
   - Updated Option B to boot the cached kernel (`vmlinuz`) and initrd directly with `boot=casper persistent quiet splash ---`.
   - Injected automatic OpenSSH startup into `rescuezilla-persistence.dat` systemd units and `mount_storage_startup.sh`.
   - Resolved unprivileged `chmod 600` warnings on `/scripts/id_rsa`.
5. **HITL Conversational Artifact Review:**
   - Interactively reviewed four VM diagnostic screenshots; approved and committed the GParted passthrough view and the active Option A persistent desktop view.

---

## 2. Forensic Analysis of VM Boot Pipelines (Option A vs. Option B)

### 2.1 Option B Initial Test Forensics
* **Observed Symptom:** Option B booted the Rescuezilla desktop quickly, but custom desktop icons were absent and `/cow` was 1.5 GB in RAM (`df -h`).
* **Root Cause:** Direct ISO boot (`-cdrom ... -boot d`) triggers the ISO's built-in isolinux default entry:
  ```text
  boot=casper quiet splash ---
  ```
  Casper requires the explicit kernel argument `persistent` to scan for and attach persistence containers (labeled `writable`). Because QEMU passed no kernel parameters to the ISO bootloader, Casper defaulted to a volatile RAM overlay and ignored virtual drive `/dev/vda`.
* **Resolution Deployed:**
  - Extracted and cached `vmlinuz` and `initrd.lz` from the Rescuezilla ISO into `/media/alan/Ventoy1/boot_cache/`.
  - Updated `run_test_vm.sh` Option B to launch via:
    ```bash
    -kernel /media/alan/Ventoy1/boot_cache/vmlinuz \
    -initrd /media/alan/Ventoy1/boot_cache/initrd.lz \
    -append "boot=casper persistent quiet splash ---" \
    -drive file=/media/alan/Ventoy1/rescuezilla-persistence.dat,format=raw,if=virtio,cache=writeback
    ```
  - Option B now mounts persistence immediately upon boot in ~5 seconds.

### 2.2 Option A Test Forensics (Screenshot `12-14-34.png`)
* **Observed Result:** Running Option A (`run_test_vm.sh` -> Choose `1` -> Ventoy menu -> Rescuezilla with persistence) achieved **complete persistence activation**:
  - All four custom desktop widgets (`Rescue_Suite.desktop`, `Mount_Network_home40.desktop`, `Run_Backup_CLI.desktop`, `Post_Backup_Wizard.desktop`, `Mount_Storage.desktop`) appeared cleanly.
  - Desktop storage symlinks (`SHARED_FAT_Storage`, `Internal_HDD`, `Remote_Backup_Storage`) were mounted and active.
  - **Zero modal error dialogs** appeared, confirming the fix for the *"no valid Exec line"* bug.
* **Transient CoW Protection Confirmed:** The QEMU `qcow2` overlay (`/tmp/ventoy_sdb_snapshot_*.qcow2`) absorbed all guest writes, ensuring complete isolation from the running host OS rootfs on `/dev/sdb3`.

---

## 3. SSH Service Automation & Telemetry Harness

### 3.1 Resolving SSH Service Absence
* **Problem:** In Ubuntu Live and Rescuezilla, `ssh.service` is disabled by default to prevent exposing open ports during recovery tasks. Attempting to connect via `ssh -p 2222 ubuntu@localhost` timed out.
* **Remediation:**
  1. In `deploy_four_tier_persistence.sh`, created the enabled systemd unit link:
     `/upper/etc/systemd/system/multi-user.target.wants/ssh.service -> /lib/systemd/system/ssh.service`
  2. Added fallback daemon activation in `mount_storage_startup.sh`:
     ```bash
     systemctl start ssh 2>/dev/null || /etc/init.d/ssh start || true
     ```
  3. Re-executed `deploy_four_tier_persistence.sh` to write the configuration into `rescuezilla-persistence.dat`.

### 3.2 Automated Test Harness (`stimulate_vm_tests.sh`)
* Provides a script that connects over SSH to port `2222` using `/home/alan/.ssh/id_rsa`.
* Performs non-interactive verification:
  - Validates guest kernel and block devices (`lsblk`).
  - Verifies OverlayFS mounts (`/cow/upper`).
  - Audits desktop entries using `desktop-file-validate`.
  - Extracts storage startup logs from `/var/log/startup_storage.log`.

---

## 4. Human-in-the-Loop (HITL) Artifact Review Register

The conversational screenshot artifacts generated during the VM testing sessions were presented individually for human confirmation:

| Artifact File | Description / Forensic Scope | Decision | Repository Target |
| :--- | :--- | :--- | :--- |
| `media_1788606464242.png` | VM Option B initial test status showing non-persistent boot and `df -h` | **Skipped** | N/A |
| `media_1788606467014.png` | VM GParted view showing 512MB persistence disk (`/dev/vda`) and 1TB read-only physical drive passthrough (`/dev/vdb`) | **Approved** | [`ventoy-2-key/docs/screenshots/vm_storage_passthrough_gparted.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/vm_storage_passthrough_gparted.png) |
| `media_1788607314006.png` | VM Option A screenshot showing fully active persistent desktop with all custom launchers and storage widgets | **Approved** | [`ventoy-2-key/docs/screenshots/vm_option_a_desktop_persistence_active.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/vm_option_a_desktop_persistence_active.png) |
| `media_1788607316920.png` | Terminal view of unprivileged `chmod` error on `/scripts/id_rsa` | **Skipped** | N/A (defect fixed in `mount_home40_backup.sh`) |

---

## 5. File Changes Register

| File Path | Description of Changes |
| :--- | :--- |
| [`ventoy-2-key/run_test_vm.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/run_test_vm.sh) | **NEW:** Interactive VM test runner; handles Option A (Ventoy CoW) & Option B (Direct persistent kernel launch), Native GTK and TigerVNC display modes, read-only physical disk passthrough, and SSH port forwarding (2222). |
| [`ventoy-2-key/stimulate_vm_tests.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/stimulate_vm_tests.sh) | **NEW:** Automated SSH test harness; polls guest on `localhost:2222`, runs non-interactive system checks, verifies desktop files, and extracts logs. |
| [`ventoy-2-key/vm_test_harness_and_emulation_architecture.md`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/vm_test_harness_and_emulation_architecture.md) | **NEW:** Complete engineering specification detailing hypervisor configuration, CoW protection, display mechanics, and read-only passthrough safety. |
| [`ventoy-2-key/deploy_four_tier_persistence.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/deploy_four_tier_persistence.sh) | **MODIFIED:** Added automatic repair for `xfce4-terminal.desktop`, enabled `ssh.service` in systemd `multi-user.target.wants/`, and added `systemctl start ssh` to `mount_storage_startup.sh`. |
| [`ventoy-2-key/mount_home40_backup.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/mount_home40_backup.sh) | **MODIFIED:** Wrapped `chmod 600 "$KEY_FILE"` in permission check to avoid `EPERM` errors when executed by unprivileged user `ubuntu`. |
| [`ventoy-2-key/README.md`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/README.md) | **MODIFIED:** Added Section 7 detailing execution runbooks for `run_test_vm.sh` and `stimulate_vm_tests.sh`. |
| [`ventoy-2-key/docs/screenshots/vm_storage_passthrough_gparted.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/vm_storage_passthrough_gparted.png) | **NEW:** Visual artifact verifying virtual persistence container (`vda`) and read-only physical disk passthrough (`vdb`). |
| [`ventoy-2-key/docs/screenshots/vm_option_a_desktop_persistence_active.png`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/docs/screenshots/vm_option_a_desktop_persistence_active.png) | **NEW:** Visual artifact confirming fully active persistent desktop, custom launchers, and error-free rendering under VM Option A. |

---

## 6. Git Commit Log for Session Changes

All changes pushed to `origin/main` on [`https://github.com/alan-prudom/setup-usb-boot-keys.git`](https://github.com/alan-prudom/setup-usb-boot-keys.git):

```
8da1b12 (HEAD -> main, origin/main) docs(ventoy-2): add screenshot artifact showing active persistent desktop under VM Option A
3b3a30a docs(ventoy-2): add screenshot artifact showing VM GParted storage passthrough
c3230f8 fix(ventoy-2): auto-start SSH in persistence, add direct persistent kernel boot for Option B, and fix key chmod
db18a5c feat(ventoy-2): implement interactive VM test harness with Option A/B boot, GTK/TigerVNC display, SSH stimulus and safe storage passthrough
fd02837 fix(ventoy-2): eradicate desktop modal error, add FAT32 link fallback, interactive image explorer and dynamic partition tables
```

Both the sub-repository and parent repository working trees are clean.
