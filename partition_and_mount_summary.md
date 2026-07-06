# Partition and Mount Setup Summary

This document summarizes the current disk partitions and their mount points as observed from the `df -h` output.

## Overview of Mounted Filesystems

| Filesystem                             | Type       | Size  | Used  | Avail | Use% | Mounted on                       | Description                                                     |
| :------------------------------------- | :--------- | :---- | :---- | :---- | :--- | :------------------------------- | :-------------------------------------------------------------- |
| `tmpfs`                                | `tmpfs`    | 1.6G  | 4.8M  | 1.6G  | 1%   | `/run`                           | Temporary filesystem for runtime data.                            |
| `/dev/sda3`                            | `ext4`     | 19G   | 13G   | 6.0G  | 68%  | `/`                              | Main Linux root partition.                                      |
| `tmpfs`                                | `tmpfs`    | 7.8G  | 0     | 7.8G  | 0%   | `/dev/shm`                       | Temporary filesystem for shared memory.                         |
| `tmpfs`                                | `tmpfs`    | 5.0M  | 4.0K  | 5.0M  | 1%   | `/run/lock`                      | Temporary filesystem for lock files.                            |
| `tmpfs`                                | `tmpfs`    | 1.6G  | 124K  | 1.6G  | 1%   | `/run/user/1000`                 | User-specific temporary filesystem.                             |
| `/dev/sda1`                            | `exfat`    | 20G   | 18G   | 1.4G  | 94%  | `/media/alan/Ventoy1`            | External USB drive, likely a Ventoy bootable drive.             |
| `/dev/nvme0n1p3`                       | `fuseblk`  | 217G  | 216G  | 910M  | 100% | `/mnt/win_os`                    | Windows OS partition (NTFS). Almost full.                       |
| `alan@192.168.1.34:/media/alan/home40` | `fuse.sshfs`| 450G  | 405G  | 23G   | 95%  | `/home/alan/mnt/zbook`           | Remote SSHFS mount to a Zbook machine. High usage.              |
| `/dev/nvme0n1p4`                       | `fuseblk`  | 260G  | 248G  | 12G   | 96%  | `/mnt/win_data`                  | Windows data partition (NTFS). Very high usage.                 |
| `tmpfs`                                | `tmpfs`    | 1.6G  | 92K   | 1.6G  | 1%   | `/run/user/125`                  | User-specific temporary filesystem.                             |
| `/dev/loop0`                           | `ext4`     | 20G   | 2.5G  | 17G   | 14%  | `/mnt/win_data/docker-data`      | **Docker/containerd virtual disk (ext4)**, stored as a file on `/mnt/win_data`. |

## Key Observations

*   **Root Filesystem (`/`)**: `/dev/sda3` is your primary Linux filesystem with 6.0GB available.
*   **Windows Partitions**:
    *   `/mnt/win_os` (`/dev/nvme0n1p3`) is almost entirely full (910MB available).
    *   `/mnt/win_data` (`/dev/nvme0n1p4`) is also highly utilized (12GB available). These are NTFS partitions mounted via `fuseblk`.
*   **SSHFS Mount**: `/home/alan/mnt/zbook` is a remote filesystem with 23GB available, indicating high usage.
*   **Ventoy USB**: `/media/alan/Ventoy1` is a 20GB exFAT partition, 94% full.
*   **Docker Virtual Disk**: `/dev/loop0` is a 20GB `ext4` virtual disk mounted on `/mnt/win_data/docker-data`. This was created to provide a compatible filesystem for Docker's `overlayfs` storage driver, overcoming the limitations of the underlying NTFS `/mnt/win_data` partition. It currently has 17GB available for Docker and `containerd` data.

This setup indicates a system that has been carefully configured to manage disk space, particularly by offloading some system components (like Docker and `containerd`) onto a virtual `ext4` disk on a Windows partition, and leveraging network mounts.
