#!/usr/bin/env bash
# sync_and_launch.sh - Self-healing script synchronizer and launcher for Rescuezilla Live
# Ensures fresh scripts from Partition 4 / USB are synced into /scripts before execution.

set -e

USB_TARGET=""
for cand in /media/ubuntu/2C95D29B2DF0500E /media/ubuntu/ntfs_usb /home/ubuntu/ntfs_usb /media/devmon/Ventoy /media/devmon/sdb4*; do
    if [ -d "$cand" ] && [ -f "${cand}/run_rescuezilla_backup_cli.sh" ]; then
        USB_TARGET="$cand"
        break
    fi
done

mkdir -p /scripts
if [ -n "$USB_TARGET" ]; then
    echo "[*] Syncing fresh authoritative scripts from ${USB_TARGET} to /scripts..."
    cp -u "${USB_TARGET}"/*.sh /scripts/ 2>/dev/null || cp "${USB_TARGET}"/*.sh /scripts/ 2>/dev/null || true
    chmod +x /scripts/*.sh 2>/dev/null || true
fi

TARGET_TO_RUN="${1:-/scripts/live_rescue_hub.sh}"
shift || true

if [ -f "$TARGET_TO_RUN" ]; then
    exec bash "$TARGET_TO_RUN" "$@"
elif [ -f "/scripts/$(basename "$TARGET_TO_RUN")" ]; then
    exec bash "/scripts/$(basename "$TARGET_TO_RUN")" "$@"
else
    echo "Error: Target $TARGET_TO_RUN not found."
    read -rp "Press Enter..." _
fi
