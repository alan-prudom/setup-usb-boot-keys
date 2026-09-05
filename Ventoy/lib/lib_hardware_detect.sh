#!/usr/bin/env bash
# ==============================================================================
# lib_hardware_detect.sh
# Dynamic Hardware & Partition Geometry Detection Library
# Decouples common scripts from hardcoded partition UUIDs, labels, and filesystems
# ==============================================================================

# Find the primary Ventoy USB block device dynamically
detect_usb_device() {
    local dev=""
    # 1. Search for partition with label VTOYEFI or Ventoy
    local p_boot
    p_boot=$(lsblk -rno PATH,LABEL | grep -iE "VTOYEFI|Ventoy" | awk '{print $1}' | head -n 1)
    if [ -n "$p_boot" ]; then
        dev=$(lsblk -no PKNAME "$p_boot" 2>/dev/null || echo "")
        if [ -n "$dev" ]; then
            echo "/dev/$dev"
            return 0
        fi
    fi
    # 2. Fallback to /dev/sdb if present
    if [ -b "/dev/sdb" ]; then
        echo "/dev/sdb"
        return 0
    fi
    echo ""
    return 1
}

# Resolve partition 4 properties dynamically
detect_data_partition() {
    local usb_dev="${1:-$(detect_usb_device)}"
    local p4="${usb_dev}4"

    if [ ! -b "$p4" ]; then
        # Try finding by known labels or UUIDs
        p4=$(blkid -L "SHARED FAT" 2>/dev/null || blkid -U "2C95D29B2DF0500E" 2>/dev/null || blkid -U "C9D1-3C83" 2>/dev/null || echo "")
    fi

    if [ -z "$p4" ] || [ ! -b "$p4" ]; then
        echo "Error: Data partition (Partition 4) could not be detected." >&2
        return 1
    fi

    DETECTED_P4_DEV="$p4"
    DETECTED_P4_FS=$(blkid -s TYPE -o value "$p4" 2>/dev/null || echo "unknown")
    DETECTED_P4_UUID=$(blkid -s UUID -o value "$p4" 2>/dev/null || echo "")
    DETECTED_P4_LABEL=$(blkid -s LABEL -o value "$p4" 2>/dev/null || echo "")

    case "$DETECTED_P4_FS" in
        ntfs|fuseblk)
            DETECTED_P4_DRIVER="mount -t ntfs-3g"
            DETECTED_P4_OPTS="rw,umask=000,uid=1000,gid=1000,force"
            DETECTED_P4_TARGET="/media/ubuntu/${DETECTED_P4_UUID:-NTFS_STORAGE}"
            DETECTED_P4_PROFILE="key1_ntfs"
            ;;
        vfat|fat32|msdos)
            DETECTED_P4_DRIVER="mount -t vfat"
            DETECTED_P4_OPTS="rw,umask=000,uid=1000,gid=1000,iocharset=utf8"
            DETECTED_P4_TARGET="/media/ubuntu/${DETECTED_P4_LABEL:-SHARED_FAT}"
            DETECTED_P4_PROFILE="key2_fat32"
            ;;
        *)
            DETECTED_P4_DRIVER="mount"
            DETECTED_P4_OPTS="defaults"
            DETECTED_P4_TARGET="/media/ubuntu/STORAGE"
            DETECTED_P4_PROFILE="generic"
            ;;
    esac

    export DETECTED_P4_DEV DETECTED_P4_FS DETECTED_P4_UUID DETECTED_P4_LABEL
    export DETECTED_P4_DRIVER DETECTED_P4_OPTS DETECTED_P4_TARGET DETECTED_P4_PROFILE
    return 0
}

# Mount the detected data partition cleanly with user permissions
mount_detected_data_partition() {
    local custom_mount="${1:-}"
    detect_data_partition || return 1

    local mnt="${custom_mount:-$DETECTED_P4_TARGET}"
    mkdir -p "$mnt"

    if mountpoint -q "$mnt"; then
        echo "Partition $DETECTED_P4_DEV is already mounted at $mnt"
        return 0
    fi

    echo "Mounting $DETECTED_P4_DEV ($DETECTED_P4_FS) -> $mnt..."
    $DETECTED_P4_DRIVER -o $DETECTED_P4_OPTS "$DETECTED_P4_DEV" "$mnt"
    return $?
}
