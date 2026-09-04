#!/usr/bin/env bash
set -e

# Ensure script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script with sudo: sudo $0"
    exit 1
fi

IMG="/media/alan/Ventoy1/rescuezilla-persistence.dat"
MNT="/mnt/rescue_persist"

if [ ! -f "$IMG" ]; then
    echo "Error: Persistence file not found at $IMG"
    echo "Check if the Ventoy partition is mounted at /media/alan/Ventoy1"
    exit 1
fi

echo "Creating temporary mountpoint at $MNT..."
mkdir -p "$MNT"

echo "Mounting $IMG..."
mount -o loop "$IMG" "$MNT"

echo "Configuring persistence inside $MNT..."

# 1. Create the automount script inside the persistence filesystem
mkdir -p "$MNT/usr/local/bin"
cat << 'INNER_EOF' > "$MNT/usr/local/bin/rescuezilla_automount.sh"
#!/usr/bin/env bash
mkdir -p /media/ubuntu/SHARED_FAT /media/ubuntu/Internal_HDD

# Mount the 82GB USB FAT partition
mount -L "SHARED FAT" /media/ubuntu/SHARED_FAT -o umask=000,rw 2>/dev/null || true

# Mount internal HDD linux partition if present (read-only for safety)
mount -o ro /dev/sda5 /media/ubuntu/Internal_HDD 2>/dev/null || true

# Place links on the Live Desktop
mkdir -p /home/ubuntu/Desktop
ln -sf /media/ubuntu/SHARED_FAT/scripts /home/ubuntu/Desktop/Scripts_FAT
ln -sf /media/ubuntu/Internal_HDD /home/ubuntu/Desktop/Internal_HDD
chown -R ubuntu:ubuntu /home/ubuntu/Desktop 2>/dev/null || true
INNER_EOF
chmod +x "$MNT/usr/local/bin/rescuezilla_automount.sh"

# 2. Add XDG Autostart so GUI triggers it on desktop login
mkdir -p "$MNT/etc/xdg/autostart"
cat << 'INNER_EOF' > "$MNT/etc/xdg/autostart/automount-fat.desktop"
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/rescuezilla_automount.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=AutoMount Shared FAT and Scripts
INNER_EOF

# 3. Pre-create user desktop and copy scripts directly into /home/ubuntu
mkdir -p "$MNT/home/ubuntu/Desktop"
mkdir -p "$MNT/home/ubuntu/scripts"
if [ -d "/ntfs/scripts" ]; then
    cp -r /ntfs/scripts/* "$MNT/home/ubuntu/scripts/" 2>/dev/null || true
    cp -r /ntfs/scripts/* "$MNT/home/ubuntu/Desktop/" 2>/dev/null || true
fi

echo "Flushing disk caches and unmounting..."
sync
umount "$MNT"
rmdir "$MNT"

echo "=========================================================="
echo "Done! Rescuezilla persistence was successfully configured."
echo "When you boot Rescuezilla from Ventoy, the 82GB FAT partition"
echo "and your scripts will automatically appear on the Desktop."
echo "=========================================================="
