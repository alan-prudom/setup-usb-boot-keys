# Recent Work & Findings Summary: SSHFS & Remote Storage Alignment

This document summarizes the recent troubleshooting, findings, and configuration changes implemented to resolve permission issues and stabilize the remote SSHFS mount from `alan-USB-g5` (local laptop) to `ap-elite` (remote server).

---

## 🔍 Investigation & Findings

### 1. Stale SSHFS Mounts
- **Observation**: Accessing the repository at `/home/alan/GitHub/setup-usb-boot-keys` returned **Input/Output errors**.
- **Root Cause**: The remote server `ap-elite` experienced an unexpected shutdown. The sudden loss of connection left the local SSHFS mount at `/home/alan/mnt/zbook` in a stale (hung) state.

### 2. Headless Server Re-boot & Devmon Ownership Shadowing
- **Observation**: Even after resetting the connection, attempts to write to the repository returned **`Permission denied`**.
- **Root Cause**: When `ap-elite` rebooted headless, the system daemon `devmon` automounted the 13TB partition (`/dev/sdc2`) under `/media/alan/home40` with ownership assigned to **`devmon` (UID 300)**. Since the local user was accessing files via SSH as `alan` (UID 1000), the remote OS blocked all write attempts.
- **Dynamic Device Renaming**: Following the server reboot, the kernel dynamically re-assigned the 13TB drive from `/dev/sdc2` to `/dev/sdb2`, demonstrating the risk of using raw device paths.

### 3. Local FSTAB Lack of Local Ownership Mapping
- **Observation**: Manual mounts clashed with systemd-automount, rendering the mount directory empty.
- **Root Cause**: The local `/etc/fstab` configuration was missing `uid=1000,gid=1000` mapping. This meant the mount was mapped to `devmon` locally, and any manual mounting attempt created a conflicting layer over systemd's automount (under `root`).

---

## 🛠️ Actions Taken

### 1. Local Mount Cleanup and Re-configuration
- Stopped the systemd automounter and force-unmounted the stale mount point.
- Modified the local `/etc/fstab` (Line 13) to include local user mapping (`uid=1000,gid=1000`):
  ```text
  alan@192.168.1.34:/media/alan/home40 /home/alan/mnt/zbook fuse.sshfs x-systemd.automount,_netdev,user,uid=1000,gid=1000,idmap=user,follow_symlinks,identityfile=/home/alan/.ssh/id_rsa,allow_other,reconnect 0 0
  ```
- Reloaded the systemd daemon config and restarted the automount service.

### 2. Remote Mount Optimization (`ap-elite`)
- Added a permanent entry for the 13TB external partition to `/etc/fstab` on the remote server `ap-elite` using its unique filesystem UUID (`5C2F-FBB0`):
  ```text
  UUID=5C2F-FBB0 /media/alan/home40 exfat defaults,uid=1000,gid=1000,fmask=0022,dmask=0022,nofail,x-systemd.device-timeout=5 0 0
  ```
- This forces the remote server to mount the disk as `alan:alan` (UID 1000, GID 1000) automatically on boot, preventing `devmon` from capturing ownership.

### 3. Clonezilla Backup Documentation
- Authored a comprehensive step-by-step partition backup guide at [clonezilla_backup_guide.md](file:///home/alan/GitHub/setup-usb-boot-keys/clonezilla_backup_guide.md) detailing pre-flight checks (BitLocker suspension), boot sequence (HP ZBook F9 key), remote SFTP repository configurations, and partition recovery.

---

## 📊 Validation & Current State
- The remote drive is now mounted with proper ownership and permissions on both the server and local sides.
- Write capability has been successfully verified (write/delete tests completed successfully in the workspace).
- The pipeline is now resilient to Wi-Fi drops, server restarts, and local laptop reboots.
