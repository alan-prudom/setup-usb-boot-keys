# Filesystem & Boot Investigation Summary
*Date: 2026-03-08*

## 1. Mounted Filesystems Overview
The system currently has a mix of Linux native (ext4), Windows native (NTFS/VFAT), and network (SSHFS) filesystems.

### Key Partitions
| Mount Point | Device | Filesystem | Purpose |
| :--- | :--- | :--- | :--- |
| `/` | `/dev/sdb3` | `ext4` | **Active Linux System** |
| `/media/alan/ef46ba23...` | `/dev/sdc9` | `ext4` | **Alternative Linux Drive** |
| `/media/alan/data` | `/dev/sdc5` | `ntfs3` | Windows Data & Development |
| `/ntfs` | `/dev/sdb4` | `vfat` | Portable Data Storage |
| `/media/alan/Windows` | `/dev/sdc2` | `ntfs3` | Windows 10 OS |
| `/media/alan/Ventoy1` | `/dev/sdb1` | `exfat` | ISO Boot Library |
| `/home/alan/mnt/apelite` | `sshfs` | `fuse.sshfs`| Remote Race Log Archive |

---

## 2. Alternative Linux Drive Investigation
The partition at `/media/alan/ef46ba23-9c38-4173-8722-22c0a54301a5` was analyzed and found to be a healthy, complete installation.

### System Details
- **OS**: Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernels**: Found `6.8.0-79-generic` and `6.8.0-78-generic` in `/boot`.
- **User Environment**: Contains a full home directory for user `alan` with configurations for VS Code Server, Docker, NVM, and Cargo.
- **FSTAB & Boot**: `/etc/fstab` and `/boot/grub/grub.cfg` are correctly configured for its UUID.

---

## 3. How to Fix and Boot the Alternative System
The system is likely missing from the GRUB boot menu because `os-prober` is disabled by default in modern Ubuntu.

### Steps to Restore Boot Entry:
1. **Enable os-prober** on the currently running system:
   Edit `/etc/default/grub` and ensure the following line exists:
   ```bash
   GRUB_DISABLE_OS_PROBER=false
   ```
2. **Update the Bootloader**:
   ```bash
   sudo update-grub
   ```
3. **Reboot**:
   Select "Ubuntu 24.04" from the GRUB menu.

---

## 4. Troubleshooting: Git & Permission Errors
Investigation into previous `chmod` and `core.filemode` errors reveals:
- **Root Cause**: Many of your Git projects (in `/ntfs/GitHub` or `/media/alan/data/Github`) are stored on **VFAT** or **NTFS** partitions.
- **Technical Limitation**: These filesystems do not support native Linux file permissions (`chmod`).
- **Recommendation**: Move active development projects to an **ext4** partition (like your main `/home` or the home directory on the Alternative Linux Drive) to ensure full Git compatibility.

---

## 5. Bootable Windows Partition Investigation
I've identified several potential Windows boot sites on your various drives.

### Primary Candidates
- **Partition `/dev/sdc1` (Label: `SYSTEM`)**:
  - Found: `bootmgr`, `Boot/BCD`, and a full BIOS-style `Boot/` directory with multi-language resources.
  - **Verdict**: This is a standalone **Legacy/BIOS** bootloader for a Windows installation.

- **Partition `/dev/sdc7` (Label: `w10`)**:
  - Found: `bootmgr` and Macrium Reflect recovery tools.
  - Contains many EFI bootloader backups in `Windows/WinSxS`.

- **Partition `/dev/sdc2` (Label: `Windows`)**:
  - Found: `Windows/Boot/EFI/bootmgfw.efi`.
  - **Verdict**: This is a UEFI-capable Windows installation.

### Why `update-grub` didn't find them:
- **Mode Mismatch**: Your current system is likely booted in **UEFI mode**. The `SYSTEM` partition uses **Legacy/BIOS** bootloading. UEFI GRUB generally refuses to chainload Legacy boot sectors.
- **Missing EFI Entry**: If you have a separate EFI System Partition (ESP), the Windows boot entry should ideally be in `EFI/Microsoft/Boot/` on that partition.

### Recommendation for Windows:
If you need to boot these Windows instances directly from GRUB:
1. Ensure your BIOS has **CSM (Compatibility Support Module)** enabled.
2. If that doesn't work, you may need to use a tool like `boot-repair` or manually recreate the EFI boot configuration for Windows if you want to use UEFI throughout.