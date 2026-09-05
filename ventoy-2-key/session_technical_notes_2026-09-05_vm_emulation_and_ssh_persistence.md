# Technical Session Notes: QEMU Emulation Lab, OpenSSH Persistence Packaging, and Storage Self-Healing

**Date:** 2026-09-05  
**Author:** Alan (`alan@prudom.me`)  
**Repository:** `devices/setup-usb-boot-keys/ventoy-2-key`  
**Latest Commits:** `03a54e4` -> `b944731` -> `ef55748` -> `176fa05` -> `97ad5b3` -> `9b18dc1` -> `08ece54`  

---

## 1. Executive Summary

This session resolved multiple critical operational and virtualization hurdles in the Rescuezilla 2.6.1 Live + Persistence environment on the Ventoy 2 USB drive (`/dev/sdb`), culminating in an automated, highly reliable test harness:
1. **Resolved QEMU Shutdown Hang:** Diagnosed why the VM appeared hung after shutting down Rescuezilla from the desktop. The root cause was identified via serial console telemetry as Ubuntu Casper's interactive media eject prompt waiting on `/dev/console` (`Please remove the installation medium, then press ENTER:`). Solved by injecting `noprompt` into the kernel boot parameters.
2. **Packaged OpenSSH Server into Persistence:** Discovered through root filesystem squashfs analysis that Rescuezilla 2.6.1 intentionally omits `openssh-server` (only `openssh-client` is pre-installed). Extracted exact Ubuntu 24.10 Oracular `openssh-server 9.7p1-7ubuntu4.3` binaries, created the missing `sshd` privilege separation user/group, set default credentials (`ubuntu:live`), and deployed `authorized_keys`. Verified live SSH command execution on port 2222.
3. **Implemented Self-Healing Storage Remount Trap:** Solved the disappearing `/media/ubuntu/SHARED_FAT` partition bug caused by Clonezilla's `ocs-sr` pre-flight unmount hooks. Added signal traps (`EXIT`, `INT`, `TERM`) and post-operation remount checks in `rescue_suite_launcher.sh`.
4. **Integrated Diagnostic Log Export into Suite Main Menu:** Added option `[9] 📦 Export Diagnostic Bundle` directly to `rescue_suite_launcher.sh`, allowing users to bundle serial console logs, guest system logs, host kernel telemetry, and desktop validation reports to the 82 GB SHARED FAT partition with a single keystroke.
5. **Silenced Legacy Floppy Drive Errors:** Identified harmless but alarming red `I/O error, dev fd0` boot messages caused by QEMU's default `i440fx` floppy controller. Correctly configured `-global isa-fdc.fdtypeA=none` and `-global isa-fdc.fdtypeB=none` in `run_test_vm.sh`.
6. **HITL Review & Version Control:** Conducted interactive review of all conversational screenshot artifacts, saving accepted artifacts with human-friendly names into `docs/screenshots/` and committing them to git.

---

## 2. Detailed Technical Forensics & Root Causes

### A. QEMU Shutdown Hang
* **Symptom:** After selecting "Shutdown" in Rescuezilla's GUI, the graphical screen went black, but the QEMU window and process remained running indefinitely.
* **Forensic Evidence (`/tmp/vm_serial_console.log`):**
  ```text
  [  OK  ] Reached target shutdown.target - System Shutdown.
           Starting casper.service - Shuts down the "live" preinstalled system cleanly...
  Please remove the installation medium, then press ENTER: 
           Unmounting cdrom.mount - /cdrom...
  [FAILED] Failed unmounting cdrom.mount - /cdrom.
  cdrom.mount
  ```
* **Mechanism:** The `casper-stop` shutdown hook in Ubuntu Live tries to eject the CD tray and blocks execution on `tty1` waiting for a physical keyboard press of `<ENTER>`. Because the X11 display was already detached, the prompt sat hidden in the virtual console.
* **Remediation:** Appended `noprompt` to the kernel arguments in Option B boot mode within `run_test_vm.sh`:
  ```bash
  -append "boot=casper persistent noprompt console=ttyS0 console=tty1 quiet splash ---"
  ```
* **Validation:** Verified via SSH `sudo poweroff` that the VM shuts down cleanly and terminates QEMU with exit code 0 in under 3 seconds.

---

### B. Missing OpenSSH Server in Rescuezilla 2.6.1
* **Symptom:** Network connectivity was established (`ens3` received IP `10.0.2.15` via DHCP), port 2222 on host accepted TCP connections, but SSH handshakes failed immediately with `Connection reset by peer` or `Connection timed out during banner exchange`.
* **Forensic Evidence:**
  1. Mounted `rescuezilla-2.6.1-64bit.oracular.iso` -> `casper/filesystem.squashfs` and inspected packages:
     ```text
     dpkg -l --root=/mnt/squash_inspect | grep -i openssh
     -> ii  openssh-client  1:9.7p1-7ubuntu4.3
     -> openssh-server is NOT installed! /usr/sbin/sshd does not exist.
     ```
  2. Inspecting guest `startup_storage.log` in persistence showed:
     - When using Ubuntu 22.04 (Jammy) host sshd: `OpenSSL version mismatch. Built against 30000020, you have 30300010` (glibc/OpenSSL incompatible).
     - When using Ubuntu 24.10 (Oracular) sshd: `Privilege separation user sshd does not exist`.
* **Remediation in `deploy_four_tier_persistence.sh`:**
  1. Extracted exact `openssh-server_9.7p1-7ubuntu4.3_amd64.deb` and `openssh-sftp-server` binaries.
  2. Embedded `/usr/sbin/sshd`, `/usr/lib/openssh/sftp-server`, and PAM configuration into the persistence image.
  3. Added logic to populate `sshd:x:107:65534:sshd privsep:/run/sshd:/usr/sbin/nologin` in `/etc/passwd` and `/etc/group`.
  4. Configured `/etc/ssh/sshd_config` with `PermitRootLogin yes` and `PasswordAuthentication yes`.
  5. Injected host identity key into `/home/ubuntu/.ssh/authorized_keys` and set passwords for `ubuntu` and `root` to `live` (`chpasswd`).
* **Validation:** Successfully executed remote commands and automated test scripts over SSH:
  ```bash
  $ sshpass -p live ssh -p 2222 ubuntu@127.0.0.1 "uptime && uname -a && whoami"
  14:48:43 up 0 min, 3 users, load average: 0.89, 0.33, 0.12
  Linux ubuntu 6.11.0-29-generic #29-Ubuntu SMP PREEMPT_DYNAMIC x86_64 GNU/Linux
  ubuntu
  ```

---

### C. Self-Healing Storage Remounts
* **Symptom:** When a Partclone/Clonezilla backup aborted or failed, `/media/ubuntu/SHARED_FAT` was missing, breaking desktop shortcuts and log exports.
* **Mechanism:** Clonezilla's `ocs-sr` unmounts any partition located on the drive being imaged (e.g., `/dev/sdb4` when imaging `/dev/sdb`) prior to running partclone, but does not remount them if the operation fails or is canceled.
* **Remediation in `rescue_suite_launcher.sh`:**
  ```bash
  remount_local_storage() {
      echo -e "\n${DIM}[*] Checking and restoring local storage mount states...${RESET}"
      if [ -x /usr/local/bin/mount_storage_startup.sh ]; then
          sudo /usr/local/bin/mount_storage_startup.sh >/dev/null 2>&1 || true
      elif [ -x "${SCRIPT_DIR}/mount_fat_and_hdd.sh" ]; then
          sudo "${SCRIPT_DIR}/mount_fat_and_hdd.sh" >/dev/null 2>&1 || true
      fi
  }
  trap remount_local_storage EXIT INT TERM
  ```
  Additionally called `remount_local_storage` unconditionally at the end of each menu loop cycle.

---

### D. Floppy Controller (fd0) Error Suppression
* **Symptom:** Serial console logged bright red I/O error lines on initial boot:
  ```text
  I/O error, dev fd0, sector 0 op 0x0:(READ) flags 0x0 phys_seg 1 prio class 0
  /init: line 38: can't open /dev/fd0: No such device or address
  ```
* **Mechanism:** QEMU defaults to an ISA floppy disk controller (`isa-fdc`). During initramfs device discovery, Casper queries `/dev/fd0`. Since no virtual floppy image is mounted, the kernel driver throws I/O errors.
* **Remediation in `run_test_vm.sh`:**
  Configured QEMU device options to disable floppy drive emulation entirely:
  ```bash
  -global "isa-fdc.fdtypeA=none"
  -global "isa-fdc.fdtypeB=none"
  ```
* **Validation:** Verified via `/tmp/vm_serial_console.log` that the boot sequence now proceeds with zero `fd0` errors.

---

## 3. Comprehensive File Changes Summary

### 1. `run_test_vm.sh`
* Appended `console=ttyS0 console=tty1` to route live kernel and systemd messages into `/tmp/vm_serial_console.log`.
* Appended `noprompt` to prevent Casper from pausing on CD removal at shutdown.
* Added `-global "isa-fdc.fdtypeA=none"` and `-global "isa-fdc.fdtypeB=none"` to disable legacy floppy disk probing.

### 2. `rescue_suite_launcher.sh`
* Added `remount_local_storage()` function and wired it to `trap remount_local_storage EXIT INT TERM`.
* Added post-operation invocation of `remount_local_storage` after each menu action.
* Expanded menu options to include:
  - `[9] 📦 Export Diagnostic Bundle` (triggers `export_vm_and_system_logs_to_fat.sh`)
  - `[10] 🖥️ Launch Rescuezilla GUI` (native GUI window)
* Adjusted selection validator `prompt_choice` range to `[0-10]`.

### 3. `deploy_four_tier_persistence.sh`
* Added extraction and installation of `openssh-server 9.7p1-7ubuntu4.3` binaries (`/usr/sbin/sshd`, `/usr/lib/openssh/sftp-server`).
* Configured `/etc/ssh/sshd_config` (`PermitRootLogin yes`, `PasswordAuthentication yes`).
* Injected `sshd` privsep user and group into container `/etc/passwd` and `/etc/group`.
* Added password assignment (`ubuntu:live`, `root:live`) and `authorized_keys` provisioning.
* Included `export_vm_and_system_logs_to_fat.sh` in the Tier 1 embedded root scripts loop.

### 4. `stimulate_vm_tests.sh`
* Integrated `sshpass` support with fallback password `'live'` for fully autonomous headless verification.
* Updated test execution commands to run via `${SSH_CMD}` wrapper.

### 5. `persistence_startup/Run_Backup_CLI.desktop`
* Updated `Icon=` attribute to `org.xfce.terminal` for maximum compatibility with PCManFM and the default theme.

### 6. `docs/screenshots/`
* `vm_rescue_suite_main_menu.png`: Accepted HITL artifact showing the unified suite menu in VM.
* `vm_backup_assistant_target_selection.png`: Accepted HITL artifact showing network mount verification and target drive selection.

---

## 4. Git Commit History (Recent Series)

```text
08ece54 docs(artifacts): add screenshot of backup assistant remote mount and target selection in VM
9b18dc1 docs(artifacts): add screenshot of unified rescue suite main menu in VM
97ad5b3 fix(qemu): use isa-fdc.fdtypeA=none and fdtypeB=none to disable floppy drive probing
176fa05 fix(qemu): suppress legacy floppy driveA probing to silence fd0 errors
ef55748 fix(ssh-auth): configure sshd privsep user, set ubuntu live password, and deploy authorized_keys
b944731 fix(vm-and-suite): package openssh-server into persistence, add noprompt to qemu, and add diagnostic bundle export to main menu
03a54e4 fix(persistence): add self-healing storage remount trap, harden sshd activation, and enable ttyS0 serial console
6ac5c21 fix(ventoy-2): simplify desktop Exec lines, add VM serial logging and log export tool for SHARED FAT
```
