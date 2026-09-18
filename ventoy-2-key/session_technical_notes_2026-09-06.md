# Comprehensive Technical Session Notes: Disk Integrity Audits, Host SSH Setup, Rescuezilla Persistence & USB Boot Resilience

**Author / Session Lead:** Alan P & Assistant  
**Date of Record:** September 6, 2026  
**Host Hardware:** HP ZBook 15u G5 (`alan-USB-zbook`) / HP EliteBook 8470p  
**Target Storage Devices:**
* **Internal Drive (`/dev/sda`):** Crucial 1TB SSD (`Crucial_CT1024M550SSD1`)
* **Multi-Boot USB Key (`/dev/sdb`):** 128 GB SanDisk / Toshiba Hybrid Ventoy Key (`Ventoy 2` & `Ventoy 1`)
**Primary Working Directory:** `devices/setup-usb-boot-keys/Ventoy/`  
**Sub-Repository:** `devices/setup-usb-boot-keys/` (Branch: `main`)

---

## 1. Executive Summary

This session covered five interrelated technical operational domains:
1. **Remote SSH & Mosh Authentication Configuration:** Diagnosed key rejection and interactive password prompts when establishing remote mosh connections to `alanp@100.127.153.93:2222`. Automated host key scanning into `~/.ssh/known_hosts` and identified required `ssh-copy-id` user authentication steps.
2. **Rescuezilla Persistence Container Relabeling (`casper-rw` vs `writable`):** Solved why Rescuezilla 2.6.1 Live GUI failed to detect and mount the persistence container (`rescuezilla-persistence.dat`). Modern Casper in Ubuntu 24.10 (Oracular Oriole) deprecated `casper-rw` and requires the label `writable`. Applied `e2label` and verified with `blkid`.
3. **USB Ubuntu Partition Boot Hang & Display Driver Crash:** Investigated why selecting the installed USB Ubuntu 22.04 LTS OS from the Ventoy F6 menu resulted in an indefinite boot hang. Traced the root cause in `/var/log/syslog` to a fatal Xorg display server crash in `glamor_egl_init` / `libgbm` / `libLLVM-15.so.1` on Intel GPU modesetting. Fixed configuration via `WaylandEnable=false`, removed redundant `sshfs` from `/etc/fstab`, and added Safe Graphics (`nomodeset`) and Text Console (`systemd.unit=multi-user.target`) recovery stanzas into `ventoy_grub.cfg`.
4. **Internal SSD Partition `sda4` Geometry & Health Audit:** Confirmed that `/dev/sda4` is not a corrupt data filesystem, but rather an MBR Extended Partition Container (1 KB / 2 sectors) enclosing logical partition `/dev/sda5`. Verified that the partition table structure is fully intact and clean.
5. **Internal Windows System Partition `sda2` Health & CHKDSK Audit:** Mounted `/dev/sda2` (141.5 GB NTFS) read-only via `udisksctl` and inspected the latest Windows `\bootex.log` generated during boot. Confirmed that Windows `chkdsk` repaired metadata errors (deleted corrupt MFT file record segment `1C55E8`, pruned dangling index entries, and corrected `$BITMAP`), concluding with `0 KB in bad sectors` and `No further action is required`.

---

## 2. Topic 1: SSH Host Key Management & Mosh Setup

### 2.1 Problem Description
The user required access to `alanp@100.127.153.93` via:
```bash
mosh --ssh="ssh -p 2222" alanp@100.127.153.93
```
Initial attempts prompted for missing host verification, followed by a password prompt:
```text
Connecting to HP ZBook G5 (Port 2222) (alanp@100.127.153.93)...
Executing: mosh --ssh="ssh -p 2222" alanp@100.127.153.93
alanp@100.127.153.93's password:
```

### 2.2 Host Key Scan & Installation
* Scanned SSH host keys on port 2222 using `ssh-keyscan`:
  ```text
  [100.127.153.93]:2222 ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBChzo7YkvNMc3oFAVUfIBfbyIc0/TTkj326LrFiY5E5dycxSvzJXcXd8dgWMDfTlDrvPeMaGuxS/prz69Iach1s=
  [100.127.153.93]:2222 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDGufZnhvV5Q5vo0FwLtCGMc/ZeK000ahmgCvbtXD5FYg2dE6q52kyCOa8dZXw9j9I91+a239lB36NOwPcFruVrf8GwqoOCgNr69mqhoW2+q9rNxMaCCX1/CXu1xZlfy/NJxwyIjWVND3v3Pw8C4L5dpMD74V1ZA/+ntxP99M1SeDaPyhqC2plNG28RXYNnFNmkhLbWnpf0H+gh+E3TwYCkz0B+ZwUHRg2vFegfsqQkH3Kl+lVh2MJdgO2wstBA7rS+pdNFooZ6xvtPdxyxKJQw/aYh3C1YDJcN5iE7630TboB+pFFq85QTFlZzrAoZ50yXm0NWVbbjhEcQJe3JADbj+7efo4fR7LTKwwh0QGqC5NXsxbOAb3n29xNiPdk1VdSyf8YgRW5VdYuuhxzfKqOiGwepRzm7Rxs0HAbZ6r4ro2LIhQKCRleMHYgmCDe4rCQDrVa2Lffdd14mtfT5T6h9FEBNWpi6vOWHMFjcH4n05bafue0uO3XUklu/UZezeBk=
  [100.127.153.93]:2222 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHVURvBZPNId6BQibp6+fWBjB0hJKz0BNULfFRS7tis
  ```
* Appended the host keys directly to `~/.ssh/known_hosts` to suppress unknown host verification prompts.
* **Authentication Note:** Inspected local public key `~/.ssh/id_ed25519.pub`. Clarified that the password prompt is standard OpenSSH behavior until the user's public key is copied to `/home/alanp/.ssh/authorized_keys` on the target machine via `ssh-copy-id -p 2222 alanp@100.127.153.93`.

---

## 3. Topic 2: Rescuezilla Persistence Relabeling (`casper-rw` ➔ `writable`)

### 3.1 Background & Root Cause Analysis
* **Symptom:** Selecting `>>> Rescuezilla 2.6.1 Live GUI (+Persistence)` from Ventoy resulted in booting into a fresh, unconfigured live desktop. No files or mount points persisted across reboots.
* **Investigation:**
  * Inspected the ISO: `rescuezilla-2.6.1-64bit.oracular.iso` is built on Ubuntu 24.10 (Oracular Oriole).
  * Casper (Ubuntu live boot scripts) historical behavior used volume label `casper-rw`.
  * Modern Ubuntu live systems (specifically Ubuntu 20.04+, 24.04 Noble, and 24.10 Oracular) deprecated `casper-rw` and require the persistent overlay container to be formatted with label **`writable`**.
  * The actual persistence container on the USB key (`/media/alan/Ventoy/rescuezilla-persistence.dat`) was formatted with `LABEL="casper-rw"`. Consequently, the Casper initramfs script bypassed the container during device discovery and ran entirely in RAM.

### 3.2 Executed Fix & Validation
1. **Relabeled Container:**
   ```bash
   /sbin/e2label /media/alan/Ventoy/rescuezilla-persistence.dat writable
   ```
2. **Verified via `blkid`:**
   ```text
   /media/alan/Ventoy/rescuezilla-persistence.dat: LABEL="writable" UUID="309a9e74-4230-458f-b89e-c492dcd3506f" TYPE="ext4"
   ```
3. **Automated Audit Integration:** Updated `verify_ventoy2.sh` to include automated verification of the `writable` label via `blkid`.

---

## 4. Topic 3: USB Ubuntu Boot Hang & GDM / Xorg Crash Resolution

### 4.1 Log Analysis & Failure Diagnostics
When booting the installed Ubuntu 22.04 LTS OS on Partition 3 (`/dev/sdb3`) via the Ventoy custom menu (**`F6`**), the boot process hung indefinitely.

Auditing `/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/var/log/syslog` revealed:
1. **Remote Filesystem (`home40` / SSHFS):**
   - The `/etc/fstab` entry `alan@192.168.1.34:/media/alan/home40 /home/alan/mnt/apelite fuse.sshfs x-systemd.automount,_netdev` did **not** hang the system boot.
   - Systemd set up the automount point without blocking. However, desktop daemons (`gvfs-udisks2-volume-monitor`, `pool`) queried the mountpoint while offline, triggering repeated `status=1/FAILURE` loops.
2. **Fatal Display Server Crash (GDM3 / Xorg):**
   - The primary failure was an Xorg server crash loop during graphical initialization.
   - GDM launched `/usr/libexec/gdm-x-session`, which attempted hardware GL acceleration via Modesetting + Glamor/EGL on `/dev/dri/card1` (Intel GPU).
   - `glamor_egl_init` crashed in `gbm_create_device` through `libLLVM-15.so.1`:
     ```text
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) Backtrace:
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 0: /usr/lib/xorg/Xorg (OsLookupColor+0x139)
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 1: /lib/x86_64-linux-gnu/libc.so.6 (__sigaction+0x50)
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 2: /lib/x86_64-linux-gnu/libLLVM-15.so.1
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 20: /lib/x86_64-linux-gnu/libgbm.so.1 (gbm_create_device+0x48)
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: (EE) 21: /usr/lib/xorg/modules/libglamoregl.so (glamor_egl_init+0x67)
     alan-USB-zbook /usr/libexec/gdm-x-session[1257]: Fatal server error: (EE) Server terminated with error (1). Closing log file.
     alan-USB-zbook gdm3: Gdm: GdmLocalDisplayFactory: maximum number of X display failures reached: check X server log for errors
     ```
   - GDM reached its maximum failure threshold and gave up, leaving the screen permanently frozen at Plymouth.

### 4.2 Actions Taken & Recovery Stanzas
1. **Fstab Cleanup:** Stripped the redundant `sshfs` mount line from `/etc/fstab` on `/dev/sdb3` (backed up to `fstab.bak`). Remote storage is now cleanly handled after login by `mount-home40.service`.
2. **GDM Configuration:** Set `WaylandEnable=false` in `/etc/gdm3/custom.conf` on `/dev/sdb3`.
3. **Resilient F6 Recovery Boot Stanzas (`ventoy_grub.cfg`):**
   Added two direct fallback options to `ventoy_grub.cfg`:
   * **`🟢 Direct Linux Kernel Boot - Safe Graphics (nomodeset)`**: Direct kernel boot with software rendering fallback; avoids Intel KMS driver crashes and directly presents the standard graphical login screen.
   * **`🟢 Direct Linux Kernel Boot - Text Console (systemd.unit=multi-user.target)`**: Boots directly to a multi-user text terminal. From the text prompt, the user can log in as `alan` and start the desktop via `sudo systemctl start gdm3` or `startx`.

---

## 5. Topic 4: Partition `sda4` Geometry & Extended Container Audit

### 5.1 Investigation & Geometry
* **Question:** Is `/dev/sda4` clean, or does it suffer from filesystem corruption?
* **Findings:**
  - Audited `/sys/class/block/sda4/`:
    ```text
    DEVNAME=sda4
    DEVTYPE=partition
    PARTN=4
    start=530249728
    size=2 sectors (1 KB)
    ```
  - Kernel topology in `dmesg`:
    ```text
    sda: sda1 sda2 sda3 sda4 < sda5 >
    ```
* **Conclusion:**
  - `/dev/sda4` is an **MBR Extended Partition Table Container**, not a formatted data filesystem.
  - In MBR partitioning, when more than four partitions are needed, the fourth partition table entry is configured as an extended container holding logical partitions (`sda5`).
  - The kernel parses `sda4 < sda5 >` with zero warnings, and `sda5` (567 GB ext4 rootfs) mounts cleanly. The partition table structure is fully intact.

---

## 6. Topic 5: Partition `sda2` (Windows System) Health & CHKDSK Audit

### 6.1 Mount & Filesystem Verification
* Partition `/dev/sda2` (141.5 GB NTFS, UUID `E40ABED00ABE9F4C`) was mounted read-only via `udisksctl` at `/media/alan/E40ABED00ABE9F4C/`.
* Directory structures (`\Windows`, `\Program Files`, `\Users`, `\ProgramData`) were verified intact and readable.

### 6.2 CHKDSK Execution Analysis (`bootex.log`)
Windows executed an automated boot-time disk check on September 5, 2026 at 23:22 UTC. The log recorded:
1. **Stage 1 (File Record Verification):**
   - Encountered corrupt file record segment `1C55E8` (`BAAD` signature) and deleted it.
   - Processed 2,604,288 file records with 0 bad file records.
2. **Stage 2 (Index & Linkage Verification):**
   - Pruned orphaned directory index entries pointing to unused file records (`WALKTH~1.3`, `175189~2.JPG`, `yaGv.md`).
   - Recovered 2 unindexed files into `\found.010`.
3. **Stage 3 (Security & Allocation Verification):**
   - Cleaned up 675 unused security descriptor index entries.
   - Corrected free space allocation errors in the MFT `$BITMAP` attribute.
4. **Final CHKDSK Verdict:**
   ```text
   Windows has made corrections to the file system.
   No further action is required.
   148,366,332 KB total disk space.
   128,019,004 KB in 1,182,063 files.
             0 KB in bad sectors.
    16,759,280 KB available on disk.
   ```
* **Conclusion:** The Windows NTFS filesystem metadata has been repaired by CHKDSK, reporting 0 KB in bad sectors. The partition was cleanly unmounted.

---

## 7. Master File Changes & Synchronization Register

| File Path | Component / Target | Description of Action Taken |
| :--- | :--- | :--- |
| `~/.ssh/known_hosts` | User environment | Added host keys for `100.127.153.93:2222` (ECDSA, RSA, ED25519). |
| `/media/alan/Ventoy/rescuezilla-persistence.dat` | Live USB Key (`/dev/sdb1`) | Relabeled ext4 filesystem from `casper-rw` to `writable`. |
| `/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/etc/fstab` | Live USB Key (`/dev/sdb3`) | Stripped redundant `sshfs` mount line; created `fstab.bak`. |
| `/media/alan/e0d8ad1a-410b-4245-9192-66d2a16077b9/etc/gdm3/custom.conf` | Live USB Key (`/dev/sdb3`) | Enforced `WaylandEnable=false`. |
| `ventoy-2-key/ventoy_grub.cfg` & `/media/alan/Ventoy/ventoy_grub.cfg` | Repo & Live USB Key | Added Safe Graphics (`nomodeset`) and Text Console (`systemd.unit=multi-user.target`) fallback stanzas. |
| `ventoy-2-key/verify_ventoy2.sh` | Repo (`ventoy-2-key/`) | Added automated test validating persistence volume label is `writable`. |
| `ventoy-2-key/README.md` | Repo (`ventoy-2-key/`) | Updated persistence label spec to `writable` and added Section 4.2 fallback recovery entries. |
| `ventoy-2-key/TEST_PLAN.md` | Repo (`ventoy-2-key/`) | Updated TC-07 (`writable` label), TC-08 (F6 recovery stanzas), and TC-09 (hardware boot matrix). |
| `ventoy-2-key/troubleshooting_persistence_and_usb_boot_hang.md` | Repo (`ventoy-2-key/`) | Preserved dedicated troubleshooting narrative artifact in version control. |
| `Ventoy/session_technical_notes_2026-09-06.md` | Repo (`Ventoy/`) | Comprehensive technical session notes covering all topics and audits. |
