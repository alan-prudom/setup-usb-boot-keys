# Rescuezilla Live Persistence Overlay Architecture

These files and configurations are pre-loaded inside `rescuezilla-persistence.dat` on the Ventoy partition (`/dev/sdb1`):

### 1. Embedded Top-Level Scripts (`/scripts/` & `~/scripts/`)
* **Role:** Completely decouples script execution from external partition mounting.
* **Included Components:**
  * `/scripts/run_rescuezilla_backup_cli.sh` (Backup Assistant runner with dynamic DMI model naming & `--rescue` mode)
  * `/scripts/post-backup-wizard.sh` (Post-backup diagnostic wizard with bad sector counting)
  * `/scripts/export_diagnostic_bundle.sh` (Universal diagnostic bundler)
  * `/scripts/rescue_suite_launcher.sh` (Unified Rescue Suite launcher)
  * `/scripts/lib/lib_hardware_detect.sh` (Dynamic hardware, DMI model, and partition detection)
  * `/scripts/id_rsa` & `~/.ssh/id_rsa` (Pre-installed SSH credentials, `chmod 600`)
  * `/scripts/ventoy_boot_repair_guide.md` (Offline reference manual)
* **Desktop Folder:** Accessible via the `~/Desktop/Scripts_Folder` symlink.

### 2. Desktop Launchers (`/home/ubuntu/Desktop/`)
* **`Live_Rescue_Hub.desktop`:** Launches `bash /usr/local/bin/sync_and_launch.sh /scripts/live_rescue_hub.sh` (Master Live Menu).
* **`Rescue_Suite.desktop`:** Launches `sudo bash /usr/local/bin/sync_and_launch.sh /scripts/rescue_suite_launcher.sh` (Unified 10-function Suite).
* **`Run_Backup_CLI.desktop`:** Launches `sudo bash /usr/local/bin/sync_and_launch.sh /scripts/run_rescuezilla_backup_cli.sh`.
* **`Post_Backup_Wizard.desktop`:** Launches `sudo bash /usr/local/bin/sync_and_launch.sh /scripts/post-backup-wizard.sh`.
* **Self-Healing Wrapper (`sync_and_launch.sh`):** Deployed to `/usr/local/bin/sync_and_launch.sh`; automatically synchronizes fresh scripts from Partition 4/USB into `/scripts/` before executing them, eliminating status 126 errors.
* **Window Persistence:** Configured with `xfce4-terminal --hold` so terminal windows remain open upon completion or error.

### 3. Startup Mount Automation (`mount_storage_startup.sh`)
* **Deployed to:** `/usr/local/bin/mount_storage_startup.sh` (aliased to `mount_ntfs_startup.sh`).
* **Dynamic User Mount:** Resolves Partition 4 whether NTFS (`ntfs-3g`) or FAT32 (`vfat`), granting user `ubuntu` full graphical read/write access without permission barriers.
* **Persistent Logging:** All execution steps and block device detection logs are mirrored to `/var/log/startup_storage.log` and `~/startup_storage.log`.

### 4. Multi-Layer Startup Triggers
* **Systemd Unit:** `/etc/systemd/system/mount-storage-startup.service` (enabled in `multi-user.target.wants/`).
* **Openbox Native:** Managed at system level without duplicate user sessions.
* **XDG Fallback:** `/etc/xdg/autostart/mount-storage-startup.desktop`.
