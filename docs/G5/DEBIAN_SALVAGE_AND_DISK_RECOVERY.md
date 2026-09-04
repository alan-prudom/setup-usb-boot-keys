# Debian WSL1 Salvage & Storage Recovery Documentation

**Date:** 2026-09-03 – 2026-09-04  
**Host System:** HP ZBook 15u G5 (AP-HP-G5)  
**Location:** `devices/setup-usb-boot-keys/docs/G5/DEBIAN_SALVAGE_AND_DISK_RECOVERY.md`

---

## 1. Executive Summary

This report documents the storage diagnostic on Drive `C:`, the investigation and data mining of the legacy `D:\Debian` environment (~17.08 GB), the extraction and publication of personal software projects to GitHub, and the creation and verification of a full-system maximum-compression archive on external drive `F:`.

```
+-----------------------------------------------------------------------------------+
| 1. C: Drive Fullness Diagnostic                                                   |
|    - Verified physical vs junction storage                                        |
|    - Isolated Evernote resource cache consuming ~16.2 GB                          |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 2. D:\Debian Investigation (Legacy WSL1 Debian 9 Stretch ~17.08 GB)               |
|    - Verified unmounted status & inspected rootfs/home/alan                       |
|    - Mined pyZK, Zettelkasten, excelreader, utility scripts, notebooks, bash log  |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 3. GitHub Repository Creation: 'legacy-debian-salvage'                            |
|    - Local path: D:\Github\legacy-debian-salvage                                  |
|    - Resolved nested git repository collision (pyZK/test/.git -> _git_backup)     |
|    - Committed 371 files and published to private remote repo                     |
+-----------------------------------------------------------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
| 4. Maximum-Compression Full Archive to F: Drive                                   |
|    - Streamed D:\Debian directly via WSL Ubuntu tar -czf (GZIP -9) to F:          |
|    - Zero uncompressed intermediate files written to C:                           |
|    - Result: F:\Debian_backup.tar.gz (5.61 GB)                                    |
|    - Verified 100% OK via full gzip byte-by-byte CRC check (gzip -tv)             |
+-----------------------------------------------------------------------------------+
```

---

## 2. C: Drive Space Diagnostic & Junction Rules

### 2.1 Critical Disk Rule: Junction Awareness
When scanning or auditing disk space on Windows (especially `C:`), directory junctions and NTFS reparse points must be checked and excluded before recursing. Otherwise, physical files residing on `D:` or other drives are erroneously counted as `C:` usage.

Key junction mappings verified on this system:
* `C:\Sync` -> `D:\sync`
* `C:\Users\alanp\.vscode` -> `D:\.vscode`
* `C:\Users\alanp\AppData\Local\Docker` -> `D:\Docker_AppData`
* Active WSL2 Ubuntu distribution -> `D:\WSL-distros\Ubuntu-24.04\ext4.vhdx`

### 2.2 Culprit Identification
Inspection of actual physical space on `C:` revealed that `C:\Users\alanp\AppData\Roaming\Evernote` was consuming **~19.9 GB**, of which **~16.2 GB** (over 135,000 files) was located in:
`C:\Users\alanp\AppData\Roaming\Evernote\resource-cache`

This local cache accounted for the sudden space exhaustion on the system drive.

---

## 3. Identification and Mining of `D:\Debian`

### 3.1 Distribution Characteristics
* **Path:** `D:\Debian`
* **Size:** ~17.08 GB (59,556 folders, 421,515 files)
* **Type:** Legacy Windows Subsystem for Linux 1 (WSL1) installation using NTFS reparse points (`fsserver`).
* **OS Version:** Debian GNU/Linux 9.13 (Stretch) — End of Life.
* **WSL State:** Unregistered in `wsl -l -v` (orphaned directory tree).

### 3.2 Salvaged Software Source Code & Data
The user directory (`rootfs/home/alan`) was scanned for personal projects, scripts, and notebook code. The following assets were extracted:

| Component | Description | Technologies |
| :--- | :--- | :--- |
| **`pyZK/`** | Zettelkasten literate programming implementation using Fastai `nbdev` | Python, Jupyter Notebooks, `nbdev`, Fastai |
| **`Zettelkasten/`** | Timestamp generation and cross-platform portability scripts | Python (`zk-portability-layer.py`, `create-time-stamp.py`) |
| **`excelreader/`** | Formula 1 timetable and race calendar spreadsheet processors | Python (`excel.py`, `aputils.py`, `circuit.json`) |
| **`cleandirs/`** | Directory clean-up utility script | Python (`cleandirs.py`) |
| **`openfile/`** | Cross-platform / GUI file opener utilities | Python, wxPython (`wxOpenfile.py`, `openfile.py`) |
| **`whereami/`** | Runtime path and execution environment inspection tool | Python (`whereami.py`), Windows batch script |
| **`cursesdemo/`** | Terminal UI curses demonstration | Python curses |
| **`nosedemo/`** | Python automated testing demo suite | Python, `nose` |
| **`pyautogui/`** | Desktop GUI automation testing script | Python, PyAutoGUI |
| **Notebooks** | Standalone scratch notebooks | `Untitled.ipynb`, `Untitled1.ipynb` |
| **Shell History** | Legacy WSL1 command history log | `bash_history.txt` |

*Security check:* `rootfs/home/alan/.ssh` and `rootfs/root/.ssh` were verified prior to export — no active private keys were found.

---

## 4. GitHub Repository: `legacy-debian-salvage`

A dedicated repository was initialized to preserve these projects under modern version control:

1. **Local Directory:** `D:\Github\legacy-debian-salvage`
2. **Sub-repository Conflict Resolution:**
   * `pyZK/test` contained an existing `.git` directory from its original `nbdev` template repository.
   * To prevent Git nested submodule errors while preserving the full commit history, `pyZK/test/.git` was renamed to `pyZK/test/_git_backup`.
3. **Repository Configuration:**
   * Configured `.gitignore` (ignoring `.pyc`, `__pycache__/`, `.ipynb_checkpoints/`, `*.exe`).
   * Generated comprehensive `README.md` cataloging each project's files and purpose.
4. **Git Commit & Push:**
   * 371 files committed using a temporary file for the commit message per repository protocol.
   * Remote repository created and pushed via GitHub CLI:  
     **[https://github.com/alan-prudom/legacy-debian-salvage](https://github.com/alan-prudom/legacy-debian-salvage)** (Private)
   * Branch: `main` (clean working tree tracking `origin/main`).

---

## 5. Maximum-Compression Full System Backup to `F:`

To ensure zero risk of data loss before deleting the 17 GB folder, a full-system compressed archive was created on external drive `F:`.

### 5.1 Architecture & Space Safety
* **External Target:** `F:\Debian_backup.tar.gz` (`F:` had >233 GB free space).
* **Zero C: Temp Usage:** Rather than using Windows tools that write intermediate uncompressed tarballs to `C:\Users\alanp\AppData\Local\Temp`, compression was streamed directly using GNU `tar` and `gzip -9` via WSL Ubuntu:
  ```bash
  wsl -d Ubuntu-24.04 -u root -- bash -c "GZIP=-9 tar -czf /mnt/f/Debian_backup.tar.gz -C /mnt/d Debian"
  ```
  This read directly from `D:\Debian` and streamed compressed blocks straight to `F:`, keeping `C:` entirely untouched.

### 5.2 Archive Statistics
* **Start Time:** 2026-09-03 22:24 BST
* **Completion Time:** 2026-09-04 02:49 BST (~4 hours 25 minutes)
* **Uncompressed Input:** ~17.08 GB (421,515 files)
* **Final Compressed Size:** **5.61 GB** (6,018,585,795 bytes)
* **Compression Ratio:** **~3.04:1** (67.1% space reduction)

### 5.3 Full Verification
1. **TAR Structural Verification:** Verified archive headers and directory table of contents by streaming `tar -tzf /mnt/f/Debian_backup.tar.gz | head -n 15`.
2. **Byte-by-Byte Integrity Verification:** Executed full stream decompression and 32-bit CRC check:
   ```bash
   gzip -tv /mnt/f/Debian_backup.tar.gz
   ```
   **Result:** `OK` (Zero CRC errors, no bit rot, no stream truncation).

---

## 6. Current Status & Next Actions

1. [x] **C: Drive space diagnosed** (Evernote resource cache isolated).
2. [x] **Source code salvaged & published** to GitHub (`alan-prudom/legacy-debian-salvage`).
3. [x] **Full 17 GB distribution archived** to `F:\Debian_backup.tar.gz` (5.61 GB).
4. [x] **Archive integrity verified** (100% passed CRC check).
5. [ ] **Pending Action:** Reclaim ~17 GB on `D:` by deleting `D:\Debian` when ready.
