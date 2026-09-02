# Rescuezilla Live Persistence Overlay Files
These files are pre-loaded inside `rescuezilla-persistence.dat` on the Ventoy partition:

1. `mount_ntfs_startup.sh` (deployed to `/usr/local/bin/`): Auto-mounts the USB NTFS partition (`sdb4`) and symlinks it to `~/ntfs_usb`.
2. `mount-ntfs.desktop` (deployed to `/home/ubuntu/.config/autostart/`): Triggers the auto-mount script when the graphical desktop starts.
3. `Run_Backup_CLI.desktop` & `Post_Backup_Wizard.desktop` (deployed to `/home/ubuntu/Desktop/`): Instant desktop launchers for the backup and diagnostics wizards.
