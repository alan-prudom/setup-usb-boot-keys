# Rescuezilla Live Persistence Overlay Architecture

These files and configurations are pre-loaded inside `rescuezilla-persistence.dat` on the Ventoy partition (`/dev/sdb1`):

### 1. Embedded Top-Level Scripts (`/scripts/` & `~/scripts/`)
* **Role:** Completely decouples script execution from external partition mounting.
* **Included Components:**
  * `/scripts/run_rescuezilla_backup_cli.sh` (Backup Assistant runner)
  * `/scripts/post-backup-wizard.sh` (Post-backup diagnostic wizard)
  * `/scripts/id_rsa` & `~/.ssh/id_rsa` (Pre-installed SSH credentials, `chmod 600`)
  * `/scripts/ventoy_boot_repair_guide.md` (Offline reference manual)
* **Desktop Folder:** Accessible via the `~/Desktop/Scripts_Folder` symlink.

### 2. Desktop Launchers (`/home/ubuntu/Desktop/`)
* **`Run_Backup_CLI.desktop`:** Launches `sudo bash /scripts/run_rescuezilla_backup_cli.sh`.
* **`Post_Backup_Wizard.desktop`:** Launches `sudo bash /scripts/post-backup-wizard.sh`.
* **Window Persistence:** Configured with `xfce4-terminal --hold --geometry=105x32` so terminal windows remain open upon completion or error.

### 3. Startup Mount Automation (`mount_storage_startup.sh`)
* **Deployed to:** `/upper/usr/local/bin/mount_storage_startup.sh` (with symlink `/usr/local/bin/mount_ntfs_startup.sh` for backward compatibility).
* **FAT32 Shared Partition Mount:** Mounts `/dev/sdb4` (UUID `C9D1-3C83`, `LABEL="SHARED FAT"`) at `/media/ubuntu/SHARED_FAT` with `uid=1000,gid=1000,umask=000`, granting user `ubuntu` full graphical read/write access without permission barriers. Creates desktop shortcut `/home/ubuntu/Desktop/SHARED_FAT_Storage` and symlinks `~/shared_fat` and `~/ntfs_usb`.
* **Internal HDD Mount:** Mounts `/dev/sda5` read-only at `/media/ubuntu/Internal_HDD` with desktop shortcut `/home/ubuntu/Desktop/Internal_HDD`.
* **Persistent Logging:** All execution steps and block device detection logs are mirrored to `/var/log/startup_storage.log` and `~/startup_storage.log`.

### 4. Multi-Layer Startup Triggers (OverlayFS `/upper/`)
* **Casper OverlayFS:** All persistent artifacts are deployed into `/upper/` inside `rescuezilla-persistence.dat` to ensure visibility under Casper's OverlayFS root union.
* **Systemd Unit:** `/upper/etc/systemd/system/mount-storage-startup.service` (enabled in `multi-user.target.wants/`).
* **Openbox Native:** Appended to `/upper/home/ubuntu/.config/openbox/autostart`, `autostart.sh`, and `/upper/etc/xdg/openbox/autostart`.
* **XDG Desktop Autostart:** `/upper/etc/xdg/autostart/mount-storage-startup.desktop`.
