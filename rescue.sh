#!/bin/bash

# 1. Define the target on the 260GB partition
TARGET_DIR="/mnt/win_data/system_offload"
sudo mkdir -p "$TARGET_DIR"

# 2. Stop the space-hungry services
echo "Stopping Docker, CasaOS, and Snapd..."
sudo systemctl stop docker casaos snapd.socket snapd 2>/dev/null

# 3. Find where the snaps went from the previous move
# We search for the 'snaps' folder inside the backup we made
ACTUAL_SNAP_PATH=$(find /mnt/win_data/snapd_storage -name "snaps" -type d -print -quit)

# 4. FIX CONTAINERD (The 4.3GB Win)
if [ -d "/var/lib/containerd" ] && [ ! -L "/var/lib/containerd" ]; then
    echo "Moving 4.3GB of Containerd to $TARGET_DIR..."
    sudo mv /var/lib/containerd "$TARGET_DIR/"
    sudo ln -s "$TARGET_DIR/containerd" /var/lib/containerd
    echo "Containerd moved and linked."
fi

# 5. FIX SNAPD (The Service Error Fix)
if [ -n "$ACTUAL_SNAP_PATH" ]; then
    echo "Repairing Snapd link to: $ACTUAL_SNAP_PATH"
    sudo rm -rf /var/lib/snapd/snaps
    sudo ln -s "$ACTUAL_SNAP_PATH" /var/lib/snapd/snaps
fi

# 6. KILL GHOSTS (The "Force Space Release" Step)
echo "Killing processes holding deleted file handles..."
# This finds PIDs of processes using 'deleted' files and terminates them
sudo lsof / | grep 'deleted' | awk '{print $2}' | xargs -r sudo kill -9 2>/dev/null

# 7. Restart Services
echo "Restarting services..."
sudo systemctl start snapd
sudo systemctl start docker casaos

echo "------------------------------------------------------"
echo "RESCUE COMPLETE. Final Disk Space:"
df -h /
