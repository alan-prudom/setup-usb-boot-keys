# Clonezilla Backup Guide: Windows 11 Partition to Remote Storage

This guide provides step-by-step instructions to create a full, compressed backup image of your Windows 11 partition (`/dev/nvme0n1p3`) using Clonezilla, and store it on your remote storage server (`ap-elite`).

---

## 📋 Phase 1: Pre-Backup Checks

### 1. Check for BitLocker Encryption (Crucial)
If Windows 11 has BitLocker enabled, Clonezilla cannot read the filesystem structure. It will be forced to clone the partition sector-by-sector, resulting in a backup that is extremely slow and takes up the full partition size (217GB) on your remote disk without any compression.

- **How to check/suspend**:
  1. Boot into Windows 11.
  2. Open Command Prompt as Administrator and run:
     ```cmd
     manage-bde -status
     ```
  3. If protection is **On**, suspend it temporarily by running:
     ```cmd
     manage-bde -protectors -disable C:
     ```
     *(Note: This keeps the drive decrypted for the next reboot so Clonezilla can read and compress the data blocks.)*

### 2. Prepare the Ventoy Bootable USB
- Ensure you have downloaded the latest **Clonezilla Live ISO** (e.g. `clonezilla-live-*-amd64.iso`).
- Copy the ISO file directly onto the primary partition of your Ventoy USB drive (`/media/alan/Ventoy1`).

### 3. Identify Remote SSH Server Details
- **Server IP**: `192.168.1.34` (hostname: `ap-elite`)
- **Username**: `alan`
- **Destination Folder**: `/media/alan/home40/Clonezilla`
- **Source Partition**: `/dev/nvme0n1p3` (~217GB, NTFS format)

---

## 🥾 Phase 2: Booting into Clonezilla

1. Insert your Ventoy USB into the computer.
2. Reboot the system.
3. As the computer starts up, repeatedly press the BIOS Boot Menu key:
   - **HP laptops / ZBooks**: Press **`F9`**.
   - *(If on a different device, common keys are `F12`, `F11`, or `Esc`)*.
4. Select your **Ventoy USB** from the list of boot devices.
5. In the Ventoy menu, select the **Clonezilla Live ISO** file and boot.
6. Choose the default option: **`Clonezilla live (Default settings, VGA 800x600)`**.

---

## ⚙️ Phase 3: Step-by-Step Wizard Configuration

Once Clonezilla starts, navigate the menu using the **Arrow keys**, **Tab** (to switch between options/buttons), and **Enter** to confirm.

### Step 1: Language & Keyboard Settings
- **Language**: Choose your preferred language (e.g., `en_US.UTF-8 English`).
- **Keyboard layout**: Select `Keep default keyboard layout` (or select your specific layout if needed).
- **Start**: Select **`Start_Clonezilla`** (Start Clonezilla).

### Step 2: Mode Selection
- Select **`device-image`** (work with disks or partitions using images).

### Step 3: Mount Image Repository (`/home/partimag`)
To tell Clonezilla where to save the backup image:
1. Select **`ssh_server`** (Use SSH/SFTP server).
2. **Network Config**: Select **`dhcp`** (or configure a static IP if DHCP is not available on your network). Clonezilla will initialize your network card.
3. **Server IP**: Type `192.168.1.34` and press Enter.
4. **Port**: Press Enter to keep the default port `22`.
5. **SSH User**: Type `alan` and press Enter.
6. **Remote Path**: Type `/media/alan/home40/Clonezilla` and press Enter.
7. **SSH Host Key**: When asked to trust the server fingerprint, type `yes` and press Enter.
8. **Password**: Type your SSH password for the remote user `alan` on `ap-elite` and press Enter.
9. **Verify Mount**: Clonezilla will mount the remote directory to `/home/partimag` and display the disk space available. Press Enter to continue.

### Step 4: Wizard Mode
- Select **`Beginner`** (Beginner mode: Accept default options).

### Step 5: Save Action
- Select **`saveparts`** (Save local partitions as an image). 
- *(Do **NOT** select `savedisk`, as that would try to clone all partitions including your Linux system).*

### Step 6: Backup Image Naming
- Input a unique name for the backup folder (e.g., `HP-ZBook-Win11-Backup-2026-07-07`). Press Enter.

### Step 7: Select Source Partition
- Use the Spacebar to mark/select **`nvme0n1p3`** (the 217GB partition labeled `win_os` / NTFS).
- Press Enter to confirm.

### Step 8: Post-processing Configuration
- **Compression**: Select the default **`-z1p`** (Parallel gzip, fast and efficient).
- **Filesystem Check**: Select **`-sfsck`** (Skip checking/repairing source filesystem) - *NTFS partitions should be checked inside Windows beforehand if needed.*
- **Check Saved Image**: Select **`Yes, check the saved image`** to verify that the backup is readable and uncorrupted.
- **Encryption**: Select **`-senc`** (Do not encrypt the image).
- **Final Action**: Choose what to do when finished (e.g., `Choose reboot/shutdown/etc. when everything is finished`).

---

## 💾 Phase 4: Executing the Backup

1. Press Enter to start the execution pre-checks.
2. Clonezilla will show a summary of the action it is about to take. 
3. When prompted **`Are you sure you want to continue? (y/n)`**, type **`y`** and press Enter.
4. Clonezilla will lock the partition and begin reading/compressing blocks, streaming the data directly over the network to the server.
5. Once the imaging completes, the validation phase will run (if you selected checking in Step 8).
6. When completely done, select **`Poweroff`** or **`Reboot`**.
7. Unplug the USB drive and reboot back into your system.

---

## 🔄 Phase 5: How to Restore (If Windows Fails)

If you ever need to restore this backup partition back onto your machine:
1. Boot Clonezilla via Ventoy.
2. Mount the remote image repository using the exact same steps in **Phase 3, Step 3**.
3. Select **`Beginner`** mode.
4. Select **`restoreparts`** (Restore an image to local partitions).
5. Choose the image name from the list.
6. Select the destination partition **`nvme0n1p3`**.
7. Confirm twice with **`y`** to overwrite the partition and restore Windows 11.
