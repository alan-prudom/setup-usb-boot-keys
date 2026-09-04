# System Disk Space Audit Report (HP ZBook 15u G5)

> [!NOTE]
> **AUDIT UPDATED (September 4, 2026)**: Drive **C:** has been recovered from **0.06 GB (60 MB)** baseline up to **15.83 GB free** (with a peak of **19.20 GB** following the Evernote AppData migration to `D:`). Drive **D:** is currently at **3.73 GB free** pending completion of the MATLAB offload to external SSD drive **F:**.

---

## 💾 1. Drive Overview & Free Space Progress

| Drive Letter | Volume Label | Total Size | Baseline Free | Current Free | Net Reclaimed | Operational Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`C:`** | **Windows** | 216.00 GB | 0.06 GB (60 MB) | **15.83 GB** | **`+15.77 GB`** | 🟢 **STABLE** (Evernote moved to D:, Google Drive queued to F:) |
| **`D:`** | **data** | 259.70 GB | 9.54 GB | **3.73 GB** | *Pending MATLAB* | 🔴 **CRITICAL** (Offloading 23.8 GB MATLAB to F:) |
| **`E:`** | **1TB(1)** | 931.51 GB | 20.97 GB | **20.97 GB** | — | 🟡 **LOW (2.3%)** (Excluded from transfer operations) |
| **`F:`** | **1TB-SSD** | 931.47 GB | 322.46 GB | **6.39 GB** | **+5.61 GB** | 🔵 **TARGET** (Holds MATLAB R2017b & R2018b; receiving My Drive) |
| **`G:`** | - | 81.02 GB | 44.99 GB | **44.99 GB** | — | ⚪ Secondary external USB |

---

## 🛠️ 2. Executed Cleanups & Migrations Summary

- [x] **Evernote AppData Relocated to `D:\appdata\Evernote`:** SQLite databases (1.25 GB) and caches moved from `C:\Users\alanp\AppData\Roaming\Evernote` and linked via NTFS Directory Junction (`mklink /J`), recovering **`+12.41 GB` on C:**.
- [x] **MATLAB Releases `~R2017b` & `~R2018b` Copied to `F:\`:** 8.64 GB transferred to `F:\Program Files\MATLAB` out of 23.8 GB total.
- [x] **Drive `F:` Recycle Bin Purged:** Released 5.61 GB (`$RYRKL4U.archive`), bringing `F:` free space to **`6.39 GB`**.
- [x] **VS Code Extension Cache Pruned:** 2.00 GB of duplicate toolkits and orphaned download caches removed from `C:\Users\alanp\.vscode\extensions`.
- [x] **Microsoft Office 2016 Uninstalled:** 11 MSI sub-packages and leftover setup directories removed, recovering **~1.52 GB**.
- [x] **NPM, Pip, Gradle & CPAN Caches Purged:** Reclaimed over **4.2 GB** in preliminary cleanups.
- [x] **User Temp Directory Cleaned:** `C:\Users\alanp\AppData\Local\Temp` cleared (**~1.16 GB** reclaimed).

---

## 🚀 3. Active & Upcoming Storage Reclaim Operations

1. **Google Drive Migration (`C:\Users\alanp\My Drive` $\rightarrow$ `F:\My Drive`):**
   - In progress: transferring 4.72 GB across 10,235 files to `F:\My Drive`.
   - Creating NTFS junction `cmd /c mklink /J "C:\Users\alanp\My Drive" "F:\My Drive"` to recover **`+4.72 GB` on `C:`**.
2. **Complete MATLAB Relocation (`~R2020a` & `~R2020b`):**
   - Requires ~15.14 GB space on `F:` to complete copying, rename `D:\Program Files\MATLAB`, and establish junction `D:\Program Files\MATLAB` $\rightarrow$ `F:\Program Files\MATLAB` to reclaim **`+23.78 GB` on `D:`**.
3. **Move Windows Pagefile (`C:\pagefile.sys` — 13.25 GB):**
   - Available to migrate to `D:` or `G:` to immediately recover another **13.25 GB** on `C:`.
