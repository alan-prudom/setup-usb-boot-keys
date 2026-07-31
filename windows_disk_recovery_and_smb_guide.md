# Windows 11 Password Recovery, Lock Screen Bypass & Disk Management Master Guide

**Target System**: Windows 11 (`C:\` / `/dev/nvme0n1p3`)  
**Host Environment**: `alan-USB-g5` (Dual-boot Ubuntu 22.04 LTS)  
**Network NAS Server**: `smb://192.168.1.34/home40` (or `smb://100.110.200.56/home40` via Tailscale)  
**Date**: July 31, 2026

---

## 1. Verified Space Recovery Progress Log

Below is the empirical step-by-step space recovery progress logged on `/dev/nvme0n1p3` (`/mnt/win_os`):

| Phase / Action | Commands Executed | Free Space Before | Free Space After | Net Recovered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Initial Audit** | System inspection | 102 MB | 102 MB | 0 MB | **100% Saturated** |
| **Phase 1: Temp & Update Cache Cleanup** | `rm -rf SoftwareDistribution/Download/* Temp/*` | 102 MB | 9.0 GB | **+9.0 GB** | **Succeeded** |
| **Phase 2: Hibernation File Removal** | `rm -f hiberfil.sys` | 9.0 GB | **16.0 GB** | **+6.4 GB** | **Succeeded** |
| **TOTAL SPACE RECOVERED** | **Combined Offline Cleanup** | **102 MB** | **16.0 GB** | **+15.9 GB** | **Partition Rescued (93%)** |

---

## 2. Windows 11 Password & Lock Screen Recovery Methods

When locked out of Windows 11 due to a forgotten password, corrupted Windows Hello PIN, or mandatory Microsoft Account (MSA) online login prompts, use these methods from Linux or recovery mode.

```mermaid
graph TD
    A["Locked Out of Windows 11"] --> B{"Choose Recovery Strategy"}
    
    B --> C["Method 1: Enable Built-in Administrator (Recommended)"]
    B --> D["Method 2: Reset Local SAM Password (chntpw)"]
    B --> E["Method 3: Clear Windows Hello PIN Cache (NGC)"]
    B --> F["Method 4: Lock Screen Accessibility CMD Exploit (utilman.exe)"]
    B --> G["Method 5: Windows Recovery Environment (WinRE)"]

    C --> C1["Bypasses PIN & Microsoft Account prompts completely"]
    D --> D1["Clears local password hash in SAM hive"]
    E --> E1["Forces Windows to bypass corrupted PIN prompt"]
    F --> F1["Spawns elevated CMD at lock screen to create new Admin user"]
```

---

### Method 1: Enable the Built-In `Administrator` Account (Recommended Fix for PIN/MSA Overrides) 🌟

> **Why this works**: Windows 11 user accounts linked to Microsoft Accounts (MSAs) or Windows Hello PINs ignore SAM password clearing at the login screen. The built-in Windows **`Administrator`** account is a pure local account that is **never** tied to a PIN or Microsoft Account.

#### Linux Steps:
1. Mount the Windows partition in Ubuntu Linux:
   ```bash
   sudo mkdir -p /mnt/win_os && sudo mount /dev/nvme0n1p3 /mnt/win_os
   ```
2. Navigate to the Windows registry hive directory:
   ```bash
   cd /mnt/win_os/Windows/System32/config
   ```
3. Run `chntpw` targeting the built-in `Administrator` account:
   ```bash
   chntpw -u "Administrator" SAM
   ```
4. Menu Selections:
   * Press **`2`** (Unlock and enable user account).
   * Press **`1`** (Clear/blank user password).
   * Press **`q`** (Quit editing).
   * Press **`y`** (Write hive file & save changes).
5. Reboot into Windows 11:
   ```bash
   sudo reboot
   ```
6. On the Windows 11 sign-in screen, click **`Administrator`** in the bottom-left corner to log directly into the desktop without a password.

---

### Method 2: Standard Account Password Reset via `chntpw`

#### Linux Steps:
1. Install `chntpw` in Ubuntu:
   ```bash
   sudo apt update && sudo apt install -y chntpw
   ```
2. Navigate to the registry folder:
   ```bash
   cd /mnt/win_os/Windows/System32/config
   ```
3. List all registered Windows user accounts:
   ```bash
   chntpw -l SAM
   ```
4. Clear the password for your username (e.g., `Alan`):
   ```bash
   chntpw -u "Alan" SAM
   ```
   * Press **`1`** (Clear user password).
   * Press **`q`** (Quit).
   * Press **`y`** (Save changes).

---

### Method 3: Clear the Windows Hello PIN Cache (`NGC` Folder)

> **Why this works**: If Windows displays "Your PIN is no longer available due to a change in security settings", corrupt PIN data is cached in the `NGC` folder. Deleting/renaming it forces Windows to bypass the PIN prompt.

#### Linux Steps:
1. Mount Windows OS partition:
   ```bash
   sudo mkdir -p /mnt/win_os && sudo mount /dev/nvme0n1p3 /mnt/win_os
   ```
2. Rename the `NGC` PIN cache directory:
   ```bash
   cd /mnt/win_os/Windows/ServiceProfiles/LocalService/AppData/Local/Microsoft
   sudo mv NGC NGC.old
   ```
3. Reboot into Windows 11.

---

### Method 4: Lock Screen Accessibility Command Prompt Exploit (`utilman.exe`)

> **Why this works**: Replacing `utilman.exe` (Accessibility Utility Manager) with `cmd.exe` allows opening a SYSTEM-privileged command prompt directly over the Windows lock screen without logging in.

#### Linux Steps:
1. Mount Windows OS partition and navigate to `System32`:
   ```bash
   cd /mnt/win_os/Windows/System32
   ```
2. Backup `utilman.exe` and overwrite it with `cmd.exe`:
   ```bash
   sudo cp utilman.exe utilman.exe.bak
   sudo cp cmd.exe utilman.exe
   ```
3. Reboot into Windows 11.
4. On the lock screen, click the **Accessibility Icon** (human/wheelchair icon in the bottom-right corner).
5. An elevated Command Prompt window will pop up over the lock screen!
6. Create a brand new local Administrator user:
   ```cmd
   net user localadmin MyPassword123! /add
   net localgroup Administrators localadmin /add
   ```
7. Log into Windows 11 with your new `localadmin` account!

---

### Method 5: Booting Windows Recovery Environment (WinRE)

If you cannot access Linux:
1. Boot PC into Windows. As soon as the Windows boot spinner appears, hold the power button for 5 seconds to force shutdown.
2. Repeat **2–3 times**. On the 3rd boot, Windows will automatically enter **Automatic Repair / WinRE**.
3. Select **Troubleshoot** -> **Advanced Options** -> **Command Prompt**.
4. Use `cd \Windows\System32` to run the `utilman.exe` replacement trick from WinRE.

---

## 3. High-Yield Windows Disk Space Recovery (C: Drive)

When Windows 11 downloads major updates, system caches (`SoftwareDistribution`, `WinSxS`, `Windows.old`) balloon on the `C:` drive. Run the following phases to recover **40 GB – 80+ GB** of space.

### Automated Cleanup via Windows Command Prompt (Administrator)

Open **Command Prompt as Administrator** in Windows 11 (`Search cmd` -> `Right-click` -> `Run as Administrator`), then execute:

```cmd
:: 1. Disable Hibernation File (Reclaims ~12 GB RAM-dump file)
powercfg /h off

:: 2. Stop Update Service & Clear Downloaded Update Cache (Reclaims 10 - 25 GB)
net stop wuauserv
del /f /s /q C:\Windows\SoftwareDistribution\Download\*
net start wuauserv

:: 3. Clean Component Store / WinSxS (Reclaims 5 - 15 GB)
Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

:: 4. Remove Previous Windows Update Backups (Reclaims 15 - 35 GB)
rd /s /q C:\Windows.old
rd /s /q C:\$WINDOWS.~BT
```

### Offline Linux Emergency Cleanup (Run from Ubuntu)

If Windows `C:` is too full to boot cleanly, run these commands in Ubuntu Linux:

```bash
# 1. Mount Windows OS Partition
sudo mkdir -p /mnt/win_os
sudo mount /dev/nvme0n1p3 /mnt/win_os

# 2. Clear Windows Update Caches & Temp Files
sudo rm -rf /mnt/win_os/Windows/SoftwareDistribution/Download/*
sudo rm -rf /mnt/win_os/Windows/Temp/*
sudo rm -rf /mnt/win_os/Users/*/AppData/Local/Temp/*

# 3. Delete Hibernation File
sudo rm -f /mnt/win_os/hiberfil.sys
```

---

## 4. Mapping & Offloading to the 13 TB SMB Server

Connect Windows 11 directly to your 13 TB SMB server (`home40`) to store downloads, media, and heavy profile folders over local LAN or Tailscale.

### Step 1: Map Network Drive in Windows File Explorer
1. Open **File Explorer** in Windows 11.
2. Right-click **This PC** (or click `...`) -> Select **Map network drive...**
3. Enter Folder Path:
   * **Local Subnet**: `\\192.168.1.34\home40`
   * **Remote / Tailscale**: `\\100.110.200.56\home40`
4. Check **Reconnect at sign-in** -> Click **Finish**.

### Step 2: Relocate Default Downloads & User Folders to SMB NAS
1. Right-click **Downloads** folder in Windows -> Select **Properties**.
2. Click **Location** tab -> Click **Move...**
3. Select your mapped SMB share (`\\192.168.1.34\home40\Downloads`).
4. Click **Apply** -> Click **Yes** to transfer existing files automatically.

---
*Comprehensive Master Guide compiled by Antigravity AI for alan-USB-g5.*
