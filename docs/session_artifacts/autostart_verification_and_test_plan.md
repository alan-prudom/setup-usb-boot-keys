# NVMe Thermal Governor: Auto-Start Verification & Reboot Test Plan

**Target System**: HP ZBook 15u G5 (`AP-HP-G5` / `alan-USB-g5`)  
**Date**: August 29, 2026  
**Repository**: `D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys`  

---

## 1. Overview of Configured Auto-Start Services

The thermal management suite has been registered across two distinct operating system contexts:

1. **Background Daemon (`NVMeThermalDaemon.exe`)**:
   * **Location**: Windows Scheduled Task (`\NVMeThermalGovernor`)
   * **Trigger**: Machine Boot (`AtStartup`)
   * **Security Context**: `NT AUTHORITY\SYSTEM` (Session 0)
   * **Role**: 24/7 continuous closed-loop CPU power throttling and dual-sensor telemetry stream (`D:\nvme_state.json`).
2. **System Tray App (`NVMeThermalTray.exe`)**:
   * **Location**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
   * **Trigger**: User Login (`AtLogon`)
   * **Security Context**: `alanp` (Interactive Desktop Session 1)
   * **Role**: Taskbar live temperature icon (`43°`), tooltip status, and desktop balloon/toast notifications.

---

## 2. Test Sequence A: Logout & Login Verification (User Session)

### Objective:
Verify that the System Tray application launches automatically upon user desktop logon.

### Steps:
1. Log out of your Windows desktop session (or select **Sign Out** from the Start menu).
2. Sign back in as user `alanp`.
3. Check the **Windows Taskbar Notification Area (bottom right)**:
   * A small square green icon should appear displaying the live temperature (e.g. `43`).
   * Hover over the icon to verify the tooltip:
     ```
     NVMe: 43°C | Chassis: 30°C | CPU: 75% (Max 75%)
     State: OPTIMAL 75%
     ```
   * Right-click the icon to test the context menu (e.g. Set Max CPU Ceiling to 80%).

---

## 3. Test Sequence B: System Reboot Verification (24/7 Daemon)

### Objective:
Verify that the background daemon starts automatically in Session 0 at boot before user login, protecting the NVMe drive unattended.

### Steps:
1. In your terminal or command prompt, initiate a system restart:
   ```cmd
   shutdown /r /t 0
   ```
2. Wait approximately 45–60 seconds for the HP ZBook to reboot.
3. Reconnect remotely via SSH from your MacBook Air:
   ```bash
   ssh alanp@100.127.153.93
   # Or via local LAN:
   ssh alanp@192.168.1.159
   ```

### Verification Commands (Run in SSH Terminal):

#### 1. Verify Daemon Process is Active:
```powershell
Get-Process NVMeThermalDaemon | Select-Object Id, ProcessName, @{N='RAM_MB';E={[math]::Round($_.WorkingSet64/1MB,2)}}
```
* **Expected Output**: Shows process active with **10–15 MB RAM**.

#### 2. Verify State Telemetry Stream:
```powershell
Get-Content D:\nvme_state.json
```
* **Expected Output**: Shows fresh timestamp, `nvmeTempC`, `chassisTempC`, and `cpuLimitPercent: 75`.

#### 3. Verify CPU Power Scheme Setting:
```cmd
powercfg -q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX
```
* **Expected Output**: `Current AC Power Setting Index: 0x0000004b` (75%).

#### 4. Launch Interactive Terminal TUI Dashboard:
```powershell
uv run D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys\scripts\diagnostic_and_maintenance\nvme_tui.py
```
* **Expected Output**: Full high-contrast terminal dashboard rendering live thermal bars and $\Delta T$ gradient.

#### 5. Launch Web Dashboard (Optional):
```powershell
uv run D:\Github\ap-devices-and-pcs\devices\setup-usb-boot-keys\scripts\diagnostic_and_maintenance\nvme_web.py
```
* Open `http://100.127.153.93:8899` in Safari on your MacBook Air.
