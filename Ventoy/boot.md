
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
