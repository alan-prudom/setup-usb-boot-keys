# Session Log: Git Permissions & SSHFS Remote Storage Setup
**Date:** 2026-03-08
**System:** alan-USB-Ventoy (Ubuntu Jammy)
**Remote:** ap-elite (Debian 6.1, 192.168.1.34)

---

## 1. Initial Troubleshooting: Git Clone Failures
### The Problem
Attempting to clone `html_tools` into `/home/alan/GitHub` (which is a mount point for `/ntfs`) failed with:
`error: chmod on /ntfs/GitHub/html_tools/.git/config.lock failed: Operation not permitted`

### The Diagnosis
The drive at `/ntfs` was identified as a **VFAT (FAT32)** filesystem. 
- **Cause:** VFAT does not support Linux-style file permissions (`chmod`). Git requires these permissions to lock configuration files during a clone.
- **Fix (Immediate):** Use the `-c core.filemode=false` flag to tell Git to ignore permission checks.
  ```bash
  git clone -c core.filemode=false https://github.com/AlanP2/html_tools.git /home/alan/GitHub/html_tools
  ```

---

## 2. Filesystem Discussion: FAT32 vs. NTFS vs. exFAT
We discussed converting the pendrive/adapter to a more modern filesystem for better compatibility.
- **Recommendation:** Use a Windows machine to run `convert E: /fs:ntfs` (non-destructive) or reformat to **exFAT** if the drive is used across different operating systems.
- **Reminder:** Linux requires specific mount flags (`permissions`) to handle NTFS file modes correctly.

---

## 3. Remote Storage setup: SSHFS
Goal: Mount a 13TB remote volume from a server (`ap-elite`) onto the local Ventura USB.

### Installation
```bash
sudo apt update && sudo apt install sshfs
```

### Manual Mount Point Creation
```bash
mkdir -p ~/mnt/apelite
```

### Connection Command
```bash
sshfs alan@192.168.1.34:/media/alan/home40 ~/mnt/apelite
```
- **Result:** Successfully mounted the 11TB/13TB volume. Verified with `ls ~/mnt/apelite` which showed backup logs and WinMerge scripts.

---

## 4. Automation & Persistence
To ensure the drive mounts automatically after a reboot:

### Step A: Password-less Authentication (SSH Keys)
Verified that SSH keys are working:
1. Checked for existing keys in `~/.ssh/`.
2. Verified manual login to `192.168.1.34` was successful.

### Step B: Permanent Mount (fstab)
Currently configuring `/etc/fstab` to include:
```text
alan@192.168.1.34:/media/alan/home40 /home/alan/mnt/apelite fuse.sshfs x-systemd.automount,_netdev,user,idmap=user,identityfile=/home/alan/.ssh/id_rsa,allow_other,reconnect 0 0
```
- **Key Flags used:**
  - `x-systemd.automount`: Mounts only when the folder is accessed (prevents boot hangs).
  - `_netdev`: Waits for network to be up.
  - `reconnect`: Resilient to Wi-Fi drops.
  - `idmap=user`: Maps remote file ownership to the local user.

---

## 5. Summary of Current State
- **Local:** `/home/alan/mnt/apelite` is active.
- **Remote:** `ap-elite` connected via SSHFS.
- **Action:** Session documentation saved locally for future reference.
