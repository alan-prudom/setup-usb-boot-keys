# Comprehensive Forensic Diagnostic Report: Physical Bare-Metal Backup Operation & Missed Partition Analysis

**Date of Record:** September 5, 2026  
**Host Target Machine:** HP EliteBook 8470p (`alan-USB-zbook`)  
**Source Drive:** Internal SanDisk SSD PLUS 1000GB (`/dev/sda`, S/N `19360S477706`)  
**Boot Environment:** Rescuezilla 2.6.1 (Ubuntu 24.10 Oracular Live) + Persistence (`/dev/sdb`)  
**Remote Backup Repository:** `192.168.1.34:/media/alan/home40/Clonezilla` (via SSHFS)  
**Created Image Directory:** `HP-EliteBook-FullDisk-2026-09-05-img` (Total written: **65 GB**)  

---

## 1. Executive Summary

During the bare-metal physical boot test on September 5, 2026, the live persistent Rescuezilla environment successfully booted, auto-mounted the network storage repository on `home40`, and executed a full disk backup of `/dev/sda`.

* **Overall Status:** **Partially Successful (2 of 3 partitions fully backed up, 65 GB image created)**.
* **Successful Partitions:**
  - **`/dev/sda1` (System Reserved, NTFS, 579 MB):** Successfully imaged via `partclone.ntfs` with `pigz` compression in **7.17 seconds** (image size: 11 MB).
  - **`/dev/sda3` (Data, NTFS, 110.8 GB / 100.7 GB used):** Successfully imaged via `partclone.ntfs` with `pigz` compression in **29 minutes 17 seconds** (image size: 17 chunks of 3.9 GB = ~65 GB).
  - **Disk Geometry & Metadata:** MBR (`sda-mbr`), partition tables (`sda-pt.sf`, `sda-pt.parted`), hidden sectors (`sda-hidden-data-after-mbr`), and extended partition table (`sda4-ebr`) were all captured cleanly.
* **The Missed Partition (`/dev/sda2`, Windows OS Partition, 141.5 GB):**
  - **Status:** **Skipped / Failed by Partclone**.
  - **Specific Cause:** During pre-flight filesystem bitmap calculation, `partclone.ntfs` encountered bad sectors / unreadable clusters on the physical SSD and terminated with a safety warning:
    > `WARNING: The disk has bad sectors. This means physical damage on the disk surface... Use the --rescue option to efficiently save as much data as possible!`
  - Because `ocs-sr` was executed in standard safe mode (without `--rescue` / `-rescue`), it safely skipped `/dev/sda2` and proceeded to complete `/dev/sda3`.

---

## 2. Evidence Log Audit & Telemetry Breakdown

### 2.1 Remote Image Directory Inventory (`home40/Clonezilla`)

A live inspection of `192.168.1.34:/media/alan/home40/Clonezilla/HP-EliteBook-FullDisk-2026-09-05-img/` reveals the following complete artifact registry:

| Artifact Name | Size | Operational Meaning |
| :--- | :--- | :--- |
| `sda1.ntfs-ptcl-img.gz.aa` | 11 MB | **Complete:** Full image of Windows System Reserved boot partition. |
| `sda3.ntfs-ptcl-img.gz.aa` ... `.aq` | 65 GB | **Complete:** 17 chunks (3.9 GB each) representing 100.7 GB of compressed user data on `/dev/sda3`. |
| `saving-error-202609051520` | 4.7 KB | **Diagnostic Trace:** Generated at `15:20 UTC` recording the exact abort on `/dev/sda2`. |
| `sda-mbr` & `sda-chs.sf` | 512 B | **Complete:** Master Boot Record and cylinder-head-sector geometry. |
| `sda-hidden-data-after-mbr` | 1.0 MB | **Complete:** Sectors 1 to 2047 containing stage 1.5 bootloader code. |
| `sda-pt.sf` & `sda-pt.parted` | 1 KB | **Complete:** SFdisk and Parted partition boundaries. |
| `sda4-ebr` | 512 B | **Complete:** Extended Boot Record for extended partition 4. |
| `Info-smart.txt` | 6.6 KB | **Complete:** Hard drive S.M.A.R.T. health dump captured at `15:49 UTC`. |
| `Info-OS-prober.txt` | 373 B | **Complete:** Detected operating systems on the drive. |
| `blkdev.list` & `blkid.list` | 3.7 KB | **Complete:** Partition UUID and filesystem attribute inventory. |

---

### 2.2 Operational Trace Analysis (`clonezilla.log` & `saving-error`)

From `/var/log/clonezilla.log` (preserved in persistence) and `saving-error-202609051520`:

#### A. `/dev/sda1` (Success)
```text
Running: partclone.ntfs -z 10485760 -N -L /var/log/partclone.log -c -s /dev/sda1 --output - | pigz -c --fast -b 1024 --rsyncable | split -a 2 -b 4096MB - /home/partimag/HP-EliteBook-FullDisk-2026-09-05-img/sda1.ntfs-ptcl-img.gz.
File system:  NTFS
Device size:  607.1 MB = 148223 Blocks
Space in use:  30.6 MB = 7462 Blocks
Partclone successfully cloned the device (/dev/sda1) to the image (-)
>>> Time elapsed: 7.17 secs (~ .119 mins)
```

#### B. `/dev/sda2` (Bad Sector Abort)
```text
Running: partclone.ntfs -z 10485760 -N -L /var/log/partclone.log -c -s /dev/sda2 --output - | pigz -c --fast -b 1024 --rsyncable | split -a 2 -b 4096MB - /home/partimag/HP-EliteBook-FullDisk-2026-09-05-img/sda2.ntfs-ptcl-img.gz.
File system:  NTFS
Device size:  151.9 GB = 37091583 Blocks
Space in use: 135.2 GB = 33009036 Blocks
Free Space:    16.7 GB = 4082547 Blocks
Block size:   4096 Byte
*************************************************************************
* WARNING: The disk has bad sectors. This means physical damage on the  *
* disk surface caused by deterioration, manufacturing faults, or        *
* another reason. The reliability of the disk may remain stable or      *
* degrade quickly. Use the --rescue option to efficiently save as much  *
* data as possible!                                                     *
*************************************************************************
Failed to save partition /dev/sda2.
```

#### C. `/dev/sda3` (Success)
```text
Running: partclone.ntfs -z 10485760 -N -L /var/log/partclone.log -c -s /dev/sda3 --output - | pigz -c --fast -b 1024 --rsyncable | split -a 2 -b 4096MB - /home/partimag/HP-EliteBook-FullDisk-2026-09-05-img/sda3.ntfs-ptcl-img.gz.
File system:  NTFS
Device size:  119.0 GB = 29041151 Blocks
Space in use: 100.7 GB = 24593022 Blocks
Free Space:    18.2 GB = 4448129 Blocks
Total Time: 00:29:09, Ave. Rate:   3.46GB/min, 100.00% completed!
Partclone successfully cloned the device (/dev/sda3) to the image (-)
>>> Time elapsed: 1757.06 secs (~ 29.284 mins)
```

---

## 3. Hardware Forensics: Physical Drive Health (`/dev/sda`)

From `Info-smart.txt` captured directly during the backup session:

* **Drive Model:** SanDisk SSD PLUS 1000GB (Firmware `UH5100RL`, S/N `19360S477706`)
* **Power-On Hours:** **23,007 hours** (~2.6 years of continuous active uptime).
* **Total NAND Writes:** **36,102 GiB** written / **28,708 GiB** read.
* **Critical Health Indicators:**
  - **Attribute 169 (`Total_Bad_Block`):** **`888`** retired flash blocks.
  - **Attribute 187 (`Reported_Uncorrect`):** **`47,425`** uncorrectable read errors reported by the SSD controller.
  - **Attribute 5 (`Reallocated_Sector_Ct`):** `0` (Standard for SSDs before spare reserve exhaustion).
  - **Self-Test Log:** Multiple logged entries:
    ```text
    # 1 Short offline Fatal or unknown error 80% lifetime (22852 hours) LBA: 0
    ```

### Engineering Interpretation:
The SanDisk SSD has accumulated significant flash wear and uncorrectable NAND read blocks within the LBA range belonging to `/dev/sda2` (the Windows C: partition). When `ntfsclone` / `partclone.ntfs` attempts a standard cluster-consistent read, the Linux kernel encounters an uncorrectable ATA I/O error and returns `EIO`. In default strict mode, Partclone immediately aborts to avoid generating a corrupted filesystem image without explicit operator approval.

---

## 4. Fresh Diagnostic Bundle Harvest

To ensure no logs are lost, the harvest tool [`export_vm_and_system_logs_to_fat.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/export_vm_and_system_logs_to_fat.sh) was updated to extract live and persistent Clonezilla and Partclone logs.

A comprehensive diagnostic archive was generated at:
**`/ntfs/vm_diagnostic_bundle_20260905_174707/`**

### Harvested Log Files:
1. **`clonezilla.log` (8.2 KB):** Complete timeline of the backup job.
2. **`partclone-sda1.log` (670 B):** Verification log for `/dev/sda1`.
3. **`partclone-sda2.log` (1.1 KB):** Detailed error report capturing the exact bad sector warning.
4. **`partclone-sda3.log` (681 B):** Verification log for the 100.7 GB transfer of `/dev/sda3`.
5. **`guest_startup_storage.log`:** Telemetry proving `/dev/sdb4` and `/dev/sda5` auto-mounted cleanly on physical boot.
6. **`guest_dmesg.log` & `guest_syslog_tail.log`:** Full kernel and system logs from the physical live session.
7. **`host_kernel_dmesg.log` & `verify_ventoy2_audit.log`:** Host audit traces.

---

## 5. Actionable Remediation Plan to Back Up Partition `/dev/sda2`

Because `/dev/sda` contains worn NAND blocks on partition 2, there are three proven methods to capture `/dev/sda2` into your `home40` repository without errors:

### Strategy 1: Clonezilla with Rescue Flag (`-rescue`) — Recommended
In `rescue_suite_launcher.sh` or Clonezilla advanced CLI:
* **The Flag:** Pass `-rescue` (or `--rescue`) to Clonezilla / Partclone.
* **Mechanism:** When Partclone encounters a bad block, instead of terminating, it zeroes out or skips the damaged block, logs the sector, and continues imaging the remaining 135 GB of healthy data.
* **Command:**
  ```bash
  sudo ocs-sr -q2 -c -j2 -z1p -i 4096 -rescue -p true saveparts HP-EliteBook-SDA2-Rescue-img sda2
  ```

### Strategy 2: Pre-Scan with NTFS Repair (`ntfsfix`)
Before running the backup:
```bash
sudo ntfsfix -b -d /dev/sda2
```
* Clears the NTFS dirty flag and attempts to remap or mark bad clusters in the NTFS `$BadClust` metadata table so Partclone skips them natively.

### Strategy 3: Raw Byte-Level Recovery via `ddrescue`
If the Windows filesystem metadata is severely damaged:
```bash
sudo ddrescue -b 4096 -d -r 2 /dev/sda2 /mnt/backup/sda2_raw.img /mnt/backup/sda2_rescue.map
```
* Streams raw sectors directly across SSHFS, retrying unreadable blocks with progressive multi-pass scraping.
