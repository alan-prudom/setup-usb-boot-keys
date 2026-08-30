# Session State Checkpoint: August 30, 2026 (09:37 BST)

**Host**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Operating System**: Windows 11 Pro 64-bit (Build 26100 / 24H2)  
**Primary NVMe SSD**: Samsung MZVLB512HAJQ-000H1 (512GB PCIe 3.0 x4)  
**Prior Continuous Uptime**: **19.05 Hours (1,143 Minutes)** with **ZERO Crashes**  
**Git Remote**: `https://github.com/alan-prudom/setup-usb-boot-keys.git` (Branch `main`)  

---

## 1. System State & Services Summary Prior to Reboot

```mermaid
graph TD
    subgraph "Tier 1: 24/7 Engine (Auto-Starts at Boot)"
        Task["Windows Scheduled Task: NVMeThermalGovernor"] -->|Runs as SYSTEM| Daemon["NVMeThermalDaemon.exe (v2.1)<br>• 11.6 MB RAM, <0.05% CPU<br>• Win32 powrprof.dll Direct P/Invoke<br>• Gentle +5% Micro-Step Ladder<br>• 120s Cold-Soak Dwell Engine"]
        Daemon --> State["D:\nvme_state.json (Atomic Stream)"]
        Daemon --> DailyLog["D:\logs\nvme_thermal_2026-08-30.csv<br>(State-change only, 7-day auto-purge)"]
    end

    subgraph "Tier 2: User Startup Suite (Auto-Starts at Logon)"
        Logon["User Logon (alanp)"] --> RunKey["HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\NVMeThermalWeb"]
        RunKey --> VBS["nvme_web_startup.vbs (Windowless Mode 0)"]
        VBS --> TrayApp["nvme_tray.py (via uv)<br>• Taskbar Live Temperature Icon<br>• Right-Click Max CPU Ceiling Menu<br>• Embedded Web Server on Port 8899<br>• 100% Avast Whitelisted & Clean"]
    end

    subgraph "Tier 3: 24/7 Connectivity & Bidirectional Boot"
        SSH["OpenSSH Server (sshd)<br>• TCPKeepAlive yes<br>• ClientAliveInterval 30"]
        Power["24/7 AC Power Policy<br>• Standby Timeout: 0 (Never)<br>• ConnectivityInStandby: Always-On"]
        BootScripts["Bidirectional Boot Scripts<br>• boot_to_linux.ps1<br>• boot_to_windows.sh"]
    end
```

---

## 2. Key Accomplishments & Fixes Applied in this Session:

1. **Overnight Stability Verified**:
   * Machine maintained **19 continuous hours of uptime** without a single crash (`0x154` or `0xEF`), keeping NVMe temperatures between **`44°C` and `48°C`**.
2. **24/7 Always-On AC Power & Network Policy**:
   * Disabled AC standby sleep timeout (`standby-timeout-ac 0`) and enabled `ConnectivityInStandby = Always On` to prevent Windows Modern Standby from dropping SSH overnight.
3. **OpenSSH Persistent KeepAlives**:
   * Configured `ClientAliveInterval 30` and `TCPKeepAlive yes` in `C:\ProgramData\ssh\sshd_config` to eliminate router NAT idle timeouts.
4. **Registry Accessibility & Input Fixes**:
   * Disabled Windows ClickLock (`HKCU:\Control Panel\Desktop\ClickLock = 0`).
   * Disabled StickyKeys, FilterKeys, and ToggleKeys accessibility hotkeys to prevent virtual modifier key lockup.
5. **Bidirectional UEFI Boot Scripts**:
   * Deployed `scripts/diagnostic_and_maintenance/boot_to_linux.ps1` and `boot_to_windows.sh`.

---

## 3. Post-Reboot Verification Steps:

1. **Reboot Command**:
   ```cmd
   shutdown /r /t 0
   ```
2. **After Boot (Wait 45s)**:
   * Connect via **TightVNC (`100.127.153.93:5901`)** and enter PIN.
   * Verify the **Taskbar Tray Icon** appears in the bottom-right showing live temperature (`46°`).
   * Open [`http://100.127.153.93:8899`](http://100.127.153.93:8899) in Safari on MacBook Air.
