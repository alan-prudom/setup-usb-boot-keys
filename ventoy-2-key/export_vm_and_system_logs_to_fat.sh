#!/usr/bin/env bash
# ==============================================================================
# export_vm_and_system_logs_to_fat.sh
# Exports all VM telemetry, serial console logs, host dmesg, and persistence logs
# to a timestamped diagnostic directory on the 82 GB SHARED FAT USB partition.
# ==============================================================================
set -e

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RED="\033[1;31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       📦 EXPORT VM & SYSTEM DIAGNOSTIC LOGS TO SHARED FAT           ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

# 1. Locate SHARED FAT mount point
FAT_MOUNT=""
for candidate in "/ntfs" "/media/alan/SHARED FAT" "/media/ubuntu/SHARED_FAT" "/media/alan/SHARED_FAT"; do
    if [ -d "$candidate" ] && [ -w "$candidate" ]; then
        FAT_MOUNT="$candidate"
        break
    fi
done

if [ -z "$FAT_MOUNT" ]; then
    # Try finding by UUID
    dev=$(blkid -U "C9D1-3C83" 2>/dev/null || lsblk -rno PATH,LABEL | grep -i "SHARED FAT" | awk '{print $1}' || echo "")
    if [ -n "$dev" ]; then
        FAT_MOUNT=$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -n1 || echo "")
    fi
fi

if [ -z "$FAT_MOUNT" ] || [ ! -d "$FAT_MOUNT" ]; then
    echo -e "${RED}Error: Could not locate mounted writable SHARED FAT partition.${RESET}"
    echo "Checked: /ntfs, /media/alan/SHARED FAT"
    exit 1
fi

DEST_DIR="${FAT_MOUNT}/vm_diagnostic_bundle_${TIMESTAMP}"
mkdir -p "$DEST_DIR"

echo -e "[*] Harvesting diagnostics into: ${BOLD}${DEST_DIR}${RESET}"

# 2. Collect QEMU & Serial Console logs
if [ -f "/tmp/vm_serial_console.log" ]; then
    cp "/tmp/vm_serial_console.log" "${DEST_DIR}/vm_serial_console.log"
    echo -e "  • Harvested VM Serial Console Log ($(wc -l < /tmp/vm_serial_console.log) lines)"
else
    echo "No /tmp/vm_serial_console.log found." > "${DEST_DIR}/vm_serial_console.log"
fi

if [ -f "/tmp/qemu_rescuezilla_vm.log" ]; then
    cp "/tmp/qemu_rescuezilla_vm.log" "${DEST_DIR}/qemu_rescuezilla_vm.log"
    echo -e "  • Harvested QEMU Runtime Log ($(wc -l < /tmp/qemu_rescuezilla_vm.log) lines)"
else
    echo "No /tmp/qemu_rescuezilla_vm.log found." > "${DEST_DIR}/qemu_rescuezilla_vm.log"
fi

# 3. Collect Host Kernel dmesg excerpts (KVM, loop devices, USB)
dmesg -T | grep -iE "kvm|qemu|loop|sdb|ext4" | tail -n 250 > "${DEST_DIR}/host_kernel_dmesg.log" 2>/dev/null || true
echo -e "  • Harvested Host Kernel Telemetry ($(wc -l < "${DEST_DIR}/host_kernel_dmesg.log") lines)"

# 4. Collect Desktop Entry Validation
echo "=== Desktop File Validation ===" > "${DEST_DIR}/desktop_file_validation.log"
for df in "${SCRIPT_DIR}/persistence_startup/"*.desktop; do
    echo "Checking $df..." >> "${DEST_DIR}/desktop_file_validation.log"
    if command -v desktop-file-validate >/dev/null 2>&1; then
        desktop-file-validate "$df" >> "${DEST_DIR}/desktop_file_validation.log" 2>&1 || echo "VALIDATION ERROR" >> "${DEST_DIR}/desktop_file_validation.log"
    fi
    grep -E "^(Exec|Name|Comment|Terminal)=" "$df" >> "${DEST_DIR}/desktop_file_validation.log" || true
    echo "---" >> "${DEST_DIR}/desktop_file_validation.log"
done
echo -e "  • Audited Desktop Files ($(wc -l < "${DEST_DIR}/desktop_file_validation.log") lines)"

# 5. Collect Persistence Storage Logs if persistence image is readable
PERSIST_IMG="/media/alan/Ventoy1/rescuezilla-persistence.dat"
if [ -f "$PERSIST_IMG" ] && [ "$EUID" -eq 0 ]; then
    tmp_m="/mnt/persist_log_harvest_$$"
    mkdir -p "$tmp_m"
    if mount -o loop,ro "$PERSIST_IMG" "$tmp_m" 2>/dev/null; then
        if [ -f "$tmp_m/upper/var/log/startup_storage.log" ]; then
            cp "$tmp_m/upper/var/log/startup_storage.log" "${DEST_DIR}/guest_startup_storage.log" 2>/dev/null || true
        fi
        if [ -f "$tmp_m/upper/var/log/syslog" ]; then
            tail -n 300 "$tmp_m/upper/var/log/syslog" > "${DEST_DIR}/guest_syslog_tail.log" 2>/dev/null || true
        fi
        ls -la "$tmp_m/upper/home/ubuntu/Desktop/" > "${DEST_DIR}/guest_desktop_ls.txt" 2>/dev/null || true
        umount "$tmp_m" 2>/dev/null || true
    fi
    rmdir "$tmp_m" 2>/dev/null || true
    echo -e "  • Harvested Guest Persistence Storage Logs"
fi

# 6. Run verify_ventoy2.sh output
if [ -x "${SCRIPT_DIR}/verify_ventoy2.sh" ]; then
    "${SCRIPT_DIR}/verify_ventoy2.sh" > "${DEST_DIR}/verify_ventoy2_audit.log" 2>&1 || true
    echo -e "  • Harvested Ventoy 2 System Audit Output"
fi

sync

echo -e "\n${GREEN}======================================================================${RESET}"
echo -e "${GREEN}✓ Diagnostic Bundle Successfully Exported!${RESET}"
echo -e "  • Location: ${BOLD}${DEST_DIR}${RESET}"
echo -e "  • Contents: $(ls "$DEST_DIR" | tr '\n' ' ')"
echo -e "${GREEN}======================================================================${RESET}"
