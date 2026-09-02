#!/usr/bin/env bash
# ==============================================================================
# Rescuezilla Live Persistence Startup Task
# Auto-mounts USB NTFS partition and prepares backup scripts & SSH keys
# ==============================================================================

sleep 2

# Target mount location
NTFS_MOUNT="/media/ubuntu/2C95D29B2DF0500E"
mkdir -p "$NTFS_MOUNT"

# Find device by UUID or pattern
NTFS_DEV=$(blkid -U "2C95D29B2DF0500E" 2>/dev/null || blkid -L "2C95D29B2DF0500E" 2>/dev/null || lsblk -no PATH,UUID | grep -i "2C95D29B2DF0500E" | awk '{print $1}' || echo "")

if [ -z "$NTFS_DEV" ]; then
    for dev in /dev/sd[a-z]4 /dev/sd[a-z]3; do
        if [ -b "$dev" ] && blkid "$dev" | grep -iE "ntfs|fuseblk" >/dev/null 2>&1; then
            NTFS_DEV="$dev"
            break
        fi
    done
fi

if [ -n "$NTFS_DEV" ] && [ -b "$NTFS_DEV" ]; then
    if ! mountpoint -q "$NTFS_MOUNT"; then
        mount -t ntfs-3g -o rw,umask=000 "$NTFS_DEV" "$NTFS_MOUNT" 2>/dev/null || \
        mount -o rw,umask=000 "$NTFS_DEV" "$NTFS_MOUNT" 2>/dev/null || true
    fi

    # Set up convenience links
    mkdir -p /home/ubuntu/Desktop
    ln -sf "$NTFS_MOUNT" /home/ubuntu/ntfs_usb
    ln -sf "$NTFS_MOUNT" /home/ubuntu/Desktop/NTFS_Storage

    # Secure SSH key
    if [ -f "${NTFS_MOUNT}/id_rsa" ]; then
        chmod 600 "${NTFS_MOUNT}/id_rsa"
    fi

    # Desktop notification
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -i drive-harddisk "Storage Ready" "USB NTFS partition mounted at ~/ntfs_usb" 2>/dev/null || true
    fi
fi
