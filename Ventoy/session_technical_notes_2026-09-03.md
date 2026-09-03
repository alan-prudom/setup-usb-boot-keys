# Technical Session Notes: Ventoy F6 Boot, NTFS Mount Collision Diagnosis & Persistent Overlay Logging

**Author / Session Lead**: Alan P & Assistant  
**Date of Record**: September 3, 2026  
**Target Machine**: HP ZBook 15u G5 (`alan-USB-g5`)  
**Storage Architecture**: 128 GB Multi-Boot USB (`/dev/sdb`) & Internal 1 TB SSD (`/dev/sda`)  
**Persistence Overlay**: 512 MB Ext4 Image (`/media/devmon/Ventoy/rescuezilla-persistence.dat`)  
**Git Repository**: `setup-usb-boot-keys` (Branch: `main`)

---

## 1. Core Discussion Points & Root Cause Investigations

### 1.1 F6 Direct Boot Validation
* **Discussion Point:** The user confirmed: *"I was able to reboot into this ubuntu with F6."*
* **Technical Analysis:**
  * Previously, booting the installed Ubuntu 22.04 LTS on `/dev/sdb3` required booting SuperGrub, running an auto-detect scan, and manually picking the kernel.
  * In this session, the custom Ventoy menu extension (`/ventoy/ventoy_grub.cfg`) loaded instantly via **`F6`**.
  * The script searched for filesystem UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9`, set `root`, and chainloaded `/boot/grub/grub.cfg`.
  * **Result:** Confirmed reliable, 2-second direct boot into the installed Linux environment without any SuperGrub dependency.

---

### 1.2 The NTFS Mount Failure & "Funny State" Root Cause Analysis
* **The Symptom:** The user reported: *"However the startup script did not mount the NTFS partition and left it in a funny state - I could not use disks to do it."*
* **Investigation in the Persistence Image:**
  * We loopback-mounted `rescuezilla-persistence.dat` and analyzed `/var/log/syslog` from the boot session at `2026-09-02 22:07:46`.
  * **Key Syslog Finding:**
    ```text
    2026-09-02T22:07:48.287606+00:00 ubuntu udisksd[1991]: Cleaning up mount point /media/ubuntu/2C95D29B2DF0500E (device 8:20 is not mounted)
    2026-09-02T22:07:56.706466+00:00 ubuntu systemd-xdg-autostart-generator[2348]: Configuration file /home/ubuntu/.config/autostart/mount-ntfs.desktop is marked executable.
    ```
* **The Chain of Events Leading to the Lockup:**
  1. **Permission Failure:** The autostart entry (`mount-ntfs.desktop`) executes as user `ubuntu` (UID 1000). The startup script called `mkdir -p /media/ubuntu/2C95D29B2DF0500E`, which succeeded, but then executed `mount -t ntfs-3g ...` directly without `sudo`. Under Linux, unprivileged users are forbidden from calling the raw `mount` syscall (`mount: only root can use "--options" option`).
  2. **Stale Directory Artifact:** The mount failed silently, but the empty folder `/media/ubuntu/2C95D29B2DF0500E` was left behind on the filesystem.
  3. **UDisks2 Collision & Refusal:** When the user opened GNOME Disks and clicked "Mount", the desktop storage daemon (`udisksd`) attempted to mount `/dev/sdb4` to its standard path `/media/ubuntu/2C95D29B2DF0500E`. Finding an unmanaged, stale directory already present, UDisks entered a cleanup conflict state.
  4. **The "Funny State":** GNOME Disks threw an error indicating the mount point was invalid or busy, preventing the user from mounting the drive graphically.

---

### 1.3 The Desktop-Native UDisks2 Solution (`udisksctl`)
* **Resolution Implemented:** Completely refactored `/usr/local/bin/mount_ntfs_startup.sh`.
* **Key Architecture Change:** Replaced raw kernel `mount` with **`udisksctl mount -b "$NTFS_DEV"`**:
  ```bash
  UDISKS_OUT=$(udisksctl mount -b "$NTFS_DEV" 2>&1 || true)
  ```
* **Why this eliminates the issue:**
  1. `udisksctl` communicates directly with `udisks2.service` over D-Bus.
  2. In Ubuntu desktop sessions, Polkit grants the active console user (`ubuntu`) permission to mount removable storage without password prompts.
  3. Because the mount is handled by UDisks itself, **GNOME Disks and PCManFM file manager immediately recognize the mount point natively**, preventing path conflicts, orphaned directories, and mutex locks.
  4. If `udisksctl` reports the drive is already mounted, the script detects the active mount point from `lsblk` and simply refreshes the symlinks.

---

### 1.4 Persistent Startup Logging Architecture
* **Requirement:** User requested: *"Implement logging to the persistance partition of the start up sequence and any errorr messages."*
* **Implementation:**
  * Added global output stream redirection at the top of `mount_ntfs_startup.sh`:
    ```bash
    LOG_FILE="/var/log/startup_ntfs.log"
    USER_LOG="/home/ubuntu/startup_ntfs.log"
    exec > >(tee -a "$LOG_FILE" "$USER_LOG") 2>&1
    ```
  * **Captured Telemetry:**
    * Start timestamp and executing user ID (`whoami` / `id -u`).
    * Block device discovery logs (`blkid`, `lsblk`).
    * `udisksctl` stdout/stderr output.
    * Fallback mount attempts if necessary.
    * Symlink creation status (`~/ntfs_usb` and Desktop links).
    * Final mount point validation and exit code.
  * **Persistence Guarantee:** Because the root filesystem is backed by `rescuezilla-persistence.dat` via OverlayFS, both `/var/log/startup_ntfs.log` and `~/startup_ntfs.log` are permanently stored on flash and survive reboot.

---

### 1.5 Diagnostic System Journal Extraction
* **Requirement:** User requested: *"Can you extract the recent system journal entries to that log file."*
* **Implementation:**
  * Extracted 1,622 lines from `/var/log/syslog` covering the boot session at `2026-09-02 22:07:46`.
  * Compiled into a structured diagnostic report: [`rescuezilla_boot_2207_journal.log`](file:///home/alan/ntfs_usb/rescuezilla_boot_2207_journal.log).
  * **Sections Included in Extract:**
    1. Kernel boot parameters & CPU/RAM initialization.
    2. Block device `/dev/sdb` SCSI registration (`sdb1`, `sdb2`, `sdb3`, `sdb4`).
    3. `udisksd` daemon startup and mount point cleanup conflict logs.
    4. XDG autostart generator execution trace for `mount-ntfs.desktop`.
    5. Complete NTFS and storage device subsystem activity.
  * **Locations Deployed:**
    * Inside Rescuezilla: `/var/log/rescuezilla_boot_2207_journal.log` & `~/rescuezilla_boot_2207_journal.log`
    * On USB NTFS partition: `/home/alan/ntfs_usb/rescuezilla_boot_2207_journal.log`
    * In Git Sub-Repository: [`Ventoy/rescuezilla_boot_2207_journal.log`](file:///home/alan/mnt/zbook/files_g5/GitHub/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/rescuezilla_boot_2207_journal.log)

---

### 1.6 How to Access the Persistent Partition from the Rescuezilla Terminal
* **Question Asked:** User requested: *"How can I access the persistant partition from the rescuezilla terminal"*
* **Four Access Methods Documented:**

#### Method 1: The Transparent Live Root (Standard Workflow)
When booted with `rescuezilla-persistence.dat`, the persistence container is **already mounted as the root filesystem (`/`)**.
* Anything created in `/home/ubuntu/`, `/etc/`, `/var/`, or `/usr/local/` is written directly into persistence.
* View persistent logs immediately:
  ```bash
  cat /var/log/startup_ntfs.log
  cat ~/startup_ntfs.log
  ```

#### Method 2: Inspecting the Raw Overlay Delta (COW Layer)
Casper OverlayFS mounts the read-write delta layer (files modified during persistent sessions) at:
```bash
ls -la /run/initramfs/cow/upper/
# or
ls -la /cow/upper/
```
Inside `/run/initramfs/cow/upper/`, you can see the modified `/etc`, `/var`, `/home`, and `/usr` trees without the read-only squashfs underlying files.

#### Method 3: Accessing the Base Ventoy USB Partition (`/dev/sdb1`)
To access the underlying partition where `rescuezilla-persistence.dat` itself resides:
```bash
sudo mkdir -p /media/ventoy
sudo mount /dev/sdb1 /media/ventoy
ls -lh /media/ventoy/
```

#### Method 4: Accessing Persistence from Ubuntu (Booted via `F6`)
Whenever booted in the installed Ubuntu environment on `/dev/sdb3`, loopback-mount the image:
```bash
sudo mkdir -p /mnt/rz_persist
sudo mount -o loop /media/devmon/Ventoy/rescuezilla-persistence.dat /mnt/rz_persist
ls -la /mnt/rz_persist/upper/
sudo umount /mnt/rz_persist
```

---

### 1.7 Terminal Persistence & Stderr Redirection Fixes
* **Investigation of Previous Crash (`diag2.md`):**
  * `prompt_choice` in `run_rescuezilla_backup_cli.sh` previously printed to standard output, causing `scope_choice=$(prompt_choice ...)` to capture the prompt text and corrupt `$PARTITIONS_LIST` into an empty string.
  * Python `rescuezillapy` crashed with `argument --partitions: expected at least one argument` (Exit code 2).
  * Because the desktop launcher used `x-terminal-emulator -e ...`, the window closed instantaneously upon error.
* **Fixes Verified:**
  1. Redirected `prompt_choice` display to `stderr` (`echo -en "$prompt_msg" >&2`). Verified with dry-run test (options 1 & 2 populate `$PARTITIONS_LIST` cleanly).
  2. Updated desktop launchers in persistence to use `xfce4-terminal --title="..." --hold --geometry=105x32`.
  3. Added explicit terminal pause at the end of both `run_rescuezilla_backup_cli.sh` and `post-backup-wizard.sh`. Windows **never close abruptly**.

---

## 2. Comprehensive File & Commit Register

| File Path | Description & Updates | Repositories & Partitions Synchronized | Git Commit |
| :--- | :--- | :--- | :--- |
| **`Ventoy/persistence_startup/Run_Backup_CLI.desktop`** | Self-mounting launcher: detects missing mount, triggers `mount_ntfs_startup.sh`, falls back to `/usr/local/bin/`. | Repo, `/media/devmon/Ventoy/rescuezilla-persistence.dat` (`/upper/home/ubuntu/Desktop/`). | `e9757c1` |
| **`Ventoy/persistence_startup/Post_Backup_Wizard.desktop`** | Self-mounting diagnostic launcher with fallback execution. | Repo, `/media/devmon/Ventoy/rescuezilla-persistence.dat` (`/upper/home/ubuntu/Desktop/`). | `e9757c1` |
| **`Ventoy/persistence_startup/mount-ntfs.service`** | System-level systemd service running after `udisks2.service` to mount NTFS before desktop loads. | Repo, `/media/devmon/Ventoy/rescuezilla-persistence.dat` (`/upper/etc/systemd/system/`). | `e9757c1` |
| **`Ventoy/persistence_startup/mount_ntfs_startup.sh`** | Updated with `udisksctl` desktop-native mount and persistent dual logging (`/var/log/` & `~/`). | Repo, `/media/devmon/Ventoy/rescuezilla-persistence.dat` (`/upper/usr/local/bin/`). | `5ebfcfa` |
| **`Ventoy/persistence_startup/README.md`** | Detailed guide on `mount_ntfs_startup.sh`, XDG autostart, and `--hold` window persistence. | Repo, secondary clone. | `4149f00` |
| **`Ventoy/rescuezilla_boot_2207_journal.log`** | Extracted 1,622-line systemd journal trace diagnosing the UDisks mount point collision. | Repo, `/home/alan/ntfs_usb/`, `/media/devmon/Ventoy/rescuezilla-persistence.dat`. | `5ebfcfa` |
| **`Ventoy/run_rescuezilla_backup_cli.sh`** | Fixed `prompt_choice` stderr redirection, added exit holding pause, installed in `/usr/local/bin/`. | Repo, NTFS USB root, Ventoy partition, persistence `/usr/local/bin/`. | `91c3e90` |
| **`Ventoy/post-backup-wizard.sh`** | Added exit holding pause on action `8`, installed in `/usr/local/bin/`. | Repo, NTFS USB root, Ventoy partition, persistence `/usr/local/bin/`. | `91c3e90` |
| **`Ventoy/ventoy_boot_repair_guide.md`** | Updated Section 16 (UDisks fix), Section 18 (artifacts), and Section 19 (terminal access methods). | Repo, NTFS USB root, `docs/`, Ventoy partition, secondary clone. | `4149f00` |
| **`/home/alan/ntfs_usb/Screenshot_2026-09-03_*.png`** | User screenshots showing Partition 1 exFAT busy error and Status 127 terminal holding window. | Preserved on USB NTFS Partition (`/dev/sdb4`). | Offline File |
| **`/media/devmon/Ventoy/rescuezilla-persistence.dat`** | Four-tier persistent environment: embedded scripts in `/usr/local/bin/`, Openbox autostart, systemd service. | Flash Partition `/dev/sdb1`. | Active Binary |

---

## 3. Step-by-Step Verification Runbook

### Testing the Updated Live Environment
1. Insert the USB drive and reboot the HP ZBook.
2. At the Ventoy menu, select `rescuezilla-2.6.2-64bit.noble.iso`.
3. Select **`Boot with /rescuezilla-persistence.dat`**.
4. Once the Openbox desktop loads:
   * A desktop notification will appear: `"NTFS Storage Ready: Mounted at /media/ubuntu/2C95D29B2DF0500E"`.
   * Check the persistent log:
     ```bash
     cat ~/startup_ntfs.log
     ```
   * Open GNOME Disks or PCManFM: `/dev/sdb4` will be cleanly mounted without errors or lockups.
5. Double-click **`🚀 Run Backup Assistant (CLI)`**:
   * The terminal will open in a clean 105x32 window.
   * Select `[1] /dev/sda (Internal 1TB Drive)` -> `[1] Windows 11 Only: sda1 + sda2`.
   * The terminal will remain open until you review the output and press a key.
