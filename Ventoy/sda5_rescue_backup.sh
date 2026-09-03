#!/usr/bin/env bash
# ==============================================================================
# sda5_rescue_backup.sh
# Emergency rescue backup of /dev/sda5 with bad sector bypass
# Clonezilla --rescue mode: skips unreadable sectors, saves all recoverable data
# ==============================================================================
# ℹ️ Why this script exists:
#   The full-disk backup on 2026-09-03 failed on /dev/sda5 (426 GB NTFS data
#   partition) due to physical bad sectors at LBA 0x00cd0c88. This script uses
#   Clonezilla's --rescue flag to read past bad sectors and save everything
#   that can be saved before the drive degrades further.
# ==============================================================================

set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
LOG_DIR="/scripts"
LOG_FILE="${LOG_DIR}/sda5_rescue_${TIMESTAMP}.log"
ENV_FILE="${LOG_DIR}/sda5_rescue_latest.env"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=============================================================="
echo " SDA5 RESCUE BACKUP — $(date)"
echo " Running as: $(whoami) (UID: $(id -u))"
echo "=============================================================="

# ── 1. SSH KEY ──────────────────────────────────────────────────────────────
echo -e "\n[1/6] Locating SSH identity key..."
echo "ℹ️  Why: SSHFS requires an SSH key to mount the remote backup server."
KEY_FILE=""
for candidate in "/scripts/id_rsa" "/home/ubuntu/.ssh/id_rsa" "/home/ubuntu/scripts/id_rsa"; do
    if [ -f "$candidate" ]; then KEY_FILE="$candidate"; break; fi
done
if [ -z "$KEY_FILE" ]; then
    KEY_FILE=$(find /media /mnt /home -name "id_rsa" 2>/dev/null | head -n 1)
fi
if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "✗ ERROR: SSH key not found. Cannot mount backup server."
    exit 1
fi
chmod 600 "$KEY_FILE"
echo "✓ SSH key: $KEY_FILE"

# ── 2. MOUNT BACKUP SERVER ───────────────────────────────────────────────────
echo -e "\n[2/6] Mounting backup server via SSHFS..."
echo "ℹ️  Why: The backup destination is on 192.168.1.34. SSHFS mounts it as a"
echo "   local filesystem so Clonezilla can write the image directly over LAN."
REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"

mkdir -p "$MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT"; then
    echo "Unmounting stale mount..."
    umount -l "$MOUNT_POINT" 2>/dev/null || true
    sleep 2
fi
sshfs -o identityfile="$KEY_FILE",allow_other,StrictHostKeyChecking=no,reconnect \
    "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT"
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "✗ ERROR: SSHFS mount failed. Check network and server availability."
    exit 1
fi
echo "✓ Server mounted at $MOUNT_POINT"

# ── 3. WRITE INVESTIGATION REPORT ──────────────────────────────────────────
echo -e "\n[3/6] Writing investigation report to backup folder..."
echo "ℹ️  Why: The report and this script are written into the backup image folder"
echo "   so future users understand what the backup contains and what failed."
IMAGE_BASE="HP-ZBook-FullDisk-2026-09-03-1904-img"
REPORT_DEST="${MOUNT_POINT}/${IMAGE_BASE}/sda_failure_report_2026-09-03.md"
SCRIPT_DEST="${MOUNT_POINT}/${IMAGE_BASE}/sda5_rescue_backup.sh"
for src_file in "/scripts/sda_failure_report_2026-09-03.md" "/home/ubuntu/sda_failure_report_2026-09-03.md"; do
    if [ -f "$src_file" ]; then
        cp -v "$src_file" "$REPORT_DEST" && echo "✓ Report written." && break
    fi
done
cp -v "$0" "$SCRIPT_DEST" 2>/dev/null && echo "✓ Script written." || true

# ── 4. SMART PRE-CHECK ──────────────────────────────────────────────────────
echo -e "\n[4/6] Running SMART health check on /dev/sda before rescue..."
echo "ℹ️  Why: Documents the exact drive health state at time of rescue attempt."
SMART_OUT="${LOG_DIR}/sda5_rescue_smart_pre_${TIMESTAMP}.txt"
smartctl -a /dev/sda > "$SMART_OUT" 2>&1 || true
grep -E "202|187|198|196|199|Lifetime|Uncorrect|Reallocated|Pending|CRC" "$SMART_OUT" | \
    sed 's/^/  /' || true
cp "$SMART_OUT" "${MOUNT_POINT}/${IMAGE_BASE}/" 2>/dev/null || true

# ── 5. RESCUE BACKUP OF SDA5 ────────────────────────────────────────────────
echo -e "\n[5/6] Starting rescue backup of /dev/sda5..."
echo "ℹ️  Why: --rescue tells Clonezilla/partclone to skip unreadable bad sectors"
echo "   and log them, rather than aborting. This maximises the data saved."
echo "   Without --rescue the backup fails completely on the first bad sector."
echo "   Bad sectors will be logged to /var/log/partclone.log for later analysis."
echo ""
echo "   Target partition: /dev/sda5 (426.2 GB NTFS 'data')"
echo "   Destination:      ${MOUNT_POINT}/"
echo "   Timestamp:        ${TIMESTAMP}"
echo ""

RESCUE_IMAGE="HP-ZBook-sda5-RESCUE-${TIMESTAMP}-img"

# Run Clonezilla saveparts in rescue mode
# Flags:
#   -q2        = priority to partclone then partimage
#   -j2        = clone hidden data between partitions
#   -z1p       = pigz compression (fast, parallel)
#   -i 4096    = split image into 4GB chunks
#   -sc        = skip checking if target is mounted
#   -p true    = run 'true' on completion (don't ask to reboot/shutdown)
#   --rescue   = skip unreadable sectors, log them, continue
#   saveparts  = save specific partitions (not full disk)
ocs-sr -q2 -j2 -z1p -i 4096 -sc -p true --rescue \
    saveparts "$RESCUE_IMAGE" sda5 \
    2>&1 | tee "${LOG_DIR}/sda5_rescue_ocs_${TIMESTAMP}.log"
RESCUE_EXIT=${PIPESTATUS[0]}

echo ""
echo "=============================================================="
if [ "$RESCUE_EXIT" -eq 0 ]; then
    echo "✓ Rescue backup COMPLETED. Exit code: 0"
else
    echo "⚠ Rescue backup finished with exit code: ${RESCUE_EXIT}"
    echo "  Check /var/log/partclone.log for sector skip details."
fi
echo "  Image saved to: ${MOUNT_POINT}/${RESCUE_IMAGE}/"
echo "=============================================================="

# Copy partclone log to image folder for reference
cp /var/log/partclone.log "${MOUNT_POINT}/${RESCUE_IMAGE}/partclone_rescue_${TIMESTAMP}.log" 2>/dev/null || true

# ── 6. POST-RESCUE STEPS ────────────────────────────────────────────────────
echo -e "\n[6/6] Running post-rescue diagnostics..."
echo "ℹ️  Why: Captures the state of the drive after the rescue attempt."

# 6a. Badblocks map
echo ""
echo "─── Step 6a: badblocks surface scan of /dev/sda5 ───"
echo "ℹ️  Why: Maps every unreadable sector on sda5. Read-only scan, does not write."
echo "   This will take 30-90 minutes for a 426 GB partition. Please wait..."
BADBLOCKS_LOG="${LOG_DIR}/sda5_badblocks_${TIMESTAMP}.txt"
badblocks -v -s -o "$BADBLOCKS_LOG" /dev/sda5 2>&1 | tee /tmp/bb_progress.txt
BB_COUNT=$(wc -l < "$BADBLOCKS_LOG" 2>/dev/null || echo "unknown")
echo "✓ badblocks complete. ${BB_COUNT} bad sector(s) mapped."
echo "  Log: ${BADBLOCKS_LOG}"
cp "$BADBLOCKS_LOG" "${MOUNT_POINT}/${IMAGE_BASE}/" 2>/dev/null || true

# 6b. SMART post-check
echo ""
echo "─── Step 6b: SMART post-rescue snapshot ───"
SMART_POST="${LOG_DIR}/sda5_rescue_smart_post_${TIMESTAMP}.txt"
smartctl -a /dev/sda > "$SMART_POST" 2>&1 || true
grep -E "202|187|198|196|199|Lifetime|Uncorrect|Reallocated|Pending|CRC" "$SMART_POST" | \
    sed 's/^/  /' || true
cp "$SMART_POST" "${MOUNT_POINT}/${IMAGE_BASE}/" 2>/dev/null || true

# 6c. sda2 image integrity check
echo ""
echo "─── Step 6c: Verify sda2 (Windows 204 GB) image integrity ───"
echo "ℹ️  Why: Bad sectors were detected on sda2 during the original backup."
echo "   Dry-run restore verifies the image is internally consistent."
SDA2_IMG=$(ls "${MOUNT_POINT}/${IMAGE_BASE}/sda2"*.gz.* 2>/dev/null | sort | head -n 1)
if [ -n "$SDA2_IMG" ]; then
    echo "  Verifying: $SDA2_IMG"
    partclone.ntfs --restore --dry-run -s "$SDA2_IMG" -o /dev/null 2>&1 | tail -n 5
else
    echo "  sda2 image not found at ${MOUNT_POINT}/${IMAGE_BASE}/. Skipping."
fi

# 6d. Write summary env file
cat > "$ENV_FILE" << ENV
RESCUE_TIMESTAMP="${TIMESTAMP}"
RESCUE_IMAGE="${RESCUE_IMAGE}"
RESCUE_EXIT_CODE="${RESCUE_EXIT}"
BADBLOCKS_COUNT="${BB_COUNT}"
RESCUE_LOG="${LOG_DIR}/sda5_rescue_ocs_${TIMESTAMP}.log"
BADBLOCKS_LOG="${BADBLOCKS_LOG}"
ENV

echo ""
echo "=============================================================="
echo " RESCUE OPERATION COMPLETE"
echo " Summary written to: ${ENV_FILE}"
echo " All logs preserved in: ${LOG_DIR}/"
echo "=============================================================="
echo ""
echo " ⚠ NEXT STEP: Replace /dev/sda — Crucial CT1024M550SSD1 is at"
echo "   6% endurance remaining. Recommended replacement:"
echo "   Samsung 870 EVO 1TB or Crucial MX500 1TB (2.5\" SATA)"
echo ""
read -n 1 -s -r -p " Press any key to close this terminal..."
