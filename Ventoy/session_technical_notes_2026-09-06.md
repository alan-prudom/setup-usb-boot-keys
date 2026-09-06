# Comprehensive Technical Notes: Disk /dev/sda Degradation Forensics, Turnkey Rescue Mode Integration & Artifact Management

**Author / Session Lead**: Alan P & Assistant  
**Date of Record**: September 6, 2026 (01:25 UTC+1)  
**Primary Target System**: HP ZBook 15u G5 / HP EliteBook 8470p  
**Active Block Devices**:
* Internal Drive: `/dev/sda` — SanDisk SSD PLUS 1000GB (`19360S477706`, UH5100RL)
* Multi-Boot USB: `/dev/sdb` — 128 GB Flash Storage (Ventoy v1.0.99, Ubuntu 22.04 LTS on `sdb3`)
* Remote Backup Storage: `192.168.1.34:/media/alan/home40/Clonezilla/` (SSHFS over LAN)  
**Repositories**:
* Primary Sub-Repo: `devices/setup-usb-boot-keys` (Branch: `main`)
* Secondary Mirror: `~/Documents/setup-usb` (Branch: `main`)
* Parent Repo: `/home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs`  

---

## 1. Executive Summary

During backup operations on the night of September 5–6, 2026, an imaging pass targeting `/dev/sda2` (Windows 11 NTFS partition) aborted prematurely with physical bad sector warnings. 

This session performed a deep log and hardware telemetry investigation, uncovered the exact root cause of the abort, implemented a turnkey **Rescue Mode (`--rescue`)** selection in the primary CLI backup runner, deployed the updated code into the live persistence overlay (`rescuezilla-persistence.dat`), enforced a strict **"no pngs"** policy for conversational artifacts, and preserved raw text-based diagnostic logs in version control.

---

## 2. Forensics & Investigation of the `/dev/sda` Imaging Failure

### 2.1 Error Trace Identification
Inspecting the remote storage directory on `192.168.1.34` revealed a failed image directory:  
`HP-ZBook-Custom-2026-09-05-2358-img/` containing the file `saving-error-202609060000`.

* **Timestamp of Failure**: 2026-09-05 23:59:02 UTC to 2026-09-06 00:00:18 UTC.
* **Target Partition**: `/dev/sda2` (141.5 GB NTFS, ~134.8 GB allocated, 17.2 GB free).
* **Partclone Failure Signature**:
  ```text
  Reading Super Block
  memory needed: 25607972 bytes
  bitmap 4636448 bytes, blocks 2*10485760 bytes, checksum 4 bytes
  Calculating bitmap... Please wait... 
  File system: NTFS
  Device size: 151.9 GB = 37091583 Blocks
  Space in use: 134.8 GB = 32901768 Blocks
  Free Space: 17.2 GB = 4189815 Blocks
  Block size: 4096 Byte
  *************************************************************************
  * WARNING: The disk has bad sectors. This means physical damage on the *
  * disk surface caused by deterioration, manufacturing faults, or *
  * another reason. The reliability of the disk may remain stable or *
  * degrade quickly. Use the --rescue option to efficiently save as much *
  * data as possible! *
  *************************************************************************
  Failed to save partition /dev/sda2.
  ```

### 2.2 Root Cause Analysis
By default, Clonezilla's native `ocs-sr` calls Partclone in **strict integrity mode**. If Partclone encounters an I/O read timeout or unreadable cluster mark on an NTFS volume, it immediately halts execution with exit code 1 to alert the user rather than writing an incomplete or corrupted backup image without explicit authorization.

### 2.3 Physical Drive Health Audit (SMART Telemetry)
Querying the drive controller (`smartctl -a /dev/sda`):
* **Model Family**: Marvell-based SanDisk SSD PLUS 1000GB (S/N: `19360S477706`).
* **Power-On Hours**: 23,008 hours (~2.6 years of continuous operation).
* **Attribute 187 (`Reported_Uncorrect`)**: **47,536 uncorrectable read errors** reported across SATA interface.
* **Attribute 169 (`Total_Bad_Block`)**: **888 bad flash blocks**.
* **Self-Test Failure History**: 21 logged short offline self-tests; every test aborted at 80% with `Fatal or unknown error at LBA 0`.
* **Conclusion**: The drive exhibits physical flash degradation. Standard non-rescue imaging passes will consistently abort on damaged clusters.

---

## 3. Implementation: Turnkey Rescue Mode in `run_rescuezilla_backup_cli.sh`

To allow imaging of decaying or bad-sector disks without manual scripting, an interactive **Rescue Mode prompt** was incorporated into the main backup runner:

### 3.1 Interactive CLI Prompt Added
```text
[5/5] Bad Sector & Hardware Rescue Handling
  ℹ️  Why we ask this: If the source drive has physical degradation (like SanDisk/Crucial SSDs with uncorrectable sectors), standard Partclone aborts immediately to protect data integrity. In Rescue Mode ('--rescue'), Partclone continues past bad blocks and zeroes unreadable sectors so imaging finishes successfully.
  [1] Standard Mode (Strict integrity check; abort if bad sectors are found)
  [2] 🚨 Rescue Mode (--rescue: bypass bad sectors, zero unreadable blocks, continue imaging)
```

### 3.2 Under-the-Hood Behavior
* When Option `[2]` is selected:
  * `RESCUE_FLAG="--rescue"` is set.
  * In Clonezilla Native (`ocs-sr`), `--rescue` is passed directly to Partclone.
  * In Rescuezilla CLI (`rescuezillapy`), `--rescue` is passed to the argument list.
* **Partclone Behavior in Rescue Mode**:
  * Skips unreadable sectors without aborting.
  * Writes zeroed blocks to the target image stream to preserve filesystem geometry.
  * Records the exact bad block offsets to `/var/log/partclone.log`.
  * Allows the backup operation to finish with exit code 0.

### 3.3 Live Persistence Deployment
* Executed `deploy_four_tier_persistence.sh`.
* Verified update across all four persistence layers:
  * Mounted `/media/devmon/Ventoy/rescuezilla-persistence.dat` to `/mnt/rescue_persist`.
  * Deployed updated `run_rescuezilla_backup_cli.sh` to `/scripts/` and `/upper/scripts/`.
  * Cleanly synced and unmounted loopback container.

---

## 4. Conversational Artifacts & Telemetry Preservation

### 4.1 "No PNGs" Policy Enforcement
* The user explicitly instructed: **"no pngs"**.
* In accordance with this directive, all 10 conversational screenshot artifacts in `.tempmediaStorage/*.png` were bypassed.
* Zero binary image files were committed to version control.

### 4.2 Text-Based Diagnostic Logs Preserved
Per user approval (*"both please"*), the raw text logs from the recent failed run were copied to a dedicated directory and committed to Git:

1. **`Ventoy/telemetry/sda2_partclone_bad_sector_error_2026-09-06.log`**:
   * Exact Clonezilla execution log from the failed run.
   * Documents block counts (37,091,583 total blocks, 32,901,768 used blocks) and the Partclone bad sector warning.
2. **`Ventoy/telemetry/sda_sandisk_smart_telemetry_2026-09-06.txt`**:
   * Full SMART health snapshot of the SanDisk SSD PLUS 1000GB capturing the 47,536 uncorrectable read errors.

---

## 5. Summary of Commits & Working Tree Status

| Commit | Summary | Scope |
| :--- | :--- | :--- |
| **`a6233de`** | `feat(backup): add interactive Rescue Mode prompt with --rescue flag for degraded disks` | Core CLI backup runner |
| **`577fe35`** | `docs(telemetry): save sda2 partclone bad sector error log and sandisk SMART telemetry` | Telemetry logs |

* **Working Tree**: Completely clean, zero uncommitted changes.
* **Remote Parity**: Synchronized with `origin/main` and mirrored to `~/Documents/setup-usb`.
