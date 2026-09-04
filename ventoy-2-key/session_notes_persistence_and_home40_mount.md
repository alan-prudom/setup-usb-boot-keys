# Session Notes: Rescuezilla Persistence Repair, Storage Auto-Mount & home40 SSHFS Automation

**Date of Record:** September 4, 2026  
**Host Machine:** HP ZBook 15u G5 (`alan-USB-zbook`)  
**Target Hardware:** 128 GB Multi-Boot Ventoy USB (`/dev/sdb`) & 1 TB Internal HDD (`/dev/sda`)  
**Sub-Repository:** `setup-usb-boot-keys/ventoy-2-key`

---

## 1. Problem Investigation & Root Causes

### 1.1 The Unmounted Large HDD Partition
* **Symptom:** On booted USB environments, the large ~608 GB Linux partition on `/dev/sda5` was not mounted.
* **Findings:**
  - Neither Ubuntu live nor USB-booted environments automatically mount fixed internal drives without an explicit `fstab` entry or explicit mount action.
  - The partition `/dev/sda5` (UUID `26448526-203a-40ab-ae59-980a7d107903`) has a healthy ext4 filesystem with 429 GB used and 101 GB available. All Git projects (`~/GitHub`, `~/projects`, `~/ZKGIT`) are intact.
  - Mounting it cleanly via `udisksctl mount -b /dev/sda5` or read-only mount via `mount -o ro` succeeded immediately.

### 1.2 Missing Scripts & Auto-Mount Failure in Rescuezilla Live
* **Symptom:** When booting Rescuezilla with persistence, neither the 82 GB FAT partition nor any custom scripts appeared on the desktop.
* **Root Causes:**
  1. **Empty Persistence Overlay:** The `rescuezilla-persistence.dat` container on `/media/alan/Ventoy1/` had only 11 inodes (blank template). No previous customizations had been committed to its `casper-rw` filesystem.
  2. **Window Manager Autostart Mismatch:** Rescuezilla runs **Openbox**, not GNOME/XFCE. XDG `.desktop` files in `~/.config/autostart/` are ignored. Autostart commands must reside in `~/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
  3. **Filesystem and UUID Mismatch:** Older scripts targeted an NTFS UUID with `ntfs-3g`. The actual 82 GB partition (`/dev/sdb4`) is formatted as **FAT32 / vfat** (UUID `C9D1-3C83`, Label `SHARED FAT`).

### 1.3 Disconnected `~/GitHub` Symlink on USB OS
* **Symptom:** On the active booted USB OS (`/dev/sdb3`), `~/GitHub` linked to `/home/alan/mnt/apelite/files_zbook/GitHub`, which was disconnected.
* **Resolution:** Re-established the SSHFS mount to `alan@192.168.1.34:/media/alan/home40` and installed a persistent systemd user service (`mount-home40.service`).

---

## 2. Solutions Implemented

### 2.1 Four-Tier Architecture Deployed to `rescuezilla-persistence.dat`
1. **Tier 1 (Embedded Root Binaries):**
   - Scripts copied directly into `/scripts/` and symlinked to `/usr/local/bin/` inside the persistence overlay:
     - `run_rescuezilla_backup_cli.sh`
     - `post-backup-wizard.sh`
   - Zero partition dependency eliminates status 127 errors.
2. **Tier 2 (Storage Auto-Mounting):**
   - Installed `/usr/local/bin/mount_storage_startup.sh`.
   - Mounts `SHARED FAT` (`UUID=C9D1-3C83`) at `/media/ubuntu/SHARED_FAT` with `umask=000,uid=1000,gid=1000`.
   - Mounts internal HDD `/dev/sda5` read-only at `/media/ubuntu/Internal_HDD`.
3. **Tier 3 (Openbox Autostart Hooks):**
   - Added `/usr/local/bin/mount_storage_startup.sh &` to `/home/ubuntu/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
4. **Tier 4 (Desktop Launchers):**
   - Placed `Run_Backup_CLI.desktop` and `Post_Backup_Wizard.desktop` onto `/home/ubuntu/Desktop/` with `--hold` flag enabled.
   - Pre-installed SSH keys into `/home/ubuntu/.ssh/id_rsa` and `/scripts/id_rsa` (`chmod 600`).

### 2.2 Persistent home40 Mount Service
* File: `~/.config/systemd/user/mount-home40.service`
* Automatically connects `alan@192.168.1.34:/media/alan/home40` to `/home/alan/mnt/apelite` on login with auto-reconnect (`ServerAliveInterval=15`).

---

## 3. Registered Artifacts in `ventoy-2-key/`
1. `mount_fat_and_hdd.sh` — standalone mounting helper.
2. `mount-home40.service` — systemd user service unit.
3. `setup_rescuezilla_persistence.sh` — initial single-pass persistence setup script.
4. `deploy_four_tier_persistence.sh` — full Four-Tier deployment script.
5. `session_notes_persistence_and_home40_mount.md` — this technical reference.

---

## 4. OverlayFS Deployment Refinement & Script Alignment (September 4, 2026 Update)

* **OverlayFS Architecture (`upperdir=/cow/upper`):** Updated `deploy_four_tier_persistence.sh` to inject files into `/upper/` inside `rescuezilla-persistence.dat`. Files placed outside `/upper/` were invisible to the running live OS overlay union.
* **Operational Script Mirroring:** Mirrored `run_rescuezilla_backup_cli.sh`, `post-backup-wizard.sh`, `sda_rescue_backup.sh`, `sda5_rescue_backup.sh`, and `mount_home40_backup.sh` to `/ntfs/scripts/`, `/media/alan/Ventoy1/scripts/`, and `ventoy-2-key/`.
* **Tool Isolation:** Moved remote administration tools (`run_mosh`, `tailscale_setup.sh`) to `network_and_remote_tools/` with `/ntfs/scripts/README.md`.
* **Verification Suite:** Added automated tests for FAT scripts and OverlayFS `/upper` integrity in `verify_ventoy2.sh` (all 9 tests passing).
