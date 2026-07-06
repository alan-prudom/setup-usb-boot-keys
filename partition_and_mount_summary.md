# Partition and Mount Setup Summary

This document summarizes the current disk partitions and their mount points as observed from the `df -h` output.

## Overview of Mounted Filesystems

| Filesystem                             | Type       | Size  | Used  | Avail | Use% | Mounted on                       | Description                                                     |
| :------------------------------------- | :--------- | :---- | :---- | :---- | :--- | :------------------------------- | :-------------------------------------------------------------- |
| `tmpfs`                                | `tmpfs`    | 1.6G  | 5.0M  | 1.6G  | 1%   | `/run`                           | Temporary filesystem for runtime data.                            |
| `/dev/sda3`                            | `ext4`     | 19G   | 14G   | 5.3G  | 72%  | `/`                              | Main Linux root partition.                                      |
| `tmpfs`                                | `tmpfs`    | 7.8G  | 0     | 7.8G  | 0%   | `/dev/shm`                       | Temporary filesystem for shared memory.                         |
| `tmpfs`                                | `tmpfs`    | 5.0M  | 4.0K  | 5.0M  | 1%   | `/run/lock`                      | Temporary filesystem for lock files.                            |
| `tmpfs`                                | `tmpfs`    | 1.6G  | 156K  | 1.6G  | 1%   | `/run/user/1000`                 | User-specific temporary filesystem.                             |
| `/dev/sda1`                            | `exfat`    | 20G   | 18G   | 1.4G  | 94%  | `/media/alan/Ventoy1`            | External USB drive, likely a Ventoy bootable drive.             |
| `/dev/nvme0n1p3`                       | `fuseblk`  | 217G  | 216G  | 910M  | 100% | `/mnt/win_os`                    | Windows OS partition (NTFS). Almost full.                       |
| `alan@192.168.1.34:/media/alan/home40` | `fuse.sshfs`| 13T   | 11T   | 2.2T  | 83%  | `/home/alan/mnt/zbook`           | Remote SSHFS mount to `ap-elite` server. Large volume.          |
| `/dev/nvme0n1p4`                       | `fuseblk`  | 260G  | 248G  | 12G   | 96%  | `/mnt/win_data`                  | Windows data partition (NTFS). Very high usage.                 |
| `/dev/loop0`                           | `ext4`     | 20G   | 271M  | 19G   | 2%   | `/mnt/win_data/docker-data`      | **Docker/containerd virtual disk (ext4)** loopback mount.       |

## Key Observations

*   **Root Filesystem (`/`)**: `/dev/sda3` is your primary Linux filesystem with 5.3GB available (72% used).
*   **Windows Partitions**:
    *   `/mnt/win_os` (`/dev/nvme0n1p3`) is almost entirely full (910MB available).
    *   `/mnt/win_data` (`/dev/nvme0n1p4`) is also highly utilized (12GB available). These are NTFS partitions mounted via `fuseblk`.
*   **SSHFS Mount**: `/home/alan/mnt/zbook` is a remote filesystem with 2.2TB available, reflecting its actual 13TB capacity.
*   **Ventoy USB**: `/media/alan/Ventoy1` is a 20GB exFAT partition, 94% full.
*   **Docker Virtual Disk**: `/dev/loop0` is a 20GB `ext4` virtual disk mounted on `/mnt/win_data/docker-data`. This provides a compatible filesystem for Docker's `overlayfs` storage driver, overcoming the limitations of the underlying NTFS `/mnt/win_data` partition. It currently has 19GB available.

This setup indicates a system that has been carefully configured to manage disk space, particularly by offloading some system components (like Docker and `containerd`) onto a virtual `ext4` disk on a Windows partition, and leveraging network mounts.

---

## Remote Mount Directory Structure & Sharing Strategy

The remote SSHFS mount `/home/alan/mnt/zbook` (pointing to `192.168.1.34:/media/alan/home40`) is shared between multiple local USB-booted systems, but they map their primary GitHub workspaces to separate directories on the remote storage to isolate project work.

### Folder Structure Layout
- **`files_g5/`**: Used by the `alan-USB-g5` system.
  - `/home/alan/GitHub` points via symlink to `/home/alan/mnt/zbook/files_g5/GitHub`.
  - Workspace repository `setup-usb-boot-keys` is located here.
- **`files_zbook/`**: Used by the `alan-USB-zbook` system.
  - `/home/alan/GitHub` points via symlink to `/home/alan/mnt/apelite/files_zbook/GitHub`.

### Workspace Sizes & Locations
- **`files_g5/GitHub/setup-usb-boot-keys`**: ~16MB (Current Workspace Repository)
- **`files_zbook/GitHub`**: ~12MB (Contains `my-souls-companion` and `Shell-script-playgound`)

