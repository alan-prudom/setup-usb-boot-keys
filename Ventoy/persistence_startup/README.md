# Rescuezilla Live Persistence Overlay Files
These files are pre-loaded inside `rescuezilla-persistence.dat` on the Ventoy partition (`/dev/sdb1`):

### 1. `mount_ntfs_startup.sh` (Deployed to `/usr/local/bin/`)
* **Role:** Auto-mounts the USB NTFS partition (`/dev/sdb4`, UUID `2C95D29B2DF0500E`) and symlinks it to `~/ntfs_usb` and `~/Desktop/NTFS_Storage`.
* **Desktop-Native Mounting:** Uses `udisksctl mount -b "$NTFS_DEV"` instead of raw kernel `mount`. This ensures GNOME Disks and PCManFM file manager recognize the mount natively and eliminates directory lock/collision errors.
* **Persistent Logging:** All execution steps and errors are logged via `tee` directly to `/var/log/startup_ntfs.log` and `~/startup_ntfs.log`.

### 2. `mount-ntfs.desktop` (Deployed to `/home/ubuntu/.config/autostart/`)
* **Role:** XDG autostart entry that triggers `mount_ntfs_startup.sh` as soon as the graphical Openbox desktop loads.

### 3. `Run_Backup_CLI.desktop` & `Post_Backup_Wizard.desktop` (Deployed to `/home/ubuntu/Desktop/`)
* **Role:** Instant desktop launchers for the backup assistant and diagnostic wizard.
* **Window Persistence:** Configured with `xfce4-terminal --hold --geometry=105x32` so the terminal window stays open even if an error occurs, allowing the user to review the diagnostic trace.
