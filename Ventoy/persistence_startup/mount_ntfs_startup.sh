#!/usr/bin/env bash
# ==============================================================================
# Rescuezilla Live Persistence Startup Task
# Robust NTFS Mount with UDisks2 and Full Persistence Logging
# ==============================================================================

LOG_FILE="/var/log/startup_ntfs.log"
USER_LOG="/home/ubuntu/startup_ntfs.log"

exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rescuezilla NTFS Mount Task"
echo "Running as: $(whoami) (UID: $(id -u))"
echo "======================================================================"

sleep 2

# 1. Locate NTFS Partition
NTFS_UUID="2C95D29B2DF0500E"
NTFS_DEV=""

# Try finding by UUID
if command -v blkid >/dev/null 2>&1; then
    NTFS_DEV=$(sudo blkid -U "$NTFS_UUID" 2>/dev/null || blkid -U "$NTFS_UUID" 2>/dev/null || echo "")
fi

# Fallback scan via lsblk
if [ -z "$NTFS_DEV" ]; then
    NTFS_DEV=$(lsblk -rno PATH,UUID | grep -i "$NTFS_UUID" | awk '{print $1}' || echo "")
fi

# Fallback scan partition list
if [ -z "$NTFS_DEV" ]; then
    for dev in /dev/sdb4 /dev/sda4 /dev/sdb3; do
        if [ -b "$dev" ]; then
            fstype=$(lsblk -no FSTYPE "$dev" 2>/dev/null || echo "")
            if echo "$fstype" | grep -iE "ntfs|fuseblk" >/dev/null 2>&1; then
                NTFS_DEV="$dev"
                echo "Found NTFS filesystem on $dev via fallback scan"
                break
            fi
        fi
    done
fi

echo "Detected NTFS Block Device: '${NTFS_DEV:-NOT_FOUND}'"

if [ -z "$NTFS_DEV" ] || [ ! -b "$NTFS_DEV" ]; then
    echo "ERROR: Unable to locate block device for UUID $NTFS_UUID"
    exit 1
fi

# 2. Check if already mounted
EXISTING_MOUNT=$(lsblk -no MOUNTPOINT "$NTFS_DEV" 2>/dev/null | grep -v "^$" | head -n 1 || echo "")

if [ -n "$EXISTING_MOUNT" ]; then
    echo "Device $NTFS_DEV is already mounted at: $EXISTING_MOUNT"
    TARGET_MOUNT="$EXISTING_MOUNT"
else
    echo "Attempting to mount $NTFS_DEV via udisksctl (Desktop-native)..."
    UDISKS_OUT=$(udisksctl mount -b "$NTFS_DEV" 2>&1 || true)
    echo "udisksctl output: $UDISKS_OUT"
    
    TARGET_MOUNT=$(lsblk -no MOUNTPOINT "$NTFS_DEV" 2>/dev/null | grep -v "^$" | head -n 1 || echo "")
    
    # Fallback to manual sudo mount if udisksctl failed
    if [ -z "$TARGET_MOUNT" ]; then
        echo "udisksctl mount unsuccessful. Falling back to sudo mount..."
        FALLBACK_DIR="/media/ubuntu/${NTFS_UUID}"
        sudo mkdir -p "$FALLBACK_DIR"
        sudo mount -t ntfs-3g -o rw,umask=000,force "$NTFS_DEV" "$FALLBACK_DIR" 2>&1 || \
        sudo mount -o rw,umask=000 "$NTFS_DEV" "$FALLBACK_DIR" 2>&1 || true
        TARGET_MOUNT="$FALLBACK_DIR"
    fi
fi

echo "Final Mount Point: '$TARGET_MOUNT'"

# 3. Create Convenience Symlinks and Permissions
if [ -n "$TARGET_MOUNT" ] && [ -d "$TARGET_MOUNT" ]; then
    mkdir -p /home/ubuntu/Desktop
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/ntfs_usb
    ln -sfn "$TARGET_MOUNT" /home/ubuntu/Desktop/NTFS_Storage
    echo "Created symlinks: ~/ntfs_usb -> $TARGET_MOUNT"
    
    if [ -f "${TARGET_MOUNT}/id_rsa" ]; then
        chmod 600 "${TARGET_MOUNT}/id_rsa" 2>/dev/null || true
        echo "Secured SSH key permissions on ${TARGET_MOUNT}/id_rsa (600)"
    fi
    
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -i drive-harddisk "NTFS Storage Ready" "Mounted at ${TARGET_MOUNT} (linked to ~/ntfs_usb)" 2>/dev/null || true
    fi
    echo "SUCCESS: NTFS Partition successfully initialized and linked."
else
    echo "FAILED: Could not establish a valid mount point for $NTFS_DEV."
    exit 2
fi

echo "======================================================================"
