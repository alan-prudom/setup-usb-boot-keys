# Troubleshooting & Resolution Report: Ventoy 2 Rescuezilla Persistence & USB Ubuntu Boot Hang

**Date:** September 4, 2026  
**Target Device:** Ventoy 2 (128 GB SanDisk USB, `/dev/sdb`)  
**Workspace:** `ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/`

---

## 1. Rescuezilla Persistence: Label Investigation (`casper-rw` vs `writable`)

### 1.1 Problem Diagnosis
When booting `rescuezilla-2.6.1-64bit.oracular.iso` with persistence enabled in Ventoy, the live system failed to recognize the persistent overlay container.

### 1.2 Root Cause
* **Casper Modern Specification:** The Rescuezilla ISO is built on Ubuntu 24.10 (Oracular). Modern Casper implementations since Ubuntu 20.04/24.04 deprecated the legacy volume label `casper-rw` and require the persistent ext4 filesystem to be labeled **`writable`**.
* **Container State:** `rescuezilla-persistence.dat` on Partition 1 (`/dev/sdb1`) was formatted with label `casper-rw`.

### 1.3 Resolution Executed
Relabeled the ext4 persistence container directly using `e2label`:
```bash
e2label /media/alan/Ventoy/rescuezilla-persistence.dat writable
```
Confirmed with `blkid`:
```text
/media/alan/Ventoy/rescuezilla-persistence.dat: LABEL="writable" UUID="309a9e74-4230-458f-b89e-c492dcd3506f" TYPE="ext4"
```

---

## 2. USB Ubuntu Partition Boot Hang (F6 Menu)

### 2.1 Problem Diagnosis
Selecting installed Ubuntu 22.04 LTS on `/dev/sdb3` from the Ventoy F6 custom menu resulted in the boot hanging before reaching the user desktop.

### 2.2 Syslog & Boot Audit Findings
1. **Remote Filesystem (`home40` / SSHFS):**
   - Did not cause the kernel or system hang. The `/etc/fstab` line had `x-systemd.automount,_netdev`, but when offline it produced background failure storms.
2. **Display Server Crash (GDM3 / Xorg):**
   - The actual hang occurred when GDM launched Xorg. 
   - The Intel GPU driver crashed during hardware GL initialization (`gbm_create_device` -> crash inside `libLLVM-15.so.1` in `glamor_egl_init`):
     ```text
     (EE) Backtrace:
     (EE) 2: /lib/x86_64-linux-gnu/libLLVM-15.so.1
     (EE) 21: /usr/lib/xorg/modules/libglamoregl.so (glamor_egl_init+0x67)
     (EE) Fatal server error: (EE) Server terminated with error (1)
     gdm3: GdmLocalDisplayFactory: maximum number of X display failures reached
     ```
   - GDM reached its maximum restart limit and quit, leaving the screen sitting on Plymouth or a frozen blank display.

### 2.3 Resolutions Executed
1. **Removed Redundant SSHFS Entry:**
   Removed `alan@192.168.1.34:/media/alan/home40` from `/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/etc/fstab` (backed up to `fstab.bak`). Remote workspaces are cleanly mounted upon user login via `~/.config/systemd/user/mount-home40.service`.
2. **Forced Wayland Off in GDM:**
   Set `WaylandEnable=false` in `/etc/gdm3/custom.conf` on the USB partition.
3. **F6 Custom Menu Recovery Stanzas Added (`ventoy_grub.cfg`):**
   Added two fallback boot entries to `/media/alan/Ventoy/ventoy_grub.cfg` and the repository:
   - `🟢 Direct Linux Kernel Boot - Safe Graphics (nomodeset)`: Boots full GUI with software rendering, bypassing KMS GPU driver crashes.
   - `🟢 Direct Linux Kernel Boot - Text Console`: Boots directly to a text TTY login (`systemd.unit=multi-user.target`).

---

## 3. Casper OverlayFS Invisibility & FAT Script Synchronization

### 3.1 Problem Diagnosis
When booting Rescuezilla 2.6.1 Live with persistence:
1. The desktop loaded in its default state without custom launchers or storage shortcuts, and partition 4 (`SHARED FAT`) was not mounted automatically.
2. When `/dev/sdb4` was manually mounted, expected Clonezilla scripts (`run_rescuezilla_backup_cli.sh`, `sda_rescue_backup.sh`) and post-mortem wizard (`post-backup-wizard.sh`) were missing from `/scripts/`, while unrelated tools (`run_mosh`, `tailscale_setup.sh`) were present.

### 3.2 Root Cause Analysis
1. **Casper OverlayFS Mechanism:**
   - Modern Casper (Ubuntu 24.10) sets up root persistence via OverlayFS with `upperdir=/cow/upper` and `workdir=/cow/work`.
   - The previous deployment script wrote directly to `$MNT/scripts/` and `$MNT/home/ubuntu/Desktop/` (outside `/upper/`).
   - Because the live system only mounts `/cow/upper/` as its writable overlay layer, files in raw `/cow/` were completely hidden from the running desktop.
2. **FAT Partition Script Gap:**
   - The Clonezilla runners and post-mortem wizard were preserved in `Ventoy/` but had never been copied to the FAT32 partition (`/ntfs/scripts/`).

### 3.3 Resolutions Executed
1. **Dual-Target OverlayFS Deployment:** Updated `deploy_four_tier_persistence.sh` to inject scripts, launchers, and autostart configurations into both `$MNT/upper/` (live overlay layer) and `$MNT/` (raw fallback).
2. **Triple-Redundant Storage Auto-Mount:** Deployed systemd service unit (`mount-storage-startup.service` in `multi-user.target.wants/`), XDG desktop autostart, and Openbox autostart to automatically mount `/dev/sdb4` (`SHARED FAT`) and `/dev/sda5` (`Internal_HDD`, read-only).
3. **Script Ecosystem Mirroring:** Copied all backup and post-mortem scripts to `/ntfs/scripts/`, `/media/alan/Ventoy1/scripts/`, and `ventoy-2-key/`. Isolated peripheral utilities into `network_and_remote_tools/` with `/ntfs/scripts/README.md`.
4. **Automated Verification:** Added Tests 8 and 9 to `verify_ventoy2.sh` to validate FAT script presence and OverlayFS `/upper` integrity on every audit pass.
