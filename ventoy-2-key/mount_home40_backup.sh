#!/usr/bin/env bash
# ==============================================================================
# One-Click Network Backup Mount Script for Rescuezilla / Live USB Environment
# Connects to 192.168.1.34 (zbook) home40/Clonezilla share via SSHFS key auth
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="${SCRIPT_DIR}/id_rsa"
REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"

echo "=== Rescuezilla Live Network Mount Assistant ==="

if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: SSH Key not found at $KEY_FILE"
    exit 1
fi

if [ -w "$KEY_FILE" ]; then
    chmod 600 "$KEY_FILE" 2>/dev/null || true
elif [ "$EUID" -ne 0 ]; then
    sudo chmod 600 "$KEY_FILE" 2>/dev/null || true
fi
mkdir -p "$MOUNT_POINT" 2>/dev/null || sudo mkdir -p "$MOUNT_POINT"

echo "Mounting $REMOTE_SERVER:$REMOTE_PATH to $MOUNT_POINT..."

sshfs -o identityfile="$KEY_FILE",allow_other,StrictHostKeyChecking=no,reconnect \
    "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT"

if [ $? -eq 0 ]; then
    echo "SUCCESS: Mounted to $MOUNT_POINT!"
    echo "In Rescuezilla, choose 'Local Directory' and select $MOUNT_POINT"
else
    echo "FAILED: SSHFS mount error."
fi
