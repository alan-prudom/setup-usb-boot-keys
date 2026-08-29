#!/usr/bin/env bash
# ==============================================================================
# boot_to_windows.sh - Force One-Time UEFI Boot to Windows 11 from Linux
# ==============================================================================
# Uses efibootmgr to dynamically find 'Windows Boot Manager' and set BootNext.
# ==============================================================================

set -euo pipefail

# Check for root / sudo
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root or with sudo to modify UEFI NVRAM."
   echo "Usage: sudo ./boot_to_windows.sh"
   exit 1
fi

# Check for efibootmgr
if ! command -v efibootmgr &> /dev/null; then
    echo "[WARN] 'efibootmgr' is not installed. Installing via package manager..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y efibootmgr
    elif command -v dnf &> /dev/null; then
        dnf install -y efibootmgr
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm efibootmgr
    else
        echo "[ERROR] Could not install efibootmgr automatically. Please install it manually."
        exit 1
    fi
fi

echo "=========================================================="
echo "       Force One-Time UEFI Boot to Windows 11             "
echo "=========================================================="
echo ""

# Query UEFI Boot Entries
echo "Querying UEFI Boot Entries..."
EFIOUT=$(efibootmgr)
echo "$EFIOUT"
echo ""

# Find Windows Boot Manager Entry Number (e.g. Boot0000 -> 0000)
WIN_BOOT_NUM=$(echo "$EFIOUT" | grep -i "Windows Boot Manager" | head -n 1 | sed -E 's/^Boot([0-9A-Fa-f]+)\*?.*/\1/')

if [[ -z "$WIN_BOOT_NUM" ]]; then
    echo "[WARN] 'Windows Boot Manager' not automatically identified in efibootmgr."
    read -rp "Please enter the 4-digit Windows Boot number manually (e.g. 0000): " WIN_BOOT_NUM
fi

echo "Setting UEFI BootNext to Windows ($WIN_BOOT_NUM)..."
efibootmgr --bootnext "$WIN_BOOT_NUM"

echo ""
echo "[OK] UEFI BootNext successfully set to Windows ($WIN_BOOT_NUM)!"
echo "The system will boot directly into Windows 11 on the NEXT reboot only."
echo ""

read -rp "Reboot into Windows 11 now? (y/N): " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Rebooting system..."
    reboot
else
    echo "Reboot postponed. BootNext will activate whenever the machine next restarts."
fi
