#!/bin/bash

# 1. Define paths
VIMAGE="/mnt/win_data/docker_storage.img"
MOUNT_POINT="/mnt/win_data/docker-data"

# 2. Check if NTFS partition is mounted
if [ ! -f "$VIMAGE" ]; then
    echo "Error: Virtual disk image $VIMAGE not found. Is /mnt/win_data mounted?"
    exit 1
fi

# 3. Check if already mounted
if mount | grep -q "$MOUNT_POINT"; then
    echo "Docker VDisk is already mounted at $MOUNT_POINT."
else
    echo "Stopping services..."
    sudo systemctl stop casaos docker docker.socket 2>/dev/null

    echo "Mounting $VIMAGE to $MOUNT_POINT..."
    sudo mkdir -p "$MOUNT_POINT"
    sudo mount -o loop "$VIMAGE" "$MOUNT_POINT"

    # 4. Ensure containerd link is correct
    if [ "$(readlink /var/lib/containerd)" != "$MOUNT_POINT/containerd" ]; then
        echo "Updating containerd symlink..."
        sudo rm -rf /var/lib/containerd
        sudo ln -sfT "$MOUNT_POINT/containerd" /var/lib/containerd
    fi

    echo "Starting services..."
    sudo systemctl start docker casaos
fi

echo "------------------------------------------------------"
echo "Current Docker Status:"
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
