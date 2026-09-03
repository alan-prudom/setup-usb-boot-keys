# Ventoy 2 USB Key — Baseline Audit & Upgrade Roadmap

**Device Node:** `/dev/sdb` (128 GB / 119.1 GiB USB Storage Device)  
**Disk Identifier (MBR):** `199e46a9`  
**Working Identifier:** **Ventoy 2** (Secondary / Legacy Rescue Key)  
**Reference Model:** Primary Ventoy Key (documented in `Ventoy/` sub-repository)  
**Date of Record:** September 3, 2026  

---

## 1. Executive Summary & Purpose

This USB drive (`/dev/sdb`) is an older multiboot installation created prior to the recent optimizations developed in this repository for the primary Ventoy key.

It contains:
1. An older Ventoy bootloader core (`v1.1.10`) on `/dev/sdb1` and `/dev/sdb2`.
2. A generic placeholder `ventoy_grub.cfg` without custom F6 direct-boot entries for the installed Ubuntu OS or Windows bootmgr.
3. A full installed Ubuntu 22.04.5 LTS operating system with persistent user data on `/dev/sdb3` (`UUID=e0d8ad1a-410b-4245-9192-66d2a16077b9`).
4. A large FAT32 partition (`SHARED FAT`) on `/dev/sdb4` containing 57 GB of existing user and project files.

The goal is to upgrade and align this drive with the advanced features and configurations of the primary key (**Ventoy 1**) without destroying or endangering the existing partitions, files, or installed operating systems.

---

## 2. Drive Partition Geometry & Detailed Audit

| Partition | Device Node | Filesystem | Label | UUID | Size | Used | Avail | Use% | Description / Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **P1** | `/dev/sdb1` | `exfat` | `Ventoy` | `4E21-0000` | 20 GB | 18 GB | 1.6 GB | 92% | Ventoy ISO storage partition |
| **P2** | `/dev/sdb2` | `vfat` | `VTOYEFI` | `E039-AD96` | 32 MB | 28 MB | 4.6 MB | 86% | Ventoy EFI / GRUB core partition |
| **P3** | `/dev/sdb3` | `ext4` | *(none)* | `e0d8ad1a-410b-4245-9192-66d2a16077b9` | 19 GB | 16 GB | 2.4 GB | 87% | Installed Ubuntu 22.04.5 LTS Rootfs (`/home/alan`) |
| **P4** | `/dev/sdb4` | `vfat` | `SHARED FAT` | `C9D1-3C83` | 82 GB | 57 GB | 25 GB | 70% | Cross-platform FAT32 shared data partition |

---

## 3. Existing Inventory on Partition 1 (`/dev/sdb1`)

### 3.1 ISO Images Present (Total ~17.5 GB)

| File Name | File Size | Category / Purpose |
| :--- | :--- | :--- |
| `ubuntu-24.04.3-live-server-amd64.iso` | 3.3 GB | Modern Ubuntu Server installer |
| `ubuntu-20.04.2.0-desktop-amd64.iso` | 2.8 GB | Desktop live environment |
| `pop-os_22.04_amd64_intel_49.iso` | 2.6 GB | Pop!_OS desktop |
| `debian-live-10.10.0-amd64-xfce.iso` | 2.4 GB | Lightweight Debian XFCE live |
| `Fedora-Workstation-Live-x86_64-33-1.2.iso` | 2.0 GB | Fedora live desktop |
| `PeppermintOS-Debian-64.iso` | 1.5 GB | Peppermint OS |
| `HBCD_PE_x64 2018.iso` | 1.3 GB | Hiren's BootCD PE (Windows diagnostic tools) |
| `CentOS-7-x86_64-Minimal-1810.iso` | 962 MB | Legacy CentOS 7 Minimal installer |
| `gparted-live-1.6.0-10-amd64.iso` | 576 MB | Disk & partition manipulation live environment |
| `clonezilla-live-3.2.0-5-amd64.iso` | 457 MB | Bare-metal disk imaging utility |
| `alpine-standard-3.21.0-x86_64.iso` | 251 MB | Minimal Alpine Linux environment |
| `mini.iso` | 67 MB | Minimal network bootloader |
| `DPMS.ISO` | 47 MB | Driver Pack Mass Storage (legacy driver utility) |
| `supergrub2-classic-2.06s4-multiarch-CD.iso` | 24 MB | Multi-boot fallback scanner |

### 3.2 Configuration Files & Utilities Present

1. **`ventoy_grub.cfg`**:
   - Currently contains dummy/sample entries (`"My Custom Menu"`, `"My Custom SubMenu"`).
   - **Missing:** The production F6 direct boot configuration developed for the primary key (booting `/dev/sdb3` direct kernel and GRUB chainloader, Windows internal drive chainloader).
2. **`ventoy.json`**:
   - Currently missing on this drive.
   - **Missing:** Plugin configurations such as menu aliases, theme settings, and persistence image mappings.
3. **`Project Link.txt`**:
   - Contains link: `https://gemini.google.com/app/8cec7eb529b19078`
4. **`ventoy-1.1.10-windows.zip`**:
   - Portable Windows binary archive stored on the root of Partition 1.

---

## 4. Comparison: Ventoy 1 (Primary) vs. Ventoy 2 (Inserted Drive)

| Feature | Ventoy 1 (Primary Key) | Ventoy 2 (`/dev/sdb` - Current State) |
| :--- | :--- | :--- |
| **Ventoy Core Version** | Up to date / configured | `1.1.10` |
| **F6 Custom Menu (`ventoy_grub.cfg`)** | Configured: direct Ubuntu chainload + Windows chainload | Generic template with echo/sleep commands |
| **Ventoy Plugin Config (`ventoy.json`)** | Persistence mapping for Rescuezilla + SuperGrub alias | Not present |
| **Persistence Container** | `rescuezilla-persistence.dat` (512 MB `casper-rw`) | Not present |
| **Rescue Tools** | Rescuezilla noble 2.6.2 ISO + CLI automation script | Clonezilla + GParted + HBCD + SuperGrub (Rescuezilla missing) |
| **Installed Linux OS (`sdb3`)** | Bootable Ubuntu 22.04 LTS | Bootable Ubuntu 22.04.5 LTS |
| **Data Partition (`sdb4`)** | Formatted / Staging storage | FAT32 `SHARED FAT` (57 GB active data) |

---

## 5. Upgrade Discussion & Safety Strategy

### 5.1 Safe Non-Destructive Ventoy Core Upgrade
Ventoy provides an in-place upgrade mechanism using the `-u` (update) flag:
```bash
Ventoy2Disk.sh -u /dev/sdb
```
* **Safety Mechanism:** `-u` strictly refreshes the bootloader sectors in the MBR/GPT and updates the contents of Partition 2 (`/dev/sdb2` `VTOYEFI`).
* **Protection of Partitions:** It **does not reformat** Partition 1 (`/dev/sdb1`), Partition 3 (`/dev/sdb3`), or Partition 4 (`/dev/sdb4`).
* **Prerequisite:** Partitions must be cleanly unmounted before running `Ventoy2Disk.sh -u`.

### 5.2 Custom Menu & Feature Alignment
To bring Ventoy 2 to full parity with Ventoy 1:
1. **Deploy `/ventoy/ventoy_grub.cfg` on `/dev/sdb1`:**
   - Configure instant `F6` direct booting into `/dev/sdb3` using UUID `e0d8ad1a-410b-4245-9192-66d2a16077b9`.
   - Configure Windows chainloader entry for internal disk `/dev/sda`.
2. **Deploy `/ventoy/ventoy.json` on `/dev/sdb1`:**
   - Configure friendly menu aliases for ISOs.
   - Configure persistence rules if a persistence container is added.
3. **Storage Space on Partition 1:**
   - Partition 1 currently has **1.6 GB** of free space remaining (out of 20 GB).
   - Adding small files (configs, scripts, persistence containers < 1 GB) will fit without removing anything.
   - If larger ISOs (like Rescuezilla 2.6.2 ~1.2 GB) are desired, we can review whether any older ISOs (such as `CentOS-7` or `ubuntu-20.04`) can be pruned or moved to Partition 4 (`SHARED FAT` has 25 GB free).

---

## 6. Next Steps & Action Items

1. Review and approve the naming convention (**Ventoy 2**).
2. Create dedicated scripts and configuration templates in `ventoy-2-key/` within this git repository.
3. Confirm whether Rescuezilla and persistence should be installed on Partition 1, taking available capacity into account.
4. Execute non-destructive Ventoy upgrade and verify F6 custom menu integration.
