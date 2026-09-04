# System Audit, Disk Space Analysis & Maintenance Report
**Date:** August 30 – September 1, 2026  
**System:** AP-HP-G5 (Windows 10/11)  
**Session Elevation:** Elevated Administrator PowerShell Session

---

## 1. System Health & Thermal Analysis (Aug 30, 2026)
An audit of Windows Event Logs (`Kernel-Power`, `Kernel-Processor-Power`, `ACPI`, and `Thermal-Operational`) and live WMI/hardware sensor queries was conducted.

- **CPU Throttling (`Event ID 37`):** 0 events recorded. The CPU operated without firmware-enforced thermal throttling.
- **Critical Thermal Shutdowns (`Event IDs 88 / 89`):** 0 events recorded.
- **ACPI Thermal Zones:** All 8 zones (`CPUZ`, `GFXZ`, `CHGZ`, `BATZ`, `PCHZ`, `EXTZ`, `LOCZ`, `HEPZ`) were enumerated normally.
- **Live Temperatures:**
  - CPU Zone: **~56°C** (Normal operating range; well below the 100°C / 128°C trip points).
  - NVMe SSD: **~48°C** (Max safe operational ceiling: 81°C).
  - Battery & Peripheral Zones: **29°C – 46°C**.

---

## 2. Overnight Power Management & Reboot History (Aug 30–31, 2026)
System event logs were audited between 20:00 Aug 30 and 12:40 Aug 31:
- **Unexpected Power Losses / Dirty Shutdowns (`Event ID 41`):** **0 occurrences.**
- **Background Power Daemons:** `NVMeThermalDaemon.exe` continuously maintained power scheme policy stability without incident.
- **Planned Windows Update Servicing Cycle:**
  - **08:31:12 AM:** Planned restart triggered by `MoNotificationUx.exe` on behalf of user.
  - **08:37:28 AM:** First-stage update boot initialized.
  - **08:41:38 AM:** Automatic servicing restart initiated cleanly by `TrustedInstaller.exe` to finalize component installation.
  - **08:42:45 AM:** Final operating system boot completed normally (Boot ID: 120).

---

## 3. Disk Space Audit & Cleanup Actions

### 3.1 Initial Baseline vs. Current Drive Status

| Drive | Label | Total Capacity | Starting Free Space | Current Free Space | Net Space Reclaimed |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`C:`** | Windows | 216.00 GB | **6.79 GB (3.1%)** | **11.47 GB (5.3%)** | **+4.68 GB** |
| **`D:`** | data | 259.70 GB | **9.54 GB (3.7%)** | **21.52 GB (8.3%)** | **+11.98 GB** |
| **`G:`** | - | 81.02 GB | 44.99 GB (55.5%) | 44.99 GB (55.5%) | Stable |

---

### 3.2 Actions Performed & Files Removed

#### 1. VS Code Extension Pruning (`C:\Users\alanp\.vscode\extensions`)
- **Space Reclaimed:** **`2.00 GB`**
- **Removed Items:**
  - Orphaned staging cache: `.d18990f0-7fa5-4f83-9fef-863dcdf9d6cd` (404.5 MB)
  - Duplicate/Obsolete C# Toolkits: `ms-dotnettools.csharp-2.100.11` and `v2.90.60` (819.4 MB)
  - Obsolete Gemini Assist: `google.geminicodeassist-2.59.0` (257.5 MB)
  - Obsolete Pylance: `ms-python.vscode-pylance-2025.8.2` (66.5 MB)
  - 9 Redundant GitHub Copilot Builds: `v1.336.0`, `1.297.0`, `1.296.0`, `1.295.0`, `1.293.0`, `1.292.0`, `1.288.0`, `1.284.0`, `1.282.0` (~490 MB)

#### 2. Microsoft Office 2016 Suite Uninstallation
- **MSI Packages Removed:**
  - `Microsoft Office Standard 2016` (`{90160000-0012-0000-1000-0000000FF1CE}`)
  - `Microsoft Office Proofing Tools & Language Packs (English, French, Spanish)`
  - `Microsoft Office Shared MUI & 32-bit Base Components`
  - `Microsoft Office OSM & UX Components`
  - `Microsoft Office Shared Setup Metadata`
- **Removed Leftover Directories:**
  - `C:\Program Files\Microsoft Office` (1,066.7 MB)
  - `C:\Program Files (x86)\Common Files\Microsoft Shared\OFFICE16` (135.7 MB)
  - `C:\Program Files\Common Files\Microsoft Shared\OFFICE16` (314.0 MB)
- **Net Physical Space Reclaimed:** **`~1.52 GB`**
- *Note on Registry Size:* Windows Add/Remove Programs originally displayed ~40 GB due to cumulative overlapping estimates across individual shared MSI components; the actual on-disk payload was ~3–4 GB.

#### 3. Windows Component Store Servicing
- Invoked native Windows servicing maintenance task (`\Microsoft\Windows\Servicing\StartComponentCleanup`) to consolidate and purge superseded update payload files from `C:\Windows\WinSxS`.

---

## 4. Key Architectural Discoveries

### 4.1 Docker WSL2 Virtual Disk Configuration
- **Discovery:** `C:\Users\alanp\AppData\Local\Docker` is configured as an **NTFS Directory Junction (Symlink)** pointing directly to **`D:\Docker_AppData`**.
- **Result:** The **`6.50 GB`** Docker WSL virtual disk (`docker_data.vhdx`) resides physically on drive **`D:`**, not `C:`.
- **WSL Distros:** All user WSL distributions (`Ubuntu-24.04`, `openSUSE-Tumbleweed`, `kali-linux`, and `docker-desktop`) are mapped to `D:\WSL-distros` and `D:\Docker_AppData`.

### 4.2 Windows Pagefile (`pagefile.sys`)
- **Status:** Statically allocated on drive `C:` at **`13.25 GB`**.
- **Note:** `pagefile.sys` remains the single largest non-OS file on `C:`. Moving this virtual memory paging file to `D:` or `G:` remains available as an immediate option to recover 13.25 GB of physical space on `C:` without impacting applications.

---

## 5. Summary of Current Drive `C:` Usage

| Category | Size | Notes |
| :--- | :--- | :--- |
| **`C:\Windows`** | **~60.35 GB** | OS binaries, WinSxS, System32, system drivers |
| **`C:\Program Files` & `(x86)`** | **~44.50 GB** | Installed 64/32-bit software (Docker, Edge, VS Code, Evernote, etc.) |
| **`C:\pagefile.sys`** | **13.25 GB** | Windows paging file |
| **`C:\Users\alanp` (Real Data)** | **~7–8 GB** | Browser profiles (Chrome, Edge), VS Code settings, caches |
| **Current Free Space** | **11.47 GB** | Improved from 6.79 GB baseline |
