# Multiboot USB Image Backup & MSYS2 SSH Port 2222 Configuration

**Date:** 2026-09-04  
**Host System:** HP ZBook 15u G5 (AP-HP-G5)  
**Location:** `devices/setup-usb-boot-keys/docs/G5/MULTIBOOT_BACKUP_AND_SSH_CONFIG.md`

---

## 1. Overview

This document records two primary system operations on the HP ZBook 15u G5:
1. **Multiboot USB Image Archive:** Creating a maximum-compression (`tar.gz`) backup of the 28.64 GB USB raw image from `F:\multiboot image` directly to `D:\multiboot_image.tar.gz` with zero intermediate temp space overhead on `C:`.
2. **SSH Port 2222 Server Analysis & Key Authorization:** Inspecting the SSH server listening on port 2222, clarifying authentication mechanics, and deploying the user's `ed25519` public key to the relevant MSYS2 and Windows OpenSSH authorization paths.

---

## 2. Multiboot USB Raw Image Archive

### 2.1 Source Data Profile
* **Source Folder:** `F:\multiboot image\` (Drive `F:` is an external 1TB-SSD with <1 GB remaining free space).
* **Contents:**
  * `mboot.bin` (30,752,000,512 bytes / **28.64 GB**): Raw disk image of a 32 GB SanDisk Ultra USB 3.0 drive created using PassMark `imageUSB` v1.5.1007. Single FAT32 partition labeled `MULTIBOOT`.
  * `mboot.log` (620 bytes): Checksum log:
    * **MD5:** `F7AC5972E58D0D5544050247A665BD3D`
    * **SHA1:** `4B36810F9B8167DBB1F46E80C3C99534701CF800`

### 2.2 Storage Safety & Architecture
Because `C:` has limited free space (~15 GB) and `F:` has only ~780 MB free, standard Windows utilities (which stage uncompressed `.tar` archives in `%TEMP%` on `C:`) could not be used.

Instead, the archive was streamed in-memory directly to `D:` using a Linux pipeline in WSL2:
```bash
wsl -d Ubuntu-24.04 -u root -- bash -c "tar -cf - -C /mnt/f 'multiboot image' | gzip -9 > /mnt/d/multiboot_image.tar.gz"
```

* **Destination:** `D:\multiboot_image.tar.gz`
* **Compression Level:** Maximum gzip (`-9`).
* **Disk Footprint:** Zero temporary files created on `C:` or `F:`. Only the compressed output is written sequentially to `D:`.

---

## 3. SSH Server on Port 2222 & Authentication

### 3.1 Listening Service Diagnostics
A connection check on port 2222 (`netstat -ano | findstr ":2222"` and `ssh -v -p 2222 localhost`) revealed:
* **Listening Socket:** `0.0.0.0:2222` and `[::]:2222`
* **Server Banner:** `SSH-2.0-OpenSSH_10.5`
* **Configuration:** `D:\msys64\etc\ssh\sshd_config` specifies:
  ```text
  Port 2222
  StrictModes no
  AuthorizedKeysFile .ssh/authorized_keys
  ```

### 3.2 Password Authentication Mechanics
When logging into the host over SSH using password authentication:
* The SSH server authenticates against the Windows Local Security Accounts (SAM) subsystem.
* The username is `alanp` (Administrator).
* There is no independent "SSH-only" password; the login password is the user's **Windows login password**.
* It can be changed via `Ctrl + Alt + Del` -> *Change a password* or via administrative command `net user alanp *`.

---

## 4. SSH Public Key Authentication Setup

To eliminate the need for entering passwords over SSH, public key authentication was deployed using the user's `ed25519` key:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNrvfWKdXUmSpQlrLBXF/Ox5AHoFGj8BGacYvPG5xCl alanp2@gmail.com
```

### 4.1 Configured Key Locations
The key was added to all three key stores to ensure compatibility across all SSH servers (MSYS2 on `D:`, MSYS2 on `C:`, and native Windows OpenSSH):

1. **`D:\msys64\home\alanp\.ssh\authorized_keys`** (Primary for Port 2222 MSYS2 sshd)
   * Confirmed existing keys: `alan@Mac`, `root@localhost`, and newly appended `alanp2@gmail.com`.
2. **`C:\msys64\home\alanp\.ssh\authorized_keys`**
   * Configured for the MSYS2 environment on Drive `C:`.
3. **`C:\Users\alanp\.ssh\authorized_keys`**
   * Configured for Windows OpenSSH server sessions.

---

## 5. Summary Checklist

* [x] **Source Image Inspected:** `F:\multiboot image\mboot.bin` (28.64 GB) verified with checksum log.
* [x] **Safe Max-Compression Pipeline Launched:** Direct memory stream to `D:\multiboot_image.tar.gz` with zero intermediate temp overhead.
* [x] **SSH Port 2222 Investigated:** Server identified and password authentication mechanism clarified.
* [x] **SSH Key Deployed:** `alanp2@gmail.com` added to `D:\msys64`, `C:\msys64`, and `C:\Users\alanp` `authorized_keys`.
