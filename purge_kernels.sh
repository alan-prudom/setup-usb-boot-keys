#!/bin/bash

# 1. Get the currently running kernel version
CURRENT_KERNEL=$(uname -r | sed 's/-generic//')

# 2. List all installed kernels except the current one and the "latest" 
# (This ensures you always have a fallback)
KERNELS_TO_REMOVE=$(dpkg --list | grep -E 'linux-image-[0-9]' | awk '{print $2}' | grep -v "$CURRENT_KERNEL")

if [ -z "$KERNELS_TO_REMOVE" ]; then
    echo "No old kernels found to remove."
    exit 0
fi

echo "Current kernel is: $CURRENT_KERNEL"
echo "The following old kernels will be purged to free space in /usr/lib/modules:"
echo "$KERNELS_TO_REMOVE"
echo "------------------------------------------------------"

# 3. Perform the purge
# Using 'purge' instead of 'remove' to clear out the /usr/lib/modules folders
sudo apt-get purge -y $KERNELS_TO_REMOVE

# 4. Update the bootloader to reflect changes
sudo update-grub

echo "------------------------------------------------------"
echo "Cleanup complete. Checking disk space..."
df -h /
