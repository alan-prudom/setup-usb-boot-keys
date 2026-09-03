#!/usr/bin/env bash
# ==============================================================================
# Non-Destructive In-Place Upgrade Script for Ventoy 2 USB Key (/dev/sdb)
# ==============================================================================

set -euo pipefail

DEV="/dev/sdb"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENTOY_TAR="ventoy-1.0.99-linux.tar.gz"
VENTOY_URL="https://github.com/ventoy/Ventoy/releases/download/v1.0.99/${VENTOY_TAR}"

echo "======================================================================"
echo "          VENTOY 2 NON-DESTRUCTIVE UPGRADE WIZARD"
echo "======================================================================"

# Safety confirmation
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This upgrade script must be run with sudo/root privileges."
    echo "Usage: sudo $0"
    exit 1
fi

echo "Target Device: $DEV"
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$DEV"
echo "----------------------------------------------------------------------"
echo "ATTENTION: This will perform an in-place upgrade (-u) of Sector 0 MBR"
echo "and Partition 2 (VTOYEFI). Data on sdb1, sdb3, and sdb4 will NOT be wiped."
echo "----------------------------------------------------------------------"

# 1. Unmount all partitions on /dev/sdb
echo "Step 1: Unmounting all /dev/sdb partitions..."
for p in "${DEV}"*; do
    if [ "$p" != "$DEV" ]; then
        umount "$p" 2>/dev/null || true
    fi
done

# 2. Download/Prepare Ventoy Linux installer
VENTOY_DIR="/tmp/ventoy_installer"
mkdir -p "$VENTOY_DIR"
cd "$VENTOY_DIR"

if [ ! -f "ventoy-1.0.99/Ventoy2Disk.sh" ]; then
    echo "Step 2: Fetching Ventoy Linux upgrade package..."
    wget -q --show-progress "$VENTOY_URL" -O "$VENTOY_TAR"
    tar -xzf "$VENTOY_TAR"
fi

cd ventoy-1.0.99

# 3. Execute non-destructive update
echo "Step 3: Running non-destructive in-place upgrade (-u)..."
sh Ventoy2Disk.sh -u "$DEV"

# 4. Mount sdb1 and deploy configurations
echo "Step 4: Remounting sdb1 and deploying Ventoy 2 configs..."
MOUNT_SDB1="/mnt/ventoy2_sdb1"
mkdir -p "$MOUNT_SDB1"
mount "${DEV}1" "$MOUNT_SDB1"

mkdir -p "${MOUNT_SDB1}/ventoy"
cp -v "${SCRIPT_DIR}/ventoy_grub.cfg" "${MOUNT_SDB1}/ventoy/ventoy_grub.cfg"
cp -v "${SCRIPT_DIR}/ventoy_grub.cfg" "${MOUNT_SDB1}/ventoy_grub.cfg"
cp -v "${SCRIPT_DIR}/ventoy.json" "${MOUNT_SDB1}/ventoy/ventoy.json"

sync
umount "$MOUNT_SDB1"
rmdir "$MOUNT_SDB1"

echo "======================================================================"
echo "          VENTOY 2 CORE UPGRADE COMPLETED SUCCESSFULLY"
echo "======================================================================"
