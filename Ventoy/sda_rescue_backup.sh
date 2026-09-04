#!/usr/bin/env bash
# ==============================================================================
# sda_rescue_backup.sh
# Emergency Rescue Backup for Damaged Partitions (sda2 & sda5)
# Uses Clonezilla --rescue mode with strict remote mount verification
# ==============================================================================
# ℹ️ Why this script exists:
#   The Crucial 1TB SSD (/dev/sda) has physical bad sectors at LBA 0x00cd0c88
#   and only 6% write endurance remaining. Both sda2 (Windows, 204GB) and
#   sda5 (Data, 426GB) failed during standard backup due to unreadable blocks.
#   This script connects to the network backup server, strictly verifies
#   that /home/partimag is mounted to the remote share (preventing local disk
#   full errors), and rescues all readable data using Clonezilla's --rescue flag.
# ==============================================================================

set -euo pipefail

TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
LOG_DIR="/scripts"
LOG_FILE="${LOG_DIR}/sda_rescue_${TIMESTAMP}.log"
ENV_FILE="${LOG_DIR}/sda_rescue_latest.env"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "======================================================================"
echo " 🚨 EMERGENCY DRIVE RESCUE BACKUP — $(date)"
echo " Running as: $(whoami) (UID: $(id -u))"
echo " Target Drive: /dev/sda (Crucial CT1024M550SSD1 - 6% endurance remain)"
echo "======================================================================"

# ── 1. LOCATE SSH KEY ────────────────────────────────────────────────────────
echo -e "\n[1/6] Locating SSH identity key..."
echo "  ℹ️  Why: SSHFS requires authentication to mount the network storage server."
KEY_FILE=""
for candidate in "/scripts/id_rsa" "/home/ubuntu/.ssh/id_rsa" "/home/ubuntu/scripts/id_rsa"; do
    if [ -f "$candidate" ]; then KEY_FILE="$candidate"; break; fi
done
if [ -z "$KEY_FILE" ]; then
    KEY_FILE=$(find /media /mnt /home -name "id_rsa" 2>/dev/null | head -n 1)
fi
if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "  ✗ ERROR: SSH key 'id_rsa' not found. Cannot connect to backup server."
    exit 1
fi
chmod 600 "$KEY_FILE"
echo "  ✓ SSH key found: $KEY_FILE"

# ── 2. MOUNT REMOTE STORAGE & BIND TO /home/partimag ────────────────────────
echo -e "\n[2/6] Connecting to backup server and setting Clonezilla repository..."
echo "  ℹ️  Why: Clonezilla's ocs-sr hardcodes /home/partimag as its repository."
echo "     We mount the remote share via SSHFS to /mnt/backup, then bind-mount"
echo "     /mnt/backup to /home/partimag. This guarantees images write across the"
echo "     network and CANNOT fill up the local 512MB persistence filesystem."

REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"

mkdir -p "$MOUNT_POINT"
mkdir -p /home/partimag

# Unmount any stale mounts cleanly
if mountpoint -q /home/partimag; then
    echo "  Unmounting stale /home/partimag bind mount..."
    umount -l /home/partimag 2>/dev/null || true
    sleep 1
fi
if mountpoint -q "$MOUNT_POINT"; then
    echo "  Unmounting stale $MOUNT_POINT..."
    umount -l "$MOUNT_POINT" 2>/dev/null || true
    sleep 1
fi

echo "  Mounting sshfs alan@${REMOTE_SERVER}:${REMOTE_PATH} -> ${MOUNT_POINT}..."
sshfs -o identityfile="$KEY_FILE",allow_other,StrictHostKeyChecking=no,reconnect \
    "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "  ✗ CRITICAL ERROR: SSHFS mount failed! Server ${REMOTE_SERVER} unreachable."
    exit 1
fi

echo "  Binding ${MOUNT_POINT} -> /home/partimag..."
mount --bind "$MOUNT_POINT" /home/partimag

# ── PRE-FLIGHT SANITY CHECK (ZERO RISK OF LOCAL DISK FULL) ──────────────────
echo -e "\n[2b/6] Pre-Flight Storage Integrity Verification..."
if ! mountpoint -q /home/partimag; then
    echo "  ✗ CRITICAL ERROR: /home/partimag is NOT a mountpoint!"
    echo "    Aborting immediately to protect local filesystem from filling up."
    exit 1
fi

FREE_GB=$(df -BG /home/partimag | awk 'NR==2 {print $4}' | tr -d 'G')
echo "  Storage check: /home/partimag has ${FREE_GB} GB free space."
if [ "$FREE_GB" -lt 50 ]; then
    echo "  ✗ CRITICAL ERROR: /home/partimag has only ${FREE_GB} GB free."
    echo "    Expected network share (>50 GB). Aborting to prevent disk full error."
    exit 1
fi
echo "  ✓ Confirmed: /home/partimag is remote storage with ${FREE_GB} GB free."

# ── 3. CHOOSE RESCUE SCOPE ──────────────────────────────────────────────────
echo -e "\n[3/6] Select Rescue Scope:"
echo "  ℹ️  Why: You can rescue the 426GB data partition (sda5), the 204GB Windows"
echo "     partition (sda2), or both sequentially. Both failed in normal backup."
echo "     1) Rescue sda5 only (Data partition — 426 GB) [RECOMMENDED FIRST]"
echo "     2) Rescue sda2 only (Windows partition — 204 GB)"
echo "     3) Rescue both sda2 AND sda5 sequentially"
read -r -p "  Enter choice [1-3, default 1]: " scope_choice
scope_choice="${scope_choice:-1}"

case "$scope_choice" in
    1) RESCUE_PARTS="sda5" ;;
    2) RESCUE_PARTS="sda2" ;;
    3) RESCUE_PARTS="sda2 sda5" ;;
    *) RESCUE_PARTS="sda5" ;;
esac
echo "  Selected rescue target(s): ${RESCUE_PARTS}"

# ── 4. SMART HEALTH SNAPSHOT (PRE-RESCUE) ───────────────────────────────────
echo -e "\n[4/6] Capturing SMART drive health snapshot before rescue..."
echo "  ℹ️  Why: Documents sector reallocation and error counts prior to read stress."
SMART_PRE="${LOG_DIR}/sda_rescue_smart_pre_${TIMESTAMP}.txt"
smartctl -a /dev/sda > "$SMART_PRE" 2>&1 || true
grep -E "202|187|198|196|199|Lifetime|Uncorrect|Reallocated|Pending|CRC" "$SMART_PRE" | \
    sed 's/^/    /' || true
cp "$SMART_PRE" "/home/partimag/" 2>/dev/null || true

# ── 5. RUN RESCUE BACKUP VIA CLONEZILLA ─────────────────────────────────────
echo -e "\n[5/6] Executing Clonezilla saveparts in --rescue mode..."
echo "  ℹ️  Why: The --rescue flag tells partclone to skip unreadable bad sectors"
echo "     and fill them with zero blocks, allowing the imaging process to continue"
echo "     to completion rather than aborting. Bad sectors are logged to partclone.log."

RESCUE_EXIT=0
for part in $RESCUE_PARTS; do
    PART_IMAGE="HP-ZBook-${part}-RESCUE-${TIMESTAMP}-img"
    echo ""
    echo "  =================================================================="
    echo "  Starting rescue imaging: /dev/${part} -> ${PART_IMAGE}"
    echo "  Destination: /home/partimag/${PART_IMAGE}/"
    echo "  =================================================================="

    set +e
    ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -p true --rescue \
        saveparts "$PART_IMAGE" "$part" 2>&1 | tee "${LOG_DIR}/${part}_rescue_ocs_${TIMESTAMP}.log"
    PART_EXIT="${PIPESTATUS[0]}"
    set -e

    if [ "$PART_EXIT" -eq 0 ]; then
        echo "  ✓ Rescue for /dev/${part} completed successfully."
    else
        echo "  ⚠️ Clonezilla finished with exit code ${PART_EXIT} for /dev/${part}."
        echo "    Inspect /var/log/partclone.log for bad sector locations."
        RESCUE_EXIT="$PART_EXIT"
    fi

    # Copy logs to image folder on remote server
    cp -v "/var/log/partclone.log" "/home/partimag/${PART_IMAGE}/partclone_${part}_rescue.log" 2>/dev/null || true
    cp -v "${LOG_DIR}/${part}_rescue_ocs_${TIMESTAMP}.log" "/home/partimag/${PART_IMAGE}/" 2>/dev/null || true
done

# ── 6. POST-RESCUE BADBLOCKS SCAN & SMART AUDIT ─────────────────────────────
echo -e "\n[6/6] Post-Rescue Diagnostic Analysis:"
echo "  ℹ️  Why: A badblocks surface scan provides an exact count and sector map"
echo "     of every physically damaged LBA block on the drive."
echo "     Would you like to run a read-only badblocks scan on sda5 now?"
echo "     (Note: Scan takes 30-60 minutes on a 426GB partition)"
read -r -p "  Run badblocks scan on sda5? [y/N]: " run_bb
run_bb="${run_bb:-N}"

if [[ "$run_bb" =~ ^[Yy]$ ]]; then
    BB_LOG="${LOG_DIR}/sda5_badblocks_${TIMESTAMP}.txt"
    echo "  Starting read-only badblocks scan on /dev/sda5..."
    badblocks -v -s -o "$BB_LOG" /dev/sda5 2>&1 | tee /tmp/bb_live.txt
    BB_COUNT=$(wc -l < "$BB_LOG" 2>/dev/null || echo "0")
    echo "  ✓ badblocks scan complete. Detected ${BB_COUNT} bad blocks."
    cp "$BB_LOG" "/home/partimag/" 2>/dev/null || true
else
    echo "  Skipping badblocks scan. Proceeding to final health check."
fi

# Final SMART check
echo ""
echo "  Capturing post-rescue SMART snapshot..."
SMART_POST="${LOG_DIR}/sda_rescue_smart_post_${TIMESTAMP}.txt"
smartctl -a /dev/sda > "$SMART_POST" 2>&1 || true
grep -E "202|187|198|196|199|Lifetime|Uncorrect|Reallocated|Pending|CRC" "$SMART_POST" | \
    sed 's/^/    /' || true
cp "$SMART_POST" "/home/partimag/" 2>/dev/null || true

# Summary env file
cat > "$ENV_FILE" << ENV
TIMESTAMP="${TIMESTAMP}"
RESCUED_PARTS="${RESCUE_PARTS}"
FINAL_EXIT_CODE="${RESCUE_EXIT}"
REMOTE_REPOSITORY="${REMOTE_SERVER}:${REMOTE_PATH}"
LOG_FILE="${LOG_FILE}"
ENV

echo ""
echo "======================================================================"
echo " RESCUE BACKUP OPERATION FINISHED (Exit code: ${RESCUE_EXIT})"
echo " All logs and images saved on remote server: ${REMOTE_SERVER}"
echo " Local persistence filesystem verified safe (not filled)."
echo "======================================================================"
echo ""
echo " ⚠️ REMINDER: Drive /dev/sda (Crucial CT1024M550SSD1) has only 6%"
echo "   lifetime remaining and failing sectors. Replace drive promptly."
echo ""
read -n 1 -s -r -p " Press any key to close this terminal..."
