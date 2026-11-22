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
    local p_boot=""
    local raw_p_boot
    if raw_p_boot=$(lsblk -rno PATH,LABEL 2>/dev/null); then
        # Parse lsblk output: find first PATH whose LABEL matches VTOYEFI or Ventoy
        while IFS=' ' read -r path label; do
            case "$label" in
                [Vv][Tt][Oo][Yy][Ee][Ff][Ii]|[Vv][Ee][Nn][Tt][Oo][Yy]*)
                    p_boot="$path"
                    break
                    ;;
            esac
        done <<< "$raw_p_boot"
    fi
    if [ -n "$p_boot" ]; then
        if dev=$(lsblk -no PKNAME "$p_boot" 2>/dev/null); then
            :
        else
            dev=""
        fi
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
        p4=""
        if ! p4=$(blkid -L "SHARED FAT" 2>/dev/null); then
            if ! p4=$(blkid -U "2C95D29B2DF0500E" 2>/dev/null); then
                if ! p4=$(blkid -U "C9D1-3C83" 2>/dev/null); then
                    p4=""
                fi
            fi
        fi
    fi

    if [ -z "$p4" ] \
        || [ ! -b "$p4" ]; then
        echo "Error: Data partition (Partition 4) could not be detected." >&2
        return 1
    fi

    DETECTED_P4_DEV="$p4"
    if ! DETECTED_P4_FS=$(blkid -s TYPE -o value "$p4" 2>/dev/null); then
        DETECTED_P4_FS="unknown"
    fi
    if ! DETECTED_P4_UUID=$(blkid -s UUID -o value "$p4" 2>/dev/null); then
        DETECTED_P4_UUID=""
    fi
    if ! DETECTED_P4_LABEL=$(blkid -s LABEL -o value "$p4" 2>/dev/null); then
        DETECTED_P4_LABEL=""
    fi

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
    if ! detect_data_partition; then
        return 1
    fi

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

# Dynamically detect hardware machine model (e.g. HP-EliteBook-8470p, HP-ZBook-15u-G5)
detect_machine_model() {
    local model=""
    for p in "/sys/class/dmi/id/product_name" "/sys/devices/virtual/dmi/id/product_name"; do
        if [ -f "$p" ]; then
            local raw_model
            raw_model=$(tr -s ' \t' '-' < "$p")
            model=$(tr -cd '[:alnum:]-_' <<< "$raw_model")
            if [ -n "$model" ] \
                && [ "$model" != "None" ] \
                && [ "$model" != "System-Product-Name" ]; then
                echo "$model"
                return 0
            fi
        fi
    done
    local host
    if ! host=$(hostname -s 2>/dev/null); then
        host="Host"
    fi
    echo "$host"
}

