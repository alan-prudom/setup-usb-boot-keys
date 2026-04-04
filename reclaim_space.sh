#!/bin/bash

# 1. Stop services
echo "Stopping Snap services..."
sudo systemctl stop snapd.socket snapd 2>/dev/null

# 2. Force Unmount Loop Devices
echo "Detaching snap loop devices..."
# This detaches the virtual drives that Snaps use
sudo umount -l /var/lib/snapd/snaps/* 2>/dev/null
sudo umount -l /snap/* 2>/dev/null
sudo losetup -D 2>/dev/null

# 3. The "Ghost Hunt" (Killing processes holding deleted files)
echo "Searching for processes locking deleted snap files..."
# This finds PIDs of processes still using /var/lib/snapd
PIDS=$(sudo lsof /var/lib/snapd | grep 'deleted' | awk '{print $2}' | sort -u)

if [ -n "$PIDS" ]; then
    echo "Killing processes: $PIDS"
    sudo kill -9 $PIDS
else
    echo "No locking processes found."
fi

# 4. Final Folder Cleanup
echo "Emptying the local /var/lib/snapd directory..."
sudo rm -rf /var/lib/snapd/*

# 5. Bind Mount to the Large Partition
echo "Binding /var/lib/snapd to /mnt/win_data/snapd_storage..."
# Ensure the destination exists
sudo mkdir -p /mnt/win_data/snapd_storage
sudo mount --bind /mnt/win_data/snapd_storage /var/lib/snapd

# 6. Restart Service
echo "Restarting Snapd..."
sudo systemctl start snapd

echo "------------------------------------------------------"
echo "Check /dev/sda3 usage now:"
df -h /
