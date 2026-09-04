#!/usr/bin/env bash
# Script to mount the USB FAT32 partition and internal HDD on Rescuezilla / Live USB
set -e

echo "=== Mounting USB FAT partition (/dev/sdb4 or label SHARED FAT) ==="
FAT_DEV=$(blkid -L "SHARED FAT" || blkid | grep -i 'LABEL="SHARED FAT"' | cut -d: -f1 || lsblk -lno NAME,FSTYPE | grep vfat | head -n1 | awk '{print "/dev/"$1}')
if [ -n "$FAT_DEV" ]; then
    sudo mkdir -p /media/rescue/shared_fat
    sudo mount "$FAT_DEV" /media/rescue/shared_fat -o rw,umask=000 || true
    echo "Mounted $FAT_DEV at /media/rescue/shared_fat"
else
    echo "Warning: FAT partition not found."
fi

echo "=== Mounting Internal HDD Linux partition (/dev/sda5) ==="
if [ -b /dev/sda5 ]; then
    sudo mkdir -p /media/rescue/internal_sda5
    sudo mount -o ro /dev/sda5 /media/rescue/internal_sda5 || sudo mount /dev/sda5 /media/rescue/internal_sda5 || true
    echo "Mounted /dev/sda5 at /media/rescue/internal_sda5"
fi

echo "Done. Available mounts:"
df -h | grep -E "shared_fat|internal_sda5|/dev/sd"
