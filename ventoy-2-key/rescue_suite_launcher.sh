#!/usr/bin/env bash
# ==============================================================================
# rescue_suite_launcher.sh
# Unified Interactive Suite for Network Storage & Rescuezilla / Clonezilla Tools
# Connects Network Storage (home40) and launches all 5 core functions:
# [1] Backup Image (Clonezilla ocs-sr & Rescuezilla)
# [2] Restore Image to Target Device
# [3] Clone Device-to-Device Directly
# [4] Verify Backup Image Integrity
# [5] Image Explorer (Mount & Browse Partclone Images)
# [6] Mount Remote Network Storage (home40) Only
# [7] Post-Backup Diagnostic Wizard
# ==============================================================================

set -e

# Styling
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
DIM="\033[2m"
RESET="\033[0m"

# SSH / Network Configurations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"
KEY_FILE="${SCRIPT_DIR}/id_rsa"

# Locate SSH Key
if [ ! -f "$KEY_FILE" ]; then
    for candidate in "/scripts/id_rsa" "/home/ubuntu/.ssh/id_rsa" "/home/ubuntu/scripts/id_rsa" "${SCRIPT_DIR}/id_rsa"; do
        if [ -f "$candidate" ]; then
            KEY_FILE="$candidate"
            break
        fi
    done
fi

if [ ! -f "$KEY_FILE" ]; then
    KEY_FILE=$(find /media /mnt /home -name "id_rsa" 2>/dev/null | head -n 1)
fi

# POSIX Input Validation Helpers
prompt_yes_no() {
    local prompt_msg="$1"
    local answer=""
    while true; do
        echo -en "${prompt_msg}"
        read -r answer
        answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
        if [ -z "$answer" ]; then
            echo -e "  ${YELLOW}⚠️  Empty response (Return key) is not accepted. You must explicitly type 'y' or 'n'.${RESET}"
            continue
        fi
        case "$answer" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) echo -e "  ${RED}⚠️  Invalid input '$answer'. Please type 'y' (yes) or 'n' (no).${RESET}" ;;
        esac
    done
}

prompt_choice() {
    local prompt_msg="$1"
    local min_val="$2"
    local max_val="$3"
    local choice=""
    while true; do
        echo -en "${prompt_msg}" >&2
        read -r choice
        choice="$(echo "$choice" | xargs)"
        if [ -z "$choice" ]; then
            echo -e "  ${YELLOW}⚠️  Empty input (Return key) rejected. Type a number between ${min_val} and ${max_val}.${RESET}" >&2
            continue
        fi
        case "$choice" in
            *[!0-9]*|"")
                echo -e "  ${RED}⚠️  Invalid input '$choice'. Please type a number between ${min_val} and ${max_val}.${RESET}" >&2
                ;;
            *)
                if [ "$choice" -ge "$min_val" ] && [ "$choice" -le "$max_val" ]; then
                    echo "$choice"
                    return 0
                else
                    echo -e "  ${RED}⚠️  Invalid option '$choice'. Please type a number between ${min_val} and ${max_val}.${RESET}" >&2
                fi
                ;;
        esac
    done
}

# Network Storage Setup Helper
ensure_network_mount() {
    echo -e "\n${BOLD}[*] Checking Network Storage Connection...${RESET}"
    echo -e "${DIM}  ℹ️  Why this is needed: Mounts remote storage on ${REMOTE_SERVER} (${REMOTE_PATH}) to ${MOUNT_POINT} and binds to /home/partimag so images stream directly over LAN without filling RAM.${RESET}"
    
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Remote storage is already mounted at ${MOUNT_POINT}.${RESET}"
    else
        if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            echo -e "  ${RED}✗ Warning: SSH key 'id_rsa' not found. Checking local mounts...${RESET}"
        else
            chmod 600 "$KEY_FILE" 2>/dev/null || true
            echo -e "  ${CYAN}• Connecting to ${REMOTE_SERVER}:${REMOTE_PATH}...${RESET}"
            mkdir -p "$MOUNT_POINT"
            if sshfs -o allow_other,default_permissions,IdentityFile="$KEY_FILE",ConnectTimeout=8,ServerAliveInterval=15 "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT" 2>/dev/null; then
                echo -e "  ${GREEN}✓ Connected successfully via SSHFS to ${MOUNT_POINT}!${RESET}"
            else
                echo -e "  ${YELLOW}⚠️  SSHFS auto-mount failed. Network may be offline or host unreachable.${RESET}"
            fi
        fi
    fi

    # Bind mount to /home/partimag for Clonezilla native tool compatibility
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        mkdir -p /home/partimag
        if ! mountpoint -q /home/partimag 2>/dev/null; then
            mount --bind "$MOUNT_POINT" /home/partimag 2>/dev/null || true
            echo -e "  ${GREEN}✓ Bind-mounted ${MOUNT_POINT} -> /home/partimag for Clonezilla compatibility.${RESET}"
        fi
        ln -sfn "$MOUNT_POINT" /home/ubuntu/Desktop/Remote_Backup_Storage 2>/dev/null || true
        return 0
    fi
    return 1
}

# ------------------------------------------------------------------------------
# Interactive Menu Loop
# ------------------------------------------------------------------------------
while true; do
    clear 2>/dev/null || true
    echo -e "${CYAN}======================================================================${RESET}"
    echo -e "${BOLD}       🛡️ RESCUEZILLA & CLONEZILLA UNIFIED RESCUE SUITE               ${RESET}"
    echo -e "${CYAN}======================================================================${RESET}"
    echo -e "  Active Mode: ${GREEN}Live Persistent USB${RESET} | Remote Target: ${CYAN}${REMOTE_SERVER}:${REMOTE_PATH}${RESET}"
    echo -e "----------------------------------------------------------------------"
    echo -e "  ${BOLD}Core Operations:${RESET}"
    echo -e "  ${CYAN}[1]${RESET} 📤 ${BOLD}Backup Image${RESET}            (Create backup of disk or partition)"
    echo -e "  ${CYAN}[2]${RESET} 📥 ${BOLD}Restore Image${RESET}           (Restore an existing image to disk)"
    echo -e "  ${CYAN}[3]${RESET} 🔀 ${BOLD}Clone Device-to-Device${RESET}  (Direct disk-to-disk clone without temp file)"
    echo -e "  ${CYAN}[4]${RESET} 🛡️ ${BOLD}Verify Backup Image${RESET}     (Audit image integrity and checksums)"
    echo -e "  ${CYAN}[5]${RESET} 🔍 ${BOLD}Image Explorer${RESET}          (Mount & extract individual files from image)"
    echo -e "----------------------------------------------------------------------"
    echo -e "  ${BOLD}Storage & Diagnostic Utilities:${RESET}"
    echo -e "  ${CYAN}[6]${RESET} 🌐 ${BOLD}Connect Network Storage${RESET} (Mount home40/Clonezilla share via SSHFS)"
    echo -e "  ${CYAN}[7]${RESET} 💾 ${BOLD}Mount Local Storage${RESET}     (Mount SHARED FAT and Internal HDD ro)"
    echo -e "  ${CYAN}[8]${RESET} 📋 ${BOLD}Post-Backup Wizard${RESET}      (Examine backup manifests & disk health)"
    echo -e "  ${CYAN}[9]${RESET} 🖥️  ${BOLD}Launch Rescuezilla GUI${RESET}  (Native Rescuezilla graphical window)"
    echo -e "  ${CYAN}[0]${RESET} 🚪 Exit"
    echo -e "${CYAN}======================================================================${RESET}"

    echo -e "${DIM}  ℹ️  Why choose from this menu: All tools automatically ensure your network backup share is connected to /home/partimag, preventing local memory/disk exhaustion.${RESET}"
    choice=$(prompt_choice "  Enter your selection [0-9]: " 0 9)

    case "$choice" in
        1)
            # Backup
            echo -e "\n${BOLD}>>> Launching Backup Assistant...${RESET}"
            ensure_network_mount || true
            if [ -f "${SCRIPT_DIR}/run_rescuezilla_backup_cli.sh" ]; then
                bash "${SCRIPT_DIR}/run_rescuezilla_backup_cli.sh"
            elif [ -f "/scripts/run_rescuezilla_backup_cli.sh" ]; then
                bash "/scripts/run_rescuezilla_backup_cli.sh"
            else
                echo -e "${YELLOW}Falling back to Clonezilla ocs-sr wizard...${RESET}"
                sudo ocs-sr -x || sudo rescuezilla
            fi
            ;;
        2)
            # Restore
            echo -e "\n${BOLD}>>> Restore Image to Destination Device...${RESET}"
            ensure_network_mount || true
            echo -e "  ${DIM}Select restore engine:${RESET}"
            echo -e "  ${CYAN}[1]${RESET} Clonezilla Native CLI (ocs-sr restoreparts / restoredisk)"
            echo -e "  ${CYAN}[2]${RESET} Rescuezilla GUI Guided Restore"
            r_eng=$(prompt_choice "  Select engine [1-2]: " 1 2)
            if [ "$r_eng" = "1" ]; then
                echo -e "\n${BOLD}Starting Clonezilla interactive restore wizard...${RESET}"
                sudo ocs-sr -g auto -e1 auto -e2 -c -j2 -p true restoredisk
            else
                echo -e "\n${BOLD}Starting Rescuezilla in Restore mode...${RESET}"
                if command -v rescuezillapy >/dev/null 2>&1; then
                    sudo /usr/sbin/rescuezillapy restore &
                else
                    sudo rescuezilla &
                fi
            fi
            ;;
        3)
            # Clone Device-to-Device
            echo -e "\n${BOLD}>>> Direct Device-to-Device Clone...${RESET}"
            echo -e "${DIM}  ℹ️  Why Clonezilla Native: Directly clones from source disk to target disk via Partclone without needing network storage.${RESET}"
            echo -e "  ${CYAN}[1]${RESET} Clonezilla Native Clone Wizard (ocs-onthefly)"
            echo -e "  ${CYAN}[2]${RESET} Rescuezilla GUI Clone Wizard"
            c_eng=$(prompt_choice "  Select engine [1-2]: " 1 2)
            if [ "$c_eng" = "1" ]; then
                sudo ocs-onthefly
            else
                if command -v rescuezillapy >/dev/null 2>&1; then
                    sudo /usr/sbin/rescuezillapy clone &
                else
                    sudo rescuezilla &
                fi
            fi
            ;;
        4)
            # Verify Backup Image
            echo -e "\n${BOLD}>>> Verify Backup Image Integrity...${RESET}"
            ensure_network_mount || true
            echo -e "  ${DIM}Available images in /home/partimag:${RESET}"
            ls -la /home/partimag 2>/dev/null || true
            echo -e "\n  ${CYAN}[1]${RESET} Clonezilla Native Verify (ocs-chkimg)"
            echo -e "  ${CYAN}[2]${RESET} Rescuezilla GUI Verify Tool"
            v_eng=$(prompt_choice "  Select verify method [1-2]: " 1 2)
            if [ "$v_eng" = "1" ]; then
                echo -en "  Enter image directory name to verify: "
                read -r img_name
                if [ -n "$img_name" ] && [ -d "/home/partimag/$img_name" ]; then
                    sudo ocs-chkimg -d "/home/partimag" "$img_name"
                else
                    echo -e "${RED}Directory not found. Launching interactive checker...${RESET}"
                    sudo ocs-chkimg
                fi
            else
                if command -v rescuezillapy >/dev/null 2>&1; then
                    sudo /usr/sbin/rescuezillapy verify &
                else
                    sudo rescuezilla &
                fi
            fi
            ;;
        5)
            # Image Explorer (Mount & Browse Files Inside Image)
            echo -e "\n${BOLD}>>> Image Explorer (Mount & Browse Files Inside Image)...${RESET}"
            ensure_network_mount || true
            echo -e "${DIM}  ℹ️  Why this is useful: Mounts partclone/fsarchiver images via qemu-nbd so you can copy specific files without restoring the whole disk.${RESET}"

            echo -e "\n  ${CYAN}[1]${RESET} Select and Mount Specific Image (CLI + File Browser)"
            echo -e "  ${CYAN}[2]${RESET} Open Native Rescuezilla GUI Wizard"
            exp_choice=$(prompt_choice "  Select mode [1-2]: " 1 2)

            if [ "$exp_choice" = "1" ] && command -v rescuezillapy >/dev/null 2>&1; then
                mapfile -t img_list < <(find /home/partimag -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort)
                if [ ${#img_list[@]} -eq 0 ]; then
                    echo -e "${YELLOW}No backup image directories found in /home/partimag.${RESET}"
                    echo -e "Launching native Rescuezilla GUI instead..."
                    sudo rescuezilla &
                else
                    echo -e "\n  ${BOLD}Available Backup Images:${RESET}"
                    idx=1
                    for img in "${img_list[@]}"; do
                        echo -e "  ${CYAN}[$idx]${RESET} $img"
                        idx=$((idx + 1))
                    done
                    sel_idx=$(prompt_choice "  Select image to explore [1-${#img_list[@]}]: " 1 "${#img_list[@]}")
                    selected_img="${img_list[$((sel_idx - 1))]}"
                    mount_dest="/mnt/image_explorer_${selected_img}"
                    sudo mkdir -p "$mount_dest"
                    echo -e "  Mounting image ${BOLD}${selected_img}${RESET} to ${BOLD}${mount_dest}${RESET}..."
                    sudo /usr/sbin/rescuezillapy mount --source "/home/partimag/${selected_img}" --destination "$mount_dest" &
                    sleep 2
                    if command -v pcmanfm >/dev/null 2>&1; then
                        pcmanfm "$mount_dest" 2>/dev/null &
                    fi
                    echo -e "${GREEN}✓ Image Explorer launched. Destination: $mount_dest${RESET}"
                fi
            else
                echo -e "  Launching Rescuezilla GUI to open Image Explorer..."
                sudo rescuezilla &
            fi
            ;;
        6)
            # Connect Network Storage Only
            ensure_network_mount
            ;;
        7)
            # Mount Local Storage
            echo -e "\n${BOLD}>>> Mounting Local USB FAT & Internal HDD (ro)...${RESET}"
            if [ -x /usr/local/bin/mount_storage_startup.sh ]; then
                sudo /usr/local/bin/mount_storage_startup.sh
            elif [ -x "${SCRIPT_DIR}/mount_fat_and_hdd.sh" ]; then
                sudo "${SCRIPT_DIR}/mount_fat_and_hdd.sh"
            else
                echo -e "${RED}Mount helper script not found.${RESET}"
            fi
            ;;
        8)
            # Post-Backup Wizard
            echo -e "\n${BOLD}>>> Launching Post-Backup Diagnostic Wizard...${RESET}"
            if [ -f "${SCRIPT_DIR}/post-backup-wizard.sh" ]; then
                bash "${SCRIPT_DIR}/post-backup-wizard.sh"
            elif [ -f "/scripts/post-backup-wizard.sh" ]; then
                bash "/scripts/post-backup-wizard.sh"
            else
                echo -e "${RED}post-backup-wizard.sh not found.${RESET}"
            fi
            ;;
        9)
            # Native Rescuezilla GUI
            echo -e "\n${BOLD}>>> Launching Native Rescuezilla GUI...${RESET}"
            ensure_network_mount || true
            sudo rescuezilla &
            ;;
        0)
            echo -e "\nExiting rescue suite. Goodbye!"
            break
            ;;
    esac

    echo -e "\n${DIM}Press Enter to return to main menu...${RESET}"
    read -r _dummy
done
