#!/usr/bin/env bash
# sync_and_launch.sh - Self-healing script synchronizer and launcher for Rescuezilla Live
# Ensures fresh scripts from Partition 4 / USB are synced into /scripts before execution.

set -e

# Ensure storage is mounted if not already present
if [ ! -d /home/ubuntu/ntfs_usb ] && [ -x /usr/local/bin/mount_ntfs_startup.sh ]; then
    sudo /usr/local/bin/mount_ntfs_startup.sh 2>/dev/null || true
fi

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

# Check global instrumentation toggle
INSTRUMENTED=0
if [ -f "/tmp/rescue_instrumentation.mode" ]; then
    INSTRUMENTED=$(cat "/tmp/rescue_instrumentation.mode" 2>/dev/null || echo "0")
elif [ -f "$HOME/.config/rescue_instrumentation.mode" ]; then
    INSTRUMENTED=$(cat "$HOME/.config/rescue_instrumentation.mode" 2>/dev/null || echo "0")
fi

RESOLVED_SCRIPT=""
if [ -f "$TARGET_TO_RUN" ]; then
    RESOLVED_SCRIPT="$TARGET_TO_RUN"
elif [ -f "/scripts/$(basename "$TARGET_TO_RUN")" ]; then
    RESOLVED_SCRIPT="/scripts/$(basename "$TARGET_TO_RUN")"
fi

if [ -n "$RESOLVED_SCRIPT" ]; then
    if [ "$INSTRUMENTED" = "1" ] && [ -x "/scripts/run_with_coverage.sh" ]; then
        echo "[*] Launching with line & branch instrumentation..."
        exec bash "/scripts/run_with_coverage.sh" "$RESOLVED_SCRIPT" "$@"
    else
        exec bash "$RESOLVED_SCRIPT" "$@"
    fi
else
    echo "Error: Target $TARGET_TO_RUN not found."
    read -rp "Press Enter..." _
fi
