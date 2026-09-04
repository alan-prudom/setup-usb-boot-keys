#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

REPO_DIR="/media/alan/26448526-203a-40ab-ae59-980a7d107903/home/alan/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy"
IMG="/media/alan/Ventoy1/rescuezilla-persistence.dat"
MNT="/mnt/rescue_persist"

echo "Mounting persistence image $IMG..."
mkdir -p "$MNT"
mount -o loop "$IMG" "$MNT"

echo "Deploying Four-Tier Architecture to persistence container..."

# 1. Tier 1: Embedded Root Scripts (/scripts and /usr/local/bin)
mkdir -p "$MNT/scripts" "$MNT/usr/local/bin"
cp "$REPO_DIR/run_rescuezilla_backup_cli.sh" "$MNT/scripts/"
cp "$REPO_DIR/post-backup-wizard.sh" "$MNT/scripts/"
chmod +x "$MNT/scripts/"*.sh
ln -sf /scripts/run_rescuezilla_backup_cli.sh "$MNT/usr/local/bin/run_rescuezilla_backup_cli.sh"
ln -sf /scripts/post-backup-wizard.sh "$MNT/usr/local/bin/post-backup-wizard.sh"

# 2. Tier 2: Startup Mount Automation (FAT32 partition C9D1-3C83 & SHARED FAT)
cat << 'INNER_EOF' > "$MNT/usr/local/bin/mount_storage_startup.sh"
#!/usr/bin/env bash
LOG_FILE="/var/log/startup_storage.log"
USER_LOG="/home/ubuntu/startup_storage.log"
exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rescuezilla Storage Mount Task"

# Find 82GB FAT32 partition
FAT_DEV=$(blkid -U "C9D1-3C83" 2>/dev/null || blkid -L "SHARED FAT" 2>/dev/null || lsblk -rno PATH,LABEL | grep -i "SHARED FAT" | awk '{print $1}' || echo "/dev/sdb4")
TARGET_MOUNT="/media/ubuntu/SHARED_FAT"

if [ -b "$FAT_DEV" ]; then
    mkdir -p "$TARGET_MOUNT"
    mount -o rw,umask=000,uid=1000,gid=1000 "$FAT_DEV" "$TARGET_MOUNT" 2>/dev/null || true
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/shared_fat
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/Desktop/SHARED_FAT_Storage
    echo "Mounted $FAT_DEV at $TARGET_MOUNT"
fi

# Mount internal HDD linux partition if present (read-only for safe imaging)
if [ -b /dev/sda5 ]; then
    mkdir -p /media/ubuntu/Internal_HDD
    mount -o ro /dev/sda5 /media/ubuntu/Internal_HDD 2>/dev/null || true
    ln -sfn /media/ubuntu/Internal_HDD /home/ubuntu/Desktop/Internal_HDD
    echo "Mounted /dev/sda5 at /media/ubuntu/Internal_HDD (ro)"
fi

# Ensure user permissions
chown -R 1000:1000 /home/ubuntu/Desktop 2>/dev/null || true
INNER_EOF
chmod +x "$MNT/usr/local/bin/mount_storage_startup.sh"

# 3. Tier 3: Openbox Autostart (Rescuezilla native desktop window manager)
mkdir -p "$MNT/etc/xdg/openbox" "$MNT/home/ubuntu/.config/openbox"
echo "/usr/local/bin/mount_storage_startup.sh &" >> "$MNT/etc/xdg/openbox/autostart"
echo "/usr/local/bin/mount_storage_startup.sh &" >> "$MNT/home/ubuntu/.config/openbox/autostart"

# 4. Tier 4: Desktop Launchers with --hold
mkdir -p "$MNT/home/ubuntu/Desktop"
cp "$REPO_DIR/persistence_startup/Run_Backup_CLI.desktop" "$MNT/home/ubuntu/Desktop/"
cp "$REPO_DIR/persistence_startup/Post_Backup_Wizard.desktop" "$MNT/home/ubuntu/Desktop/"
chmod +x "$MNT/home/ubuntu/Desktop/"*.desktop

# Copy SSH key to persistence overlay
mkdir -p "$MNT/home/ubuntu/.ssh"
if [ -f "/home/alan/.ssh/id_rsa" ]; then
    cp "/home/alan/.ssh/id_rsa" "$MNT/home/ubuntu/.ssh/id_rsa"
    cp "/home/alan/.ssh/id_rsa" "$MNT/scripts/id_rsa"
    chmod 600 "$MNT/home/ubuntu/.ssh/id_rsa" "$MNT/scripts/id_rsa"
fi

chown -R 1000:1000 "$MNT/home/ubuntu" 2>/dev/null || true

echo "Flushing and unmounting..."
sync
umount "$MNT"
rmdir "$MNT"
echo "Four-tier architecture deployed cleanly into persistence container."
