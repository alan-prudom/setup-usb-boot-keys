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

### 3. Startup Mount Automation (`mount_ntfs_startup.sh`)
* **Deployed to:** `/usr/local/bin/mount_ntfs_startup.sh`
* **Direct User Mount:** Mounts `/dev/sdb4` (UUID `2C95D29B2DF0500E`) at `/media/ubuntu/2C95D29B2DF0500E` with `uid=1000,gid=1000,umask=000`, granting user `ubuntu` full graphical read/write access without permission barriers.
* **Persistent Logging:** All execution steps and block device detection logs are mirrored to `/var/log/startup_ntfs.log` and `~/startup_ntfs.log`.

### 4. Multi-Layer Startup Triggers
* **Systemd Unit:** `/etc/systemd/system/mount-ntfs.service` (enabled in `multi-user.target.wants/`).
* **Openbox Native:** Appended to `~/.config/openbox/autostart` and `/etc/xdg/openbox/autostart`.
* **XDG Fallback:** `~/.config/autostart/mount-ntfs.desktop`.
