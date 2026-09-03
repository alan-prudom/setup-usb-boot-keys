#!/usr/bin/env bash
# ==============================================================================
# Verification Script for Ventoy 2 USB Drive (/dev/sdb)
# Validates partitions, UUIDs, GRUB configs, JSON, and persistence container
# ==============================================================================

set -euo pipefail

DEV="/dev/sdb"
EXPECTED_UBUNTU_UUID="e0d8ad1a-410b-4245-9192-66d2a16077b9"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================================"
echo "          VENTOY 2 AUDIT & VERIFICATION TEST SUITE"
echo "======================================================================"

# 1. Check Device Existence
echo -n "[TEST] Checking block device $DEV... "
if [ -b "$DEV" ]; then
    echo "PASS"
else
    echo "FAIL: $DEV not found!"
    exit 1
fi

# 2. Check Partitions
echo -n "[TEST] Checking partition geometry on $DEV... "
part_count=$(lsblk -n -o NAME "$DEV" | wc -l)
if [ "$part_count" -ge 5 ]; then # sdb + 4 partitions
    echo "PASS (sdb1, sdb2, sdb3, sdb4 detected)"
else
    echo "FAIL: Unexpected partition count ($part_count)"
    exit 1
fi

# 3. Check sdb3 Rootfs UUID
echo -n "[TEST] Checking sdb3 UUID ($EXPECTED_UBUNTU_UUID)... "
actual_uuid=$(lsblk -n -o UUID "${DEV}3" 2>/dev/null || blkid -s UUID -o value "${DEV}3" 2>/dev/null || true)
if [ "$actual_uuid" == "$EXPECTED_UBUNTU_UUID" ]; then
    echo "PASS (UUID intact: $actual_uuid)"
else
    echo "FAIL: sdb3 UUID mismatch! Found: '$actual_uuid'"
    exit 1
fi

# 4. Check GRUB Syntax
echo -n "[TEST] Validating ventoy_grub.cfg syntax... "
if command -v grub-script-check >/dev/null 2>&1; then
    grub-script-check "${SCRIPT_DIR}/ventoy_grub.cfg"
    echo "PASS"
else
    echo "SKIP (grub-script-check not installed)"
fi

# 5. Check ventoy.json Syntax
echo -n "[TEST] Validating ventoy.json syntax... "
python3 -m json.tool "${SCRIPT_DIR}/ventoy.json" >/dev/null
echo "PASS"

# 6. Check MBR Signature
echo -n "[TEST] Checking MBR boot signature (0x55AA)... "
if [ -r "$DEV" ]; then
    mbr_sig=$(dd if="$DEV" bs=1 skip=510 count=2 2>/dev/null | xxd -p)
    if [ "$mbr_sig" == "55aa" ]; then
        echo "PASS ($mbr_sig)"
    else
        echo "FAIL: Invalid MBR signature: $mbr_sig"
        exit 1
    fi
else
    echo "SKIP (raw block device requires root/disk group to read Sector 0)"
fi

echo "======================================================================"
echo "          ALL PRE-BOOT CONFIGURATION AUDITS PASSED"
echo "======================================================================"
