# Operational Recommendation: Partition /dev/sda2 (Windows 10 OS) Repair & Backup Procedure

**Document Version:** 1.0  
**Date of Record:** September 5, 2026  
**Target Host Machine:** HP EliteBook 8470p (`alan-USB-zbook`)  
**Target Storage Device:** SanDisk SSD PLUS 1000GB (`/dev/sda`, S/N `19360S477706`)  
**Affected Partition:** `/dev/sda2` (NTFS, UUID `E40ABED00ABE9F4C`, 151.9 GB)  
**Remote Backup Repository:** `192.168.1.34:/media/alan/home40/Clonezilla`  

---

## 1. Identity & Role of Partition `/dev/sda2`

Direct forensic inspection of the filesystem metadata, directory structures, and system tables confirms:

* **Role:** **Primary Windows 10 System Drive (`C:\`)**.
* **Filesystem:** NTFS (Cluster size: 4096 bytes).
* **Capacity:** 151.9 GB total (135.2 GB allocated / in use, 16.7 GB free space).
* **Core Contents:**
  - Standard Windows system hierarchy: `\Windows`, `\Program Files`, `\Program Files (x86)`, `\ProgramData`, `\Users`.
  - Windows runtime memory backing stores: `pagefile.sys` (1.0 GB), `hiberfil.sys` (6.8 GB), `swapfile.sys` (16 MB).
  - Recovery archives: Existing `found.000` through `found.009` folders created by previous automated Windows disk check passes.
* **Layout on Physical Drive `/dev/sda`:**
  1. `/dev/sda1` (579 MB) = **System Reserved** (Windows BCD Bootloader) — **Status: Successfully Backed Up** (11 MB compressed).
  2. `/dev/sda2` (151.9 GB) = **Windows 10 Operating System (`C:\`)** — **Status: Skipped / Failed due to bad sectors**.
  3. `/dev/sda3` (110.8 GB) = **Data Partition (`D:\`)** — **Status: Successfully Backed Up** (~65 GB compressed).
  4. `/dev/sda5` (extended) = **Ubuntu 20.04 LTS Linux Partition**.

---

## 2. Technical Evaluation: Windows `chkdsk` vs. Linux Utilities

### The Question:
> *Is it better to run a Windows-based `chkdsk` on `/dev/sda2` rather than Linux utilities?*

### The Verdict:
**Yes, significantly better.** Running Windows' native `chkdsk /f /r` is the technically superior approach for this specific failure condition.

### Detailed Engineering Justification:

#### 1. Hardware-Level Bad Block Reallocation via ATA Write Commands
* **The Underlying Failure:** The SanDisk SSD controller reported **47,425 uncorrectable read errors** and **888 retired bad blocks** in its S.M.A.R.T. telemetry (`Info-smart.txt`). When Partclone attempted to read the clusters on `/dev/sda2`, the drive's hardware ECC failed, causing the Linux SATA driver to throw an input/output error (`EIO`).
* **The SSD Firmware Mechanism:** Solid-State Drives cannot reallocate damaged NAND flash blocks upon *read* operations alone; the flash translation layer (FTL) requires an explicit **write** command to that logical block address (LBA) to trigger the substitution of a healthy spare block from its reserve pool.
* **How `chkdsk /r` Fixes This:** During Stage 4 and Stage 5 surface analysis, Windows `chkdsk` reads the physical sectors, recovers readable portions into a buffer, and issues rewrite commands to the target LBAs. This forces the Marvell/SanDisk FTL controller to retire the damaged NAND cells and re-map the address to factory spare blocks.

#### 2. Native NTFS Metadata & `$BadClust` Accounting
* If a physical sector cannot be recovered or reallocated, `chkdsk` records the damaged clusters directly into the master filesystem's internal **`$BadClust`** metadata stream.
* Once logged in `$BadClust`:
  - The Windows operating system will never attempt to write user or system files to those clusters again.
  - **Partclone will no longer abort:** Partclone reads `$BadClust` during pre-flight bitmap generation, identifies those clusters as pre-flagged unusable blocks, and skips them natively without throwing read errors.

#### 3. Limitations of Linux Utilities (`ntfsfix` / `fsck.ntfs`)
* Linux `ntfsfix` is only capable of resetting the NTFS journal (`$LogFile`), clearing the volume dirty flag, and scheduling a mandatory Windows check on next startup.
* `ntfsfix` **cannot** perform cluster surface analysis, **cannot** reconstruct corrupted MFT B-tree index records, and **cannot** properly populate `$BadClust`. Attempting to force writes with Linux tools on damaged NTFS metadata can cause further filesystem desynchronization.

---

## 3. Step-by-Step Operational Runbook

### Phase 1: Boot into Windows 10
1. Reboot the laptop.
2. At the Ventoy boot menu, press **`F6`** (Custom Boot Menu) and select:
   ```text
   🪟 Boot Windows (Internal Disk /dev/sda)
   ```
   *(Or allow the HP UEFI/BIOS bootloader to boot the internal drive normally).*

### Phase 2: Schedule Full 5-Stage Disk Check
1. Once Windows desktop loads, open the Start Menu, type `cmd`, right-click **Command Prompt**, and select **"Run as administrator"**.
2. Execute the combined fix and surface recovery command:
   ```cmd
   chkdsk C: /f /r
   ```
3. Windows will display the following prompt:
   ```text
   Chkdsk cannot run because the volume is in use by another
   process. Would you like to schedule this volume to be
   checked the next time the system restarts? (Y/N)
   ```
4. Type **`Y`** and press **Enter**.
5. Close the command prompt.

### Phase 3: Execute Boot-Time Repair
1. Restart the computer normally.
2. During startup, Windows will display:
   ```text
   Scanning and repairing drive (C:): ...% complete
   ```
3. **Allow the scan to complete uninterrupted:**
   - On a 1 TB SSD with ~135 GB used space, this scan typically takes **15 to 35 minutes**.
   - Stages 1–3 verify files, indexes, and security descriptors.
   - Stages 4–5 analyze all clusters, recover orphaned data fragments into `C:\found.xxx`, and remap bad blocks.
4. When finished, Windows will boot to the desktop automatically.

### Phase 4: Re-Run Rescuezilla Backup
1. Shut down Windows.
2. Insert the Ventoy 2 USB drive and power on the laptop (press `F9` for HP Boot Menu).
3. Select `rescuezilla-2.6.1-64bit.oracular.iso` -> **Boot with persistence**.
4. Open **🛡️ Unified Rescue & Backup Suite** from the desktop.
5. Select Option **`[1] 📤 Backup Image`** (or Option **`[6]`** to connect `home40`).
6. Select `/dev/sda2` as the backup target.
7. The backup will now stream cleanly across the network to `192.168.1.34:/media/alan/home40/Clonezilla` without bad sector halts.

---

## 4. Alternative Procedure: Immediate Imaging via Clonezilla `-rescue`

If you need an immediate backup of `/dev/sda2` right now and prefer not to wait for the 30-minute Windows `chkdsk` pass:

1. Boot into **Rescuezilla Live** with persistence.
2. Ensure network storage is connected to `/home/partimag` via `rescue_suite_launcher.sh`.
3. Open a terminal and run Clonezilla CLI with the explicit `-rescue` flag:
   ```bash
   sudo ocs-sr -q2 -c -j2 -z1p -i 4096 -rescue -p true saveparts HP-EliteBook-SDA2-Rescue-img sda2
   ```
4. **Behavior:** Partclone will stream all readable data from `/dev/sda2` (~135 GB). When it encounters unreadable bad blocks, it automatically zeroes them out, logs their sector numbers, and continues imaging to `home40` without aborting.
