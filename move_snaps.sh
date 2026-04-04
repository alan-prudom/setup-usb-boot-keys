#!/bin/bash

# 1. Define paths
SOURCE="/var/lib/snapd"
DEST="/mnt/win_data/snapd_storage"

# 2. Check if destination exists, if not create it
if [ ! -d "/mnt/win_data" ]; then
    echo "Error: /mnt/win_data not found. Is your Windows partition mounted?"
    exit 1
fi

echo "Stopping Snap services to prevent file corruption..."
sudo systemctl stop snapd.socket snapd 2>/dev/null

# 3. Check for active snap mounts (Snaps are 'loop' devices)
# We must unmount them before moving the directory
echo "Unmounting active snap loops..."
sudo umount -l /snap/* 2>/dev/null

# 4. Move the data
if [ -L "$SOURCE" ]; then
    echo "It looks like $SOURCE is already a symbolic link. Skipping move."
else
    echo "Moving 4.2GB of Snap data to $DEST... (This may take a minute)"
    sudo mv "$SOURCE" "$DEST"
    
    # 5. Create the Symbolic Link
    echo "Creating symbolic link..."
    sudo ln -s "$DEST" "$SOURCE"
fi

# 6. Restart services
echo "Restarting Snap services..."
sudo systemctl start snapd

echo "------------------------------------------------------"
echo "Migration complete! Checking new disk space on /"
df -h /
