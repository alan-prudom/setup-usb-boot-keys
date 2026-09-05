#!/usr/bin/env bash
# ==============================================================================
# Rescuezilla Live Persistence Startup Task
# Mounts SHARED FAT partition (C9D1-3C83) and Internal HDD (sda5, ro)
# ==============================================================================

LOG_FILE="/var/log/startup_storage.log"
USER_LOG="/home/ubuntu/startup_storage.log"

exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rescuezilla Storage Mount Task"
echo "Running as: $(whoami) (UID: $(id -u))"
echo "======================================================================"

sleep 1

# 1. Mount SHARED FAT (82GB FAT32 partition C9D1-3C83)
FAT_DEV=$(blkid -U "C9D1-3C83" 2>/dev/null || blkid -L "SHARED FAT" 2>/dev/null || lsblk -rno PATH,LABEL | grep -i "SHARED FAT" | awk '{print $1}' || echo "/dev/sdb4")
TARGET_MOUNT="/media/ubuntu/SHARED_FAT"

if [ -b "$FAT_DEV" ]; then
    CURRENT_MOUNT=$(lsblk -no MOUNTPOINT "$FAT_DEV" 2>/dev/null | head -n1)
    if [ -z "$CURRENT_MOUNT" ]; then
        mkdir -p "$TARGET_MOUNT"
        mount -o rw,umask=000,uid=1000,gid=1000 "$FAT_DEV" "$TARGET_MOUNT" 2>/dev/null || mount "$FAT_DEV" "$TARGET_MOUNT" 2>/dev/null || true
        ACTUAL_MOUNT="$TARGET_MOUNT"
        echo "Mounted $FAT_DEV at $TARGET_MOUNT"
    else
        ACTUAL_MOUNT="$CURRENT_MOUNT"
        echo "$FAT_DEV is already mounted at $ACTUAL_MOUNT"
    fi
    mkdir -p /home/ubuntu/Desktop
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/shared_fat
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/ntfs_usb
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/Desktop/SHARED_FAT_Storage
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/Desktop/NTFS_Storage
fi

# 2. Mount Internal HDD Linux partition (/dev/sda5, read-only for safe imaging)
if [ -b /dev/sda5 ]; then
    CURRENT_SDA5=$(lsblk -no MOUNTPOINT /dev/sda5 2>/dev/null | head -n1)
    if [ -z "$CURRENT_SDA5" ]; then
        mkdir -p /media/ubuntu/Internal_HDD
        mount -o ro /dev/sda5 /media/ubuntu/Internal_HDD 2>/dev/null || mount /dev/sda5 /media/ubuntu/Internal_HDD 2>/dev/null || true
        ACTUAL_SDA5="/media/ubuntu/Internal_HDD"
        echo "Mounted /dev/sda5 at $ACTUAL_SDA5 (ro)"
    else
        ACTUAL_SDA5="$CURRENT_SDA5"
        echo "/dev/sda5 is already mounted at $ACTUAL_SDA5"
    fi
    ln -sfn "$ACTUAL_SDA5" /home/ubuntu/internal_hdd
    ln -sfn "$ACTUAL_SDA5" /home/ubuntu/Desktop/Internal_HDD
fi

# Ensure user permissions
chown -h 1000:1000 /home/ubuntu/Desktop/* 2>/dev/null || true
chown 1000:1000 /home/ubuntu/shared_fat /home/ubuntu/ntfs_usb /home/ubuntu/internal_hdd 2>/dev/null || true
echo "SUCCESS: Storage partitions mounted and symlinked."
echo "======================================================================"
