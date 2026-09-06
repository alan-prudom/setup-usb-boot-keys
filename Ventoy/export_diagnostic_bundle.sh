#!/usr/bin/env bash
# ==============================================================================
# export_diagnostic_bundle.sh
# Universal diagnostic bundler for Rescuezilla & Ventoy Live USB environments
# Dynamically resolves Partition 4 (NTFS or FAT32) via lib_hardware_detect.sh
# ==============================================================================
set -e

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/lib/lib_hardware_detect.sh" ]; then
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/lib/lib_hardware_detect.sh"
elif [ -f "/scripts/lib/lib_hardware_detect.sh" ]; then
    # shellcheck source=/dev/null
    source "/scripts/lib/lib_hardware_detect.sh"
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       📦 EXPORT SYSTEM & VM DIAGNOSTIC BUNDLE TO USB STORAGE         ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

# 1. Locate and ensure writable USB data partition (NTFS or FAT32)
DATA_MOUNT=""
for cand in "/home/ubuntu/ntfs_usb" "/home/ubuntu/shared_fat" "/media/ubuntu/"* "/media/alan/"* "/mnt/usb_data"; do
    if [ -d "$cand" ] && [ -w "$cand" ] && [[ "$cand" != *"/Ventoy" ]] && [[ "$cand" != *"/VTOYEFI" ]]; then
        DATA_MOUNT="$cand"
        break
    fi
done

if [ -z "$DATA_MOUNT" ] && command -v mount_data_partition >/dev/null 2>&1; then
    DATA_MOUNT="/mnt/usb_data"
    mkdir -p "$DATA_MOUNT"
    mount_data_partition "$DATA_MOUNT" 2>/dev/null || true
fi

if [ -z "$DATA_MOUNT" ] || [ ! -d "$DATA_MOUNT" ] || [ ! -w "$DATA_MOUNT" ]; then
    echo -e "${YELLOW}Warning: Direct USB partition not mounted writable. Defaulting to /tmp...${RESET}"
    DATA_MOUNT="/tmp"
fi

BUNDLE_DIR="${DATA_MOUNT}/diagnostic_bundle_${TIMESTAMP}"
mkdir -p "$BUNDLE_DIR"

echo -e "[*] Harvesting diagnostics into: ${BOLD}${BUNDLE_DIR}${RESET}"

# 2. Collect Backup & Session Logs
echo -e "  • Collecting backup and operation logs..."
for log in /scripts/backup_*.log /var/log/clonezilla.log /var/log/partclone.log /tmp/rescuezilla.log /tmp/vm_serial_console.log /tmp/qemu_rescuezilla_vm.log; do
    if [ -f "$log" ]; then
        cp "$log" "${BUNDLE_DIR}/" 2>/dev/null || true
    fi
done

# Copy latest_backup.env if present
if [ -f "/scripts/latest_backup.env" ]; then
    cp "/scripts/latest_backup.env" "${BUNDLE_DIR}/" 2>/dev/null || true
fi

# 3. Collect System Telemetry
echo -e "  • Harvesting kernel dmesg and system journal..."
dmesg -T > "${BUNDLE_DIR}/kernel_dmesg.log" 2>/dev/null || true
journalctl -b -n 2000 > "${BUNDLE_DIR}/system_journal.log" 2>/dev/null || true

# 4. Collect Storage & Hardware Tables
echo -e "  • Dumping block devices and partition tables..."
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL > "${BUNDLE_DIR}/block_devices.txt" 2>/dev/null || true
fdisk -l > "${BUNDLE_DIR}/partition_tables.txt" 2>/dev/null || true
df -hT > "${BUNDLE_DIR}/filesystem_usage.txt" 2>/dev/null || true

# 5. Collect SMART Drive Telemetry
echo -e "  • Querying SMART drive controller telemetry..."
for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
    if [ -b "$disk" ]; then
        dname=$(basename "$disk")
        smartctl -a "$disk" > "${BUNDLE_DIR}/smart_${dname}.log" 2>/dev/null || true
    fi
done

sync
echo -e "${GREEN}======================================================================${RESET}"
echo -e "${GREEN}✓ Diagnostic bundle successfully created at:${RESET}"
echo -e "  ${BOLD}${BUNDLE_DIR}${RESET}"
echo -e "${GREEN}======================================================================${RESET}"
