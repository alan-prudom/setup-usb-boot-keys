# ⚠️ CRITICAL: Drive Failure Investigation Report

**Date:** 2026-09-03  
**Machine:** HP ZBook 15u G5 (`alan-USB-g5`)  
**Drive Under Investigation:** `/dev/sda` — Crucial CT1024M550SSD1 (1 TB, Serial: `14150C12DD88`)  
**Backup Image:** `HP-ZBook-FullDisk-2026-09-03-1904-img`  
**Backup Start:** 2026-09-03 19:04 UTC  
**Backup End:** 2026-09-03 22:03 UTC (~3 hours)  
**Network Destination:** `192.168.1.34:/media/alan/home40/Clonezilla/`

---

## 1. What Happened: The Full Picture

A full-disk backup was run covering all 9 partitions of `/dev/sda`. The backup ran for
approximately 3 hours. Despite `latest_backup.env` reporting Exit Code 0 (misleading — Clonezilla
continued past the failure to completion), the main backup log explicitly states:

```
Failed to save partition /dev/sda5.
This image was NOT saved correctly
```

---

## 2. Per-Partition Backup Result

| Partition | Label       | Size     | FS    | Backup Result                            |
| :-------- | :---------- | :------- | :---- | :--------------------------------------- |
| sda1      | SYSTEM      | 1.1 GB   | NTFS  | ✅ Saved correctly                       |
| sda2      | Windows     | 203.9 GB | NTFS  | ⚠️ Bad sectors detected during save — verify |
| sda3      | (extended)  | —        | —     | ✅ EBR saved                             |
| sda4      | HP_TOOLS    | 2 GB     | vFAT  | ✅ Saved correctly                       |
| sda5      | data        | 426.2 GB | NTFS  | ❌ FAILED — Partclone aborted on bad sectors |
| sda6      | swap        | —        | swap  | ⚠️ swapoff failed (already inactive)    |
| sda7      | w10         | 110 GB   | NTFS  | ✅ Saved correctly                       |
| sda8      | (boot)      | 512 MB   | vFAT  | ✅ Saved correctly                       |
| sda9      | (linux)     | 162.8 GB | ext4  | ✅ Saved correctly                       |

---

## 3. Physical Failure Evidence

### Kernel / Partclone Evidence (from `kernel_dmesg.log` at 20:20:29 UTC)

```
* WARNING: The disk has bad sectors. Physical damage on the disk surface  *
* caused by deterioration. Use the --rescue option to efficiently save    *
* as much data as possible!                                               *

ata1.00: failed command: READ FPDMA QUEUED
ata1.00: status: { DRDY ERR }
ata1.00: error: { UNC }     ← Uncorrectable read error (physical bad sector)
sd 0:0:0:0: [sda] Sense Key: Medium Error
sd 0:0:0:0: [sda] Add. Sense: Unrecovered read error - auto reallocate failed
I/O error, dev sda, sector 1053625480 op 0x0:(READ)
```

- **20 Buffer I/O errors** were recorded on `sda5` in the kernel log
- All errors cluster around **LBA `0x00cd0c88` (sector 13,438,088)** and nearby sectors
- `auto reallocate failed` confirms the SSD's spare sector pool is exhausted for this region

### SMART Attributes (Crucial CT1024M550SSD1, from `smart_sda.log`)

| SMART ID | Attribute                | Raw Value | Significance                                   |
| :------- | :----------------------- | :-------- | :--------------------------------------------- |
| 1        | Raw_Read_Error_Rate      | 409       | Elevated raw read error accumulation            |
| 187      | Reported_Uncorrect       | **35**    | 35 uncorrectable errors over drive lifetime     |
| 196      | Reallocated_Event_Count  | **16**    | 16 sectors physically remapped to spare pool    |
| 197      | Current_Pending_ECC_Cnt  | 0         | No currently pending sectors (all exhausted)    |
| 198      | Offline_Uncorrectable    | **7**     | 7 sectors that failed to remap — permanently bad |
| 199      | UDMA_CRC_Error_Count     | 20        | 20 SATA bus CRC errors (connector/cable suspect)|
| **202**  | **Percent_Lifetime_Remain** | **6** | ⚠️ **CRITICAL: Only 6% write endurance remaining** |

**SMART overall-health self-assessment: PASSED** — however SMART passes are unreliable near
end-of-life. The `Percent_Lifetime_Remain = 6` is authoritative.

**SMART ATA Error Log** — uncorrectable errors at LBA addresses:
```
Error: UNC at LBA = 0x00cd0c88 = 13,438,088
Error: UNC at LBA = 0x00cd07f8 = 13,436,920
Error: UNC at LBA = 0x007dc387 = 8,242,055
```

---

## 4. Risk Assessment

| Risk Item                          | Level          | Detail                                                          |
| :--------------------------------- | :------------- | :-------------------------------------------------------------- |
| Drive failure imminent             | 🔴 **CRITICAL** | 6% lifetime remaining + 7 offline uncorrectable sectors         |
| `sda5` data partition (426 GB)    | 🔴 **CRITICAL** | Backup FAILED — not protected; bad sectors are in this partition |
| `sda2` Windows partition (204 GB) | 🟠 **HIGH**    | Bad sectors detected during save; image integrity unverified    |
| Data loss risk                     | 🔴 **IMMEDIATE**| Further writes to `sda5` could worsen the damaged LBA region   |
| SATA CRC errors (199 = 20)        | 🟡 **MEDIUM**   | May indicate SATA cable or connector degradation                |

---

## 5. Recommended Actions (in priority order)

### 🔴 Step 1: Re-run `sda5` Backup in Rescue Mode (IMMEDIATE)
Run the `sda5_rescue_backup.sh` script (co-located with this report).
This uses `--rescue` mode to skip unreadable sectors and save everything possible.

### 🟠 Step 2: Verify `sda2` Image Integrity
After the rescue completes, verify the Windows partition image on the server:
```bash
partclone.ntfs --restore --dry-run -s <path>/sda2.ntfs-ptcl-img.gz.aa -o /dev/null
```

### 🟡 Step 3: Run `badblocks` Full Surface Scan
Map the complete extent of physical damage on `sda5`:
```bash
sudo badblocks -v -s -o /home/ubuntu/sda5_badblocks.txt /dev/sda5
```

### 🟡 Step 4: Check SATA Cable/Connector
The 20 UDMA CRC errors (SMART 199) suggest the SATA cable connecting this drive may be loose
or degraded. Reseat or replace the SATA cable when convenient.

### 🔵 Step 5: Plan SSD Replacement
This drive needs replacing. Recommended replacements (1 TB 2.5" SATA):
- Samsung 870 EVO 1TB
- Crucial MX500 1TB (successor to the M550 series)
- WD Blue SA510 1TB

Once a replacement is obtained, boot Rescuezilla and clone the disk:
```bash
sudo ocs-sr -q2 -j2 -z1p -i 4096 -sc -p true savedisk <new-image-name> sda
```
Then install the new drive and restore from image.

---

## 6. Diagnostic File Reference

All diagnostic data from the backup session is preserved in:
- `backup_diagnostic_20260903_221830/smart_sda.log` — full SMART dump
- `backup_diagnostic_20260903_221830/kernel_dmesg.log` — kernel I/O error trace
- `backup_diagnostic_20260903_221830/backup_operation.log` — full Clonezilla run log
- `backup_HP-ZBook-FullDisk-2026-09-03-1904-img.log` — main backup summary

---

*Report generated: 2026-09-03 23:45 BST*  
*Investigator: Antigravity AI Assistant*
