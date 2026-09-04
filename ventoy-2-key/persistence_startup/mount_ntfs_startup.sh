#!/usr/bin/env bash
# ==============================================================================
# Rescuezilla Live Persistence Startup Task
# Mounts USB NTFS partition at /media/ubuntu/ with full user permissions
# ==============================================================================

LOG_FILE="/var/log/startup_ntfs.log"
USER_LOG="/home/ubuntu/startup_ntfs.log"

exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rescuezilla NTFS Mount Task"
echo "Running as: $(whoami) (UID: $(id -u))"
echo "======================================================================"

sleep 1

NTFS_UUID="2C95D29B2DF0500E"
NTFS_DEV=""

# 1. Locate device
if command -v blkid >/dev/null 2>&1; then
    NTFS_DEV=$(sudo blkid -U "$NTFS_UUID" 2>/dev/null || blkid -U "$NTFS_UUID" 2>/dev/null || echo "")
fi

if [ -z "$NTFS_DEV" ]; then
    NTFS_DEV=$(lsblk -rno PATH,UUID | grep -i "$NTFS_UUID" | awk '{print $1}' || echo "")
fi

if [ -z "$NTFS_DEV" ]; then
    for dev in /dev/sdb4 /dev/sda4 /dev/sdb3; do
        if [ -b "$dev" ]; then
            fstype=$(lsblk -no FSTYPE "$dev" 2>/dev/null || echo "")
            if echo "$fstype" | grep -iE "ntfs|fuseblk" >/dev/null 2>&1; then
                NTFS_DEV="$dev"
                break
            fi
        fi
    done
fi

echo "Detected NTFS Block Device: '${NTFS_DEV:-NOT_FOUND}'"

if [ -n "$NTFS_DEV" ] && [ -b "$NTFS_DEV" ]; then
    TARGET_MOUNT="/media/ubuntu/${NTFS_UUID}"
    mkdir -p "$TARGET_MOUNT"
    chmod 777 /media/ubuntu 2>/dev/null || true
    
    if ! mountpoint -q "$TARGET_MOUNT"; then
        echo "Mounting $NTFS_DEV at $TARGET_MOUNT (read-write, user-accessible)..."
        mount -t ntfs-3g -o rw,umask=000,uid=1000,gid=1000,force "$NTFS_DEV" "$TARGET_MOUNT" 2>&1 || \
        mount -o rw,umask=000 "$NTFS_DEV" "$TARGET_MOUNT" 2>&1 || true
    else
        echo "Device is already mounted at $TARGET_MOUNT."
    fi

    # Create symlinks in user profile
    mkdir -p /home/ubuntu/Desktop
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/ntfs_usb
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/Desktop/NTFS_Storage
    chown -h 999:999 /home/ubuntu/ntfs_usb /home/ubuntu/Desktop/NTFS_Storage 2>/dev/null || \
    chown -h 1000:1000 /home/ubuntu/ntfs_usb /home/ubuntu/Desktop/NTFS_Storage 2>/dev/null || true
    
    echo "Created user symlink: ~/ntfs_usb -> $TARGET_MOUNT"
    
    if [ -f "${TARGET_MOUNT}/id_rsa" ]; then
        chmod 600 "${TARGET_MOUNT}/id_rsa" 2>/dev/null || true
    fi
    
    echo "SUCCESS: NTFS partition mounted and symlinked."
fi
echo "======================================================================"
