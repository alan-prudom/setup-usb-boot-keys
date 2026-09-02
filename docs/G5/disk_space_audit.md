# System Disk Space Audit Report

> [!NOTE]
> **CLEANUP COMPLETED**: Option 1 safe cleanups have fully completed. Drive **C:** free space has been recovered from **0.06 GB (60 MB)** up to **4.28 GB (4,386.9 MB)**!

---

## 💾 1. Drive Overview & Free Space Progress

| Drive Letter | Type | Total Size | Initial Free | Current Free | Total Reclaimed | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **C:** | **Fixed (System SSD/HDD)** | **216.00 GB** | 0.06 GB (60 MB) | **4.28 GB (4,386 MB)** | **+4.22 GB** | 🟢 **STABLE** |
| **D:** | **Fixed (Data SSD/HDD)** | **259.70 GB** | 11.76 GB | **11.76 GB** | — | 🟡 **LOW** |
| **E:** | Removable (USB/SD) | 19.02 GB | 1.30 GB | 1.30 GB | — | ⚪ Removable |
| **F:** | Removable (USB/SD) | 0.03 GB | 0.00 GB | 0.00 GB | — | ⚪ Removable |
| **G:** | Removable (USB Drive) | 81.02 GB | 56.54 GB | 56.54 GB | — | ⛔ *Excluded (USB)* |

---

## 🛠️ 2. Executed Cleanups Summary

- [x] **NPM Package Cache Cleaned** (`npm cache clean --force`)
- [x] **Python Pip Cache Purged** (267 cached wheel files deleted)
- [x] **Gradle Build Caches Purged** (`C:\Users\alanp\.gradle\caches` — **~2.15 GB** reclaimed)
- [x] **Perl CPAN Cache Purged** (`C:\Users\alanp\.cpan` — **~0.91 GB** reclaimed)
- [x] **User Temp Directory Cleaned** (`C:\Users\alanp\AppData\Local\Temp` — **~1.16 GB** reclaimed)

---

## 🚀 3. Additional Reclaim Options (If Further Space is Needed)

If you need to recover more space on **C:** (e.g. up to 20+ GB):

1. **Move `C:\Sync` (16.63 GB)** to `D:\Sync` (Internal Drive D: has 11.76 GB free).
2. **Switch Google Drive (`My Drive` — 16.20 GB)** from *Mirror Files* to *Stream Files* (Files on demand).
3. **Clean Windows WinSxS Component Store** (Run as Administrator):
   ```cmd
   DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
   ```
