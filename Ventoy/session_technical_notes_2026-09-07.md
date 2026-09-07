# Comprehensive Technical Notes: Dual Master Hubs, QEMU Emulation, Dynamic Validation, and Status 126 Remediation

**Session Lead / Authors**: Alan P & Assistant  
**Date of Record**: September 7, 2026  
**Primary Repositories**: `/home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys` (Commit: `55c61bc`), synchronized with `~/Documents/setup-usb` and USB partitions (`/dev/sdb1`, `/dev/sdb4`)  
**Target Environments**: Ubuntu Development Host (`alan-USB-g5`), QEMU KVM Emulation Lab, and Rescuezilla 2.6.2 Live Environment  

---

## 1. Executive Summary & Session Overview

During this session, we resolved critical operational blockers observed during live QEMU VM boot and host-level test orchestration:
1. **Dynamic Block Device & Partition Validation**: Eliminated hardcoded assumptions about `/dev/sda` and `/dev/sdb`, dynamically querying real disks via `lsblk` and validating partition tokens prior to execution.
2. **Dual Master Menus & Prompt Stream Separation**: Separated host-level automation ([`host_support_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/host_support_hub.sh)) from guest rescue operations ([`live_rescue_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/live_rescue_hub.sh)), redirecting interactive prompts to `stderr` (`>&2`) to avoid swallowing user choices.
3. **QEMU X11 Display Authorization**: Resolved `gtk initialization failed` when running under `sudo` by automatically adding root to the host user's X11 access control list (`xhost +si:localuser:root`).
4. **Symlink Canonicalization**: Fixed `SCRIPT_DIR` resolution in `host_support_hub.sh` so symlinks located in `/home/alan/` accurately resolve to the underlying repository directory.
5. **TigerVNC Auto-Fit & Dynamic Scaling**: Enabled `-RemoteResize=1` in TigerVNC viewer and documented the `F8` interactive menu to eliminate desktop scrollbars.
6. **Remediation of Error 126 (`cannot execute binary file`)**: Diagnosed stale/corrupted `/scripts/` binaries inside the live guest overlay, authored a self-healing synchronizer (`sync_and_launch.sh`), added multi-path candidate fallbacks with header verification, and enforced kernel `sync` before snapshot creation.
7. **Automated Regression Suite Expansion**: Authored [`test_corrupt_binary_regression.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_corrupt_binary_regression.exp), bringing the master test suite to 8 out of 8 passing tests (100% success rate, 37.5% cumulative branch coverage).
8. **Artifact Versioning**: Committed [`automated_coverage_plan.md`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/docs/automated_coverage_plan.md) to Git under `Ventoy/docs/`.

---

## 2. Detailed Breakdown of Issues, Forensic Findings & Fixes

### 2.1 Issue 1: Clonezilla Error `The input device [sda1] does NOT exist in this machine!`
* **Symptom**: In user screenshots (`09:42:20` and `09:46:18`), Clonezilla aborted with:
  ```text
  The input device [sda1] does NOT exist in this machine!
  We will not save this device [sda1]!
  ```
* **Root Cause**: 
  - When QEMU ran in isolated sandbox mode (Option A or Option B), the guest virtual machine saw only virtual drives (`/dev/vda`), without `/dev/sda`.
  - The runner script had previously hardcoded `/dev/sda` and assumed `sda1` existed.
* **Remediation**:
  - Implemented dynamic drive discovery in [`run_rescuezilla_backup_cli.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_rescuezilla_backup_cli.sh):
    ```bash
    DISCOVERED_DRIVES=()
    while IFS= read -r dname; do
        if [ -n "$dname" ] && [ -b "/dev/${dname}" ]; then
            DISCOVERED_DRIVES+=("/dev/${dname}")
        fi
    done < <(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1 !~ /^(nbd|loop|ram|zram)/{print $1}')
    ```
  - Added strict partition pre-flight validation: any user-entered partition name (e.g. `sda999`) is checked against `AVAILABLE_PARTS` before `ocs-sr` or `partclone` is called.
  - Authored [`test_dynamic_drive_and_partition_validation.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_dynamic_drive_and_partition_validation.exp) to guarantee rejection of non-existent partitions.

---

### 2.2 Issue 2: Prompt Swallowing in Dual Hub Menus
* **Symptom**: `host_support_hub.sh` failed to execute choices; pressing a number immediately re-prompted without running the corresponding script.
* **Root Cause**:
  `choice=$(prompt_choice "..." min max)` captured the entire output of the function. Because `prompt_choice` printed prompt text via `echo -en "${prompt_msg}"` to standard output (`stdout`), `choice` absorbed the prompt string itself rather than just the numeric integer.
* **Remediation**:
  Updated `prompt_choice()` in both [`host_support_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/host_support_hub.sh) and [`live_rescue_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/live_rescue_hub.sh) to send prompt messages and validation warnings to standard error (`>&2`), ensuring `stdout` contains strictly the validated numeric choice.

---

### 2.3 Issue 3: Host Hub Symlink Execution Failure
* **Symptom**: Running `/home/alan/host_support_hub.sh` failed with:
  ```text
  bash: /home/alan/run_test_vm.sh: No such file or directory
  ```
* **Root Cause**:
  `/home/alan/host_support_hub.sh` is a symbolic link pointing to `/home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/host_support_hub.sh`. Standard `dirname "${BASH_SOURCE[0]}"` evaluated to `/home/alan/` rather than the canonical repository path.
* **Remediation**:
  Implemented recursive symlink canonicalization at the header of both hubs:
  ```bash
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SCRIPT_SOURCE" ]; do
      SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
      SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
      [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
  done
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  ```

---

### 2.4 Issue 4: QEMU GTK Launch Crash (`gtk initialization failed`)
* **Symptom**: Launching QEMU Option A via `sudo` exited immediately with:
  ```text
  Authorization required, but no authorization protocol specified
  gtk initialization failed
  ```
  Consequently, SSH connection attempts to `localhost:2222` produced `kex_exchange_identification: Connection closed`.
* **Root Cause**:
  Under `sudo`, root does not inherit the desktop user's X11/Wayland authorization cookies.
* **Remediation**:
  Updated [`run_test_vm.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_test_vm.sh) to automatically authorize root on the host display:
  ```bash
  export DISPLAY="${DISPLAY:-:0}"
  if [ -n "$SUDO_USER" ]; then
      sudo -u "$SUDO_USER" DISPLAY="$DISPLAY" xhost +si:localuser:root >/dev/null 2>&1 || true
  fi
  ```
  Added stderr trapping to dump `/tmp/qemu_rescuezilla_vm.log` immediately if QEMU ever fails.

---

### 2.5 Issue 5: TigerVNC Scaling & "Zoom to Fit"
* **Symptom**: User screenshot `12-35-21.png` showed scrollbars in TigerVNC, cutting off the Ventoy menu.
* **Remediation & Usage Guide**:
  1. Updated [`run_test_vm.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_test_vm.sh) to pass `-RemoteResize=1` to `vncviewer`.
  2. Documented interactive controls: Pressing **`F8`** in the TigerVNC window opens the menu to toggle **Full Screen** or set **Scale to window size** in Options -> Display.

---

### 2.6 Issue 6: Child Process Exited with Status 126 (`cannot execute binary file`)
* **Symptom**: User screenshots `12-06-33.png`, `12-18-53.png`, and `12-37-30.png` showed:
  ```text
  The child process exited normally with status 126.
  ...
  /scripts/run_rescuezilla_backup_cli.sh: /scripts/run_rescuezilla_backup_cli.sh: cannot execute binary file
  ```
* **Forensic Root Cause Analysis**:
  1. In the live Rescuezilla persistence environment, `/scripts/run_rescuezilla_backup_cli.sh` had been corrupted or written with non-executable bytes in an earlier persistence snapshot.
  2. When [`rescue_suite_launcher.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/rescue_suite_launcher.sh) ran Option 1, it attempted to invoke that corrupt file directly.
  3. In Option A (CoW snapshot), the snapshot was created before host disk buffers had been flushed to flash, meaning recent script fixes on `/dev/sdb` were not present in the VM snapshot.
* **Comprehensive Remediation**:
  1. **Mandatory Buffer Flush**: Added `sync` to [`run_test_vm.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_test_vm.sh) right before `qemu-img create`.
  2. **Multi-Path Candidate Discovery**: Updated Option 1 in `rescue_suite_launcher.sh` to check Partition 4 (`/media/ubuntu/ntfs_usb`, `/home/ubuntu/ntfs_usb`), `/media/devmon/Ventoy`, and `/media/devmon/sdb4*`.
  3. **Header Validation**: Added `[ -r "$cand" ] && head -n 1 "$cand" | grep -q "bash"` to guarantee that corrupt or non-bash files are never executed.
  4. **Self-Healing Wrapper (`sync_and_launch.sh`)**: Created [`persistence_startup/sync_and_launch.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/persistence_startup/sync_and_launch.sh) and updated desktop launchers (`Rescue_Suite.desktop` and `Live_Rescue_Hub.desktop`) to automatically sync fresh scripts from Partition 4 into `/scripts/` before launching.

---

## 3. Rationale for Every User Prompt (`ℹ️ Why we ask this:`)

Per instructions, the rationale for every user-facing prompt across all scripts is documented and enforced:

| Prompt | Location | On-Screen Explanation (`ℹ️ Why we ask this:`) |
| :--- | :--- | :--- |
| **Select drive to backup [1-N]:** | `run_rescuezilla_backup_cli.sh` | Dynamically scans all physical and virtual disks attached to this machine to prevent cloning or saving the wrong drive. |
| **Select partition scope [1-3]:** | `run_rescuezilla_backup_cli.sh` | Backing up an entire drive takes longer, whereas backing up specific partitions saves storage and speeds up recovery. |
| **Enter partition names:** | `run_rescuezilla_backup_cli.sh` | Requires entering valid partitions; every token is validated against `lsblk` before proceeding to avoid syntax or non-existent device errors. |
| **Backup Image Naming:** | `run_rescuezilla_backup_cli.sh` | Image names must be unique to avoid overwriting previous snapshots, and spaces are sanitized to underscores for network filesystem compatibility. |
| **Imaging Engine Selection [1-2]:** | `run_rescuezilla_backup_cli.sh` | Clonezilla's native CLI (`ocs-sr`) is the battle-tested standard with 15+ years of stability in terminal mode. Rescuezilla's CLI is labeled experimental. |
| **Hardware Rescue Mode [1-2]:** | `run_rescuezilla_backup_cli.sh` | On failing SSDs/HDDs, standard mode aborts on bad sectors; Rescue Mode (`--rescue`) bypasses bad sectors, zeroes unreadable blocks, and finishes imaging. |
| **Start backup operation now? (y/n):** | `run_rescuezilla_backup_cli.sh` | Starting the backup initiates intensive disk reads and multi-gigabyte network writes. Verifying options now prevents imaging with incorrect parameters. |
| **Execution Mode [1-2]:** | `live_rescue_hub.sh` | Standard mode executes normally. Instrumented mode records full terminal I/O and tracks line/branch coverage into Partition 4. |

---

## 4. Automated Regression Test Suite Status

The test suite was expanded with [`test_corrupt_binary_regression.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_corrupt_binary_regression.exp):
- Injects a mock corrupt binary (`\x7fELF...`) at the primary script candidate path.
- Executes `rescue_suite_launcher.sh` Option 1.
- Traps and fails immediately if `cannot execute binary file` or `status 126` occurs.
- Asserts clean fallback to an authoritative runner or the safe Clonezilla wizard.

### Master Cumulative Test Run Results:
```text
======================================================================
    🧪 MASTER CUMULATIVE TEST & BRANCH COVERAGE SUITE (uv + expect)   
======================================================================
[*] Running: test_backup_cli_all_and_custom.exp...              ✓ passed
[*] Running: test_backup_cli_prompts.exp...                     ✓ passed
[*] Running: test_backup_cli_sdb.exp...                         ✓ passed
[*] Running: test_corrupt_binary_regression.exp...              ✓ passed
[*] Running: test_dynamic_drive_and_partition_validation.exp... ✓ passed
[*] Running: test_hardware_detect_lib.exp...                    ✓ passed
[*] Running: test_post_backup_wizard.exp...                     ✓ passed
[*] Running: test_rescue_suite_launcher.exp...                  ✓ passed

Overall Coverage Rate:
  lines......: 37.6% (366 of 973 lines)
  branches...: 37.5% (94 of 251 branches)
  • Browsable HTML: /tmp/cumulative_regression_test/html/index.html
```

---

## 5. Summary of Modified & Added Files

| File Path | Nature of Modification |
| :--- | :--- |
| [`Ventoy/host_support_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/host_support_hub.sh) | Separated prompt output to `stderr`; added recursive symlink canonicalization; routed Option 2 to `run_test_vm.sh --boot 2`. |
| [`Ventoy/live_rescue_hub.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/live_rescue_hub.sh) | Separated prompt output to `stderr`; added recursive symlink canonicalization; improved coverage management options. |
| [`Ventoy/run_rescuezilla_backup_cli.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_rescuezilla_backup_cli.sh) | Added dynamic block device discovery (`lsblk`) excluding `nbd`/`loop`/`ram`; added strict partition token pre-validation. |
| [`Ventoy/rescue_suite_launcher.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/rescue_suite_launcher.sh) | Added multi-path discovery for `run_rescuezilla_backup_cli.sh`; added `head -n 1` bash header assertion to prevent status 126 crashes. |
| [`Ventoy/run_test_vm.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/run_test_vm.sh) | Added `xhost` root display authorization; added `sync` before CoW snapshot; configured TigerVNC with `-RemoteResize=1`. |
| [`Ventoy/deploy_four_tier_persistence.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/deploy_four_tier_persistence.sh) | Deploys `sync_and_launch.sh` to `/usr/local/bin`; configured `terminalrc` font size and zoom shortcuts; removed slow recursive finds. |
| [`Ventoy/persistence_startup/sync_and_launch.sh`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/persistence_startup/sync_and_launch.sh) | **NEW**: Self-healing wrapper syncing fresh scripts from Partition 4 into `/scripts/` before launching live tools. |
| [`Ventoy/persistence_startup/Rescue_Suite.desktop`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/persistence_startup/Rescue_Suite.desktop) | Updated `Exec` to run via `sync_and_launch.sh`. |
| [`Ventoy/persistence_startup/Live_Rescue_Hub.desktop`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/persistence_startup/Live_Rescue_Hub.desktop) | Updated `Exec` to run via `sync_and_launch.sh`. |
| [`Ventoy/tests/cases/test_corrupt_binary_regression.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_corrupt_binary_regression.exp) | **NEW**: Automated regression test asserting status 126 prevention and corrupt binary rejection. |
| [`Ventoy/tests/cases/test_dynamic_drive_and_partition_validation.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_dynamic_drive_and_partition_validation.exp) | **NEW**: Expect test exercising dynamic drive discovery and partition list validation. |
| [`Ventoy/tests/cases/test_backup_cli_sdb.exp`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/tests/cases/test_backup_cli_sdb.exp) | Updated regex match to align with dynamic partition scope menu. |
| [`Ventoy/docs/automated_coverage_plan.md`](file:///home/alan/ap-devices-and-pcs/devices/setup-usb-boot-keys/Ventoy/docs/automated_coverage_plan.md) | **NEW**: Version-controlled architectural specification for the automated testing loop. |
