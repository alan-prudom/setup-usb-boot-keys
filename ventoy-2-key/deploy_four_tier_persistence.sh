#!/usr/bin/env bash
# ==============================================================================
# deploy_four_tier_persistence.sh
# Deploys Four-Tier Redundancy into rescuezilla-persistence.dat
# Handles modern Ubuntu Casper OverlayFS (writes to /upper and root)
# ==============================================================================
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find persistence container
IMG=""
for candidate in \
    "/media/alan/Ventoy1/rescuezilla-persistence.dat" \
    "/media/alan/Ventoy/rescuezilla-persistence.dat" \
    "${SCRIPT_DIR}/rescuezilla-persistence.dat"; do
    if [ -f "$candidate" ]; then
        IMG="$candidate"
        break
    fi
done

if [ -z "$IMG" ]; then
    IMG=$(find /media /mnt -name "rescuezilla-persistence.dat" 2>/dev/null | head -n 1)
fi

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "Error: rescuezilla-persistence.dat not found."
    exit 1
fi

MNT="/mnt/rescue_persist"
echo "Mounting persistence image $IMG to $MNT..."
mkdir -p "$MNT"
mount -o loop "$IMG" "$MNT"

cleanup() {
    echo "Flushing writes and unmounting $MNT..."
    sync
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Define targets: BOTH /upper (OverlayFS active root) and root (raw container)
# ------------------------------------------------------------------------------
TARGET_DIRS=("$MNT")
if [ -d "$MNT/upper" ]; then
    TARGET_DIRS+=("$MNT/upper")
else
    mkdir -p "$MNT/upper"
    TARGET_DIRS+=("$MNT/upper")
fi

echo "Deploying redundancy across layers: ${TARGET_DIRS[*]}"

# Find SSH identity key
SSH_KEY=""
for key_cand in "/home/alan/.ssh/id_rsa" "${SCRIPT_DIR}/id_rsa" "/root/.ssh/id_rsa"; do
    if [ -f "$key_cand" ]; then
        SSH_KEY="$key_cand"
        break
    fi
done

for TDIR in "${TARGET_DIRS[@]}"; do
    echo "-> Deploying to $TDIR..."

    # 1. Tier 1: Embedded Root Scripts (/scripts and /usr/local/bin)
    mkdir -p "$TDIR/scripts" "$TDIR/usr/local/bin"
    for script_file in \
        "run_rescuezilla_backup_cli.sh" \
        "post-backup-wizard.sh" \
        "sda_rescue_backup.sh" \
        "sda5_rescue_backup.sh" \
        "mount_home40_backup.sh" \
        "mount_fat_and_hdd.sh" \
        "rescue_suite_launcher.sh"; do
        if [ -f "${SCRIPT_DIR}/${script_file}" ]; then
            cp "${SCRIPT_DIR}/${script_file}" "$TDIR/scripts/"
            chmod +x "$TDIR/scripts/${script_file}"
            ln -sf "/scripts/${script_file}" "$TDIR/usr/local/bin/${script_file}"
        fi
    done

    # 2. Tier 2: Startup Mount Automation Script
    cat << 'INNER_EOF' > "$TDIR/usr/local/bin/mount_storage_startup.sh"
#!/usr/bin/env bash
# mount_storage_startup.sh - Resilient storage auto-mount for Rescuezilla Live
LOG_FILE="/var/log/startup_storage.log"
USER_LOG="/home/ubuntu/startup_storage.log"
exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Rescuezilla Storage Mount Task"

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
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/shared_fat
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/ntfs_usb
    ln -sfn "$ACTUAL_MOUNT" /home/ubuntu/Desktop/SHARED_FAT_Storage
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
INNER_EOF
    chmod +x "$TDIR/usr/local/bin/mount_storage_startup.sh"
    ln -sf "/usr/local/bin/mount_storage_startup.sh" "$TDIR/usr/local/bin/mount_ntfs_startup.sh"

    # 3. Tier 3: Multi-Layer Autostart (Systemd service + XDG + Openbox)
    # A) Systemd system unit
    mkdir -p "$TDIR/etc/systemd/system/multi-user.target.wants"
    cat << 'SVC_EOF' > "$TDIR/etc/systemd/system/mount-storage-startup.service"
[Unit]
Description=Rescuezilla Live Storage Auto-Mount
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mount_storage_startup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC_EOF
    chmod 644 "$TDIR/etc/systemd/system/mount-storage-startup.service"
    ln -sf "/etc/systemd/system/mount-storage-startup.service" "$TDIR/etc/systemd/system/multi-user.target.wants/mount-storage-startup.service"

    # B) XDG Desktop Autostart
    mkdir -p "$TDIR/etc/xdg/autostart"
    cat << 'XDG_EOF' > "$TDIR/etc/xdg/autostart/mount-storage-startup.desktop"
[Desktop Entry]
Type=Application
Name=Mount Storage Startup
Exec=/usr/local/bin/mount_storage_startup.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
XDG_EOF
    chmod 644 "$TDIR/etc/xdg/autostart/mount-storage-startup.desktop"

    # C) Openbox native autostart
    # Clean any user-level calls to mount_storage_startup.sh (already managed by system-level systemd service)
    for ob_file in "$TDIR/etc/xdg/openbox/autostart" "$TDIR/home/ubuntu/.config/openbox/autostart" "$TDIR/home/ubuntu/.config/openbox/autostart.sh"; do
        if [ -f "$ob_file" ]; then
            sed -i '/mount_storage_startup/d' "$ob_file" 2>/dev/null || true
        fi
    done

    # 4. Tier 4: Desktop Launchers
    mkdir -p "$TDIR/home/ubuntu/Desktop"
    # Remove obsolete desktop entries that produce "no valid Exec line" error
    rm -f "$TDIR/home/ubuntu/Desktop/mount-ntfs.desktop" "$TDIR/etc/xdg/autostart/mount-ntfs.desktop"

    if [ -d "${SCRIPT_DIR}/persistence_startup" ]; then
        cp "${SCRIPT_DIR}/persistence_startup/"*.desktop "$TDIR/home/ubuntu/Desktop/"
        find "$TDIR/home/ubuntu/Desktop" -maxdepth 1 -type f -name "*.desktop" -exec chmod +x {} +
    fi

    # 5. SSH Identity Key
    mkdir -p "$TDIR/home/ubuntu/.ssh"
    if [ -n "$SSH_KEY" ]; then
        cp "$SSH_KEY" "$TDIR/home/ubuntu/.ssh/id_rsa"
        cp "$SSH_KEY" "$TDIR/scripts/id_rsa"
        chmod 600 "$TDIR/home/ubuntu/.ssh/id_rsa" "$TDIR/scripts/id_rsa"
    fi

    # Set proper permissions for user ubuntu
    chown -R 1000:1000 "$TDIR/home/ubuntu" 2>/dev/null || true
done

echo "Four-tier persistence deployment completed successfully."
