# Session Technical Notes: Physical Bare-Metal Backup Forensics, `sda2` Repair Runbook & Artifact Audit

**Date:** September 5, 2026 (Evening Baseline)  
**Host Target Machine:** HP EliteBook 8470p (`alan-USB-zbook`)  
**Physical Storage:** Internal SanDisk SSD PLUS 1000GB (`/dev/sda`, S/N `19360S477706`)  
**Boot Key:** Ventoy 2 USB Key (`/dev/sdb`, 128 GB MBR `199e46a9`)  
**Remote Backup Repository:** `192.168.1.34:/media/alan/home40/Clonezilla` (via SSHFS)  
**Current Git Commit:** `fc2aaf9` (`main`, ahead of `origin/main` by 4 commits)  

---

## 1. Executive Summary & Core Milestones

During the September 5, 2026 active session, three major technical phases were accomplished:
1. **Physical Bare-Metal Backup Execution & Forensic Investigation:**
   - Booted the physical HP EliteBook 8470p from the Ventoy 2 USB drive into the persistent Rescuezilla/Clonezilla live environment.
   - Successfully imaged `/dev/sda1` (Windows System Reserved, 11 MB) and `/dev/sda3` (NTFS User Data, ~65 GB across 17 chunks) to remote SSHFS network storage on `home40`.
   - Forensically investigated the failure/skipping of `/dev/sda2` (Windows 10 C: drive, 141.5 GB), identifying SSD controller hardware errors (47,425 reported uncorrectable errors, 888 bad flash blocks).
2. **Architectural Analysis & Windows `chkdsk` Operational Runbook:**
   - Conducted an in-depth technical analysis of why native Windows `chkdsk C: /f /r` is required over Linux `ntfsfix` for NTFS bad block repair and Flash Translation Layer (FTL) sector retirement.
   - Authored and committed a comprehensive operational runbook (`recommendation_sda2_windows_chkdsk_and_repair_runbook.md`) documenting both the primary Windows repair workflow and the fallback Clonezilla `-rescue` imaging bypass.
3. **Interactive HITL Conversational Artifact Audit & Specification Synchronization:**
   - Audited all candidate screenshots and diagnostic artifacts generated during the session one by one with Human-In-The-Loop (HITL) confirmation prompts.
   - Synchronized [README.md](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/README.md) and [TEST_PLAN.md](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/ventoy-2-key/TEST_PLAN.md) with **TC-19** (Bare-Metal Disk Backup) and **TC-20** (Diagnostic Bundle Harvesting).

---

## 2. Detailed Technical Discussion Points & Root-Cause Analyses

### 2.1 Physical Bare-Metal Backup Forensics (`HP-EliteBook-FullDisk-2026-09-05-img`)

#### A. Imaging Outcome
* **`/dev/sda1` (System Reserved, 579 MB):** Imaged cleanly via `partclone.ntfs` with `pigz` fast compression in 7.17 seconds (`sda1.ntfs-ptcl-img.gz.aa`, 11 MB).
* **`/dev/sda3` (NTFS Data, 110.8 GB total / 100.7 GB used):** Imaged cleanly in 29 minutes 17 seconds (`sda3.ntfs-ptcl-img.gz.aa` through `.aq`, 17 chunks of ~3.9 GB = ~65 GB).
* **Geometry & Boot Metadata:** MBR (`sda-mbr`), cylinder-head-sector boundaries (`sda-chs.sf`), stage 1.5 boot code (`sda-hidden-data-after-mbr`), extended boot records (`sda4-ebr`), and partition layout (`sda-pt.sf`, `sda-pt.parted`) were completely preserved.

#### B. The Skipped Partition (`/dev/sda2`, Windows 10 OS Partition)
* **Error Encountered:** `partclone.ntfs` aborted with the following trace in `saving-error-202609051520`:
  ```text
  WARNING: The disk has bad sectors. This means physical damage on the disk surface...
  Use the --rescue option to efficiently save as much data as possible!
  ```
* **Hardware Forensic Trace (S.M.A.R.T. ID 187):**
  - Drive: SanDisk SSD PLUS 1000GB (Firmware `UG4500RL`).
  - Attribute `187 Reported_Uncorrect`: **47,425 raw events**.
  - Attribute `005 Reallocated_Sector_Ct`: **888 bad flash blocks**.
  - Attribute `230 Media_Wear_Percentage`: **0% consumed** (flash cells are healthy overall, but specific NAND physical pages experienced ECC decode failure).
* **Safety Mechanism:** Clonezilla's standard `ocs-sr` defaults to strict abort on bad blocks to protect data integrity. Because `-rescue` was not active, Partclone skipped `sda2` to avoid propagating corrupted filesystem structures.

---

### 2.2 Forensic Comparison: Windows `chkdsk` vs Linux `ntfsfix`

A critical discussion centered on whether to repair `sda2` using Linux tools (`ntfsfix`) or native Windows `chkdsk`:

| Capability / Mechanism | Linux `ntfsfix` / `ntfs-3g` | Native Windows `chkdsk C: /f /r` |
| :--- | :--- | :--- |
| **Fix Minor Journal Flags** | Marks volume dirty to schedule Windows scan; clears journal | Cleans volume flags and commits journal cleanly |
| **Read Bad Sector Scanning** | No surface read verification | Exhaustively reads every cluster in Stage 4 |
| **SSD FTL Bad Block Reallocation** | Does not trigger reallocation | Forces rewrite of failing clusters, triggering SSD controller FTL sector retirement |
| **NTFS Metadata `$BadClust` Update** | **Cannot update `$BadClust`** | Adds unreadable clusters to `$BadClust:$Bad` |
| **Partclone Safe Imaging Post-Fix** | Still fails if unreadable clusters exist | **Succeeds:** Partclone queries `$BadClust`, skips bad clusters, and images cleanly |

**Conclusion:** Windows `chkdsk C: /f /r` is mandatory because Linux NTFS utilities cannot perform surface scans, cannot remap SSD hardware flash blocks, and cannot update the NTFS `$BadClust` system file.

---

### 2.3 Interactive HITL Conversational Artifact Audit

All conversational artifacts created during the session were reviewed individually with the user:

1. **`vm_rescue_suite_main_menu.png` (`media_1788610534481.png`):** Accepted and committed to `docs/screenshots/vm_rescue_suite_main_menu.png` (`9b18dc1`).
2. **`vm_backup_assistant_target_selection.png` (`media_1788610538540.png`):** Accepted and committed to `docs/screenshots/vm_backup_assistant_target_selection.png` (`08ece54`).
3. **`media_1788559826014.png` (GNOME Disks unmounted FAT32):** Reviewed and skipped per HITL decision.
4. **`media_1788564738940.png` / `media_1788599871487.png` (Exec line error popups):** Reviewed and skipped.
5. **`media_1788564749376.png` (`[[: not found` terminal):** Reviewed and skipped.
6. **`media_1788606464242.png` (`df -h` OverlayFS table):** Reviewed and skipped.
7. **`media_1788607316920.png` (`chmod /scripts/id_rsa: Operation not permitted`):** Reviewed and skipped.
8. **`media_1788610545240.png` / `media_1788618025776.png` (Empty FAT cd prompt):** Reviewed and skipped.

---

## 3. Comprehensive Log of File Changes

### 1. `TEST_PLAN.md`
* Added **`TC-19` (Bare-Metal Disk Backup)**: Validates physical boot on HP EliteBook, imaging of `sda1` and `sda3` (~65 GB), and safe abort on `sda2` bad sectors.
* Added **`TC-20` (Diagnostic Bundle Harvesting)**: Validates live execution of `export_vm_and_system_logs_to_fat.sh`, gathering `clonezilla.log`, `partclone.log`, guest dmesg, and desktop manifests into `/ntfs/`.

### 2. `README.md`
* Updated Section 7 (Log Export Utility) to document the harvesting of live and persistent Clonezilla and Partclone operational logs.

### 3. `export_vm_and_system_logs_to_fat.sh`
* Added live check for `/var/log/clonezilla*.log` and `/var/log/partclone*.log` directly from `/var/log/`.
* Added persistence container extraction of Partclone and Clonezilla logs from `$tmp_m/upper/var/log/`.
* Added live harvesting of `syslog` (tail 500 lines) and kernel `dmesg -T`.

### 4. `comprehensive_physical_backup_and_bad_sector_forensics_2026-09-05.md`
* Authored forensic documentation detailing:
  - Repository inventory of `HP-EliteBook-FullDisk-2026-09-05-img` on `home40`.
  - Partclone operational trace on `/dev/sda1`, `/dev/sda2`, and `/dev/sda3`.
  - SanDisk SSD S.M.A.R.T. health breakdown (Attribute 187, Attribute 005, Attribute 230).
  - Risk assessment and action plan.

### 5. `recommendation_sda2_windows_chkdsk_and_repair_runbook.md`
* Authored exact operational runbook containing:
  - Phase 1: Native Windows repair commands (`chkdsk C: /f /r`, `dism`, `sfc`).
  - Phase 2: Follow-up Clonezilla imaging runbook.
  - Option B: Immediate Clonezilla `-rescue` imaging command.
  - SSD hardware longevity and physical replacement advisory.

---

## 4. Git Commit History (Recent Series)

```text
fc2aaf9 docs(ventoy-2): update test matrix and README with TC-19 bare-metal backup and TC-20 log harvest
2771ad8 docs(ventoy-2): add exact operational recommendation and runbook for sda2 windows chkdsk repair
d769030 docs(ventoy-2): add comprehensive forensic report for physical bare-metal backup and sda2 bad sector analysis
029e4b7 fix(export): harvest live and persistent clonezilla and partclone logs into diagnostic bundle
99c27f7 docs(ventoy-2): synchronize README, TEST_PLAN, and persistence docs with latest baseline
d30d6fe docs(ventoy-2): add comprehensive session technical notes for VM emulation and SSH persistence packaging
08ece54 docs(artifacts): add screenshot of backup assistant remote mount and target selection in VM
9b18dc1 docs(artifacts): add screenshot of unified rescue suite main menu in VM
97ad5b3 fix(qemu): use isa-fdc.fdtypeA=none and fdtypeB=none to disable floppy drive probing
176fa05 fix(qemu): suppress legacy floppy driveA probing to silence fd0 errors
ef55748 fix(ssh-auth): configure sshd privsep user, set ubuntu live password, and deploy authorized_keys
b944731 fix(vm-and-suite): package openssh-server into persistence, add noprompt to qemu, and add diagnostic bundle export to main menu
```
