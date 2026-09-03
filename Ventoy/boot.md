# Boot

## HP EliteBook Boot Configuration Summary

* **Customized Boot:** Enabled
* **SecureBoot:** Disabled
* **Key Mode:** HP Factory Keys
* **Boot Mode:** Legacy
* **UEFI Mode:** Disabled (both UEFI Hybrid with CSM and UEFI Native are inactive)
* **UEFI Boot Order:** Inactive / greyed out due to Legacy mode selection

### Key Technical Implications

* **Partition Table Compatibility:** Boots exclusively using traditional MBR (Master Boot Record) partition schemes. GPT-only UEFI drives will not boot under this setting.
* **External Media / Ventoy:** Boots loaders via the legacy BIOS/CSM path (useful for legacy MBR tools, older Linux live environments, and syslinux/GRUB legacy loaders).
* **OS Support:** Disables Secure Boot signature checks entirely, allowing unsigned operating systems, custom kernels, and legacy hypervisors to initialize without key enrollment.

---

## Ventoy Boot & GRUB Troubleshooting

The GRUB errors (can't find command 'vt_clean_key', vt_list_img, theme.txt not found) followed by "No ISO or supported IMG files found" indicate that GRUB loaded, but it cannot access or read the first partition (Part 1) where your files and Ventoy core scripts reside.
1. Update Ventoy in Place (Fixes Corrupted Bootloader/EFI)
 * Plug the USB into a working machine.
 * Open the Ventoy installer (Ventoy2Disk GUI or ./Ventoy2Disk.sh -u /dev/sdX).
 * Click Update (or use the -u flag).
 * This rewires GRUB, modules, and the EFI system partition to matching versions without deleting or formatting your data partition.
2. Filesystem Corruption (Dirty Bit / Unclean Unmount)
 * If the primary partition (exFAT or NTFS) was unmounted uncleanly, Linux/GRUB often fails to mount it in read-only mode during boot:
   * On Windows: Open Command Prompt as Administrator and run:
     chkdsk X: /f

     (Replace X: with the letter of the main Ventoy data drive).
   * On Linux: If formatted as NTFS:
     sudo ntfsfix /dev/sdX1

     If formatted as exFAT:
     sudo fsck.exfat -a /dev/sdX1
