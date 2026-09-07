#!/usr/bin/env bash
# ==============================================================================
# Rescuezilla & Clonezilla CLI Automated Backup Runner
# Includes on-screen rationale for every prompt and strict input validation.
# ==============================================================================

set -e

# Styling
BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
DIM="\033[2m"
RESET="\033[0m"

# ------------------------------------------------------------------------------
# Strict Input Validation Helpers
# ------------------------------------------------------------------------------

# Rejects empty Return / Enter key; requires explicit 'y' or 'n'
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
            *)
                echo -e "  ${RED}⚠️  Invalid input '$answer'. Please type 'y' (yes) or 'n' (no).${RESET}"
                ;;
        esac
    done
}

# Rejects empty Return / Enter key; requires an integer within range
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
            echo -e "  ${YELLOW}⚠️  Empty input (Return key) is not accepted. Please type a number between ${min_val} and ${max_val}.${RESET}" >&2
            continue
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min_val" ] && [ "$choice" -le "$max_val" ]; then
            echo "$choice"
            return 0
        else
            echo -e "  ${RED}⚠️  Invalid option '$choice'. Please type a number between ${min_val} and ${max_val}.${RESET}" >&2
        fi
    done
}

clear 2>/dev/null || true
echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🚀 LIVE COMMAND-LINE BACKUP ASSISTANT (RESCUE/CLONE)          ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

# 1. Locate SSH Key & Load Helper Libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/lib/lib_hardware_detect.sh" ]; then
    source "${SCRIPT_DIR}/lib/lib_hardware_detect.sh"
elif [ -f "/scripts/lib/lib_hardware_detect.sh" ]; then
    source "/scripts/lib/lib_hardware_detect.sh"
fi

KEY_FILE="${SCRIPT_DIR}/id_rsa"
REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"
LOG_DIR="${SCRIPT_DIR}"

if [ ! -f "$KEY_FILE" ]; then
    for candidate in "/scripts/id_rsa" "/home/alan/.ssh/id_rsa" "/home/ubuntu/.ssh/id_rsa" "/home/ubuntu/scripts/id_rsa" "${SCRIPT_DIR}/id_rsa"; do
        if [ -f "$candidate" ]; then
            KEY_FILE="$candidate"
            break
        fi
    done
fi

if [ ! -f "$KEY_FILE" ]; then
    KEY_FILE=$(find /media/devmon /media/ubuntu /home/ubuntu -maxdepth 3 -name "id_rsa" 2>/dev/null | head -n 1 || echo "")
fi

if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}✗ Error: SSH key 'id_rsa' not found.${RESET}"
    exit 1
fi

chmod 600 "$KEY_FILE"
echo -e "${GREEN}✓ SSH Identity Key:${RESET} $KEY_FILE"

# 2. Check Network & Mount Remote Storage via SSHFS
echo -e "\n${BOLD}[1/4] Remote Network Storage Connection${RESET}"
echo -e "${DIM}  ℹ️  Why this is needed: Mounts the backup destination on ${REMOTE_SERVER} (${REMOTE_PATH}) via SSHFS so images can be written directly over the LAN without filling local RAM or flash drives.${RESET}"
mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    echo "Unmounting stale mount at $MOUNT_POINT..."
    umount -l "$MOUNT_POINT" 2>/dev/null || true
    sleep 1
fi

sshfs -o identityfile="$KEY_FILE",allow_other,StrictHostKeyChecking=no,reconnect \
    "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT"

# Verify write capability
TEST_FILE="${MOUNT_POINT}/.write_test_$(date +%s)"
if touch "$TEST_FILE" 2>/dev/null && rm -f "$TEST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ Verified READ-WRITE access to ${REMOTE_SERVER}:${REMOTE_PATH}!${RESET}"
else
    echo -e "${RED}✗ Error: Remote filesystem mounted, but write test failed!${RESET}"
    exit 1
fi

# 3. Dynamic Drive Discovery & Selection
echo -e "\n${BOLD}[2/4] Target Drive Selection${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Dynamically scans all physical and virtual disks attached to this machine to prevent cloning or saving the wrong drive.${RESET}"

DISCOVERED_DRIVES=()
while IFS= read -r dname; do
    if [ -n "$dname" ] && [ -b "/dev/${dname}" ]; then
        DISCOVERED_DRIVES+=("/dev/${dname}")
    fi
done < <(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')

if [ "${#DISCOVERED_DRIVES[@]}" -eq 0 ]; then
    echo -e "${RED}✗ Error: No disk block devices found on this system!${RESET}"
    exit 1
fi

for i in "${!DISCOVERED_DRIVES[@]}"; do
    dev_path="${DISCOVERED_DRIVES[$i]}"
    d_size=$(lsblk -d -n -o SIZE "$dev_path" 2>/dev/null | xargs || echo "Unknown")
    d_model=$(lsblk -d -n -o MODEL "$dev_path" 2>/dev/null | xargs || echo "")
    d_tran=$(lsblk -d -n -o TRAN "$dev_path" 2>/dev/null | xargs || echo "")
    [ -z "$d_model" ] && d_model="Disk Device"
    [ -n "$d_tran" ] && d_model="${d_model} (${d_tran})"
    echo -e "  ${CYAN}[$((i + 1))]${RESET} ${dev_path} (${d_size}, ${d_model})"
done

drive_idx=$(prompt_choice "Select drive to backup [1-${#DISCOVERED_DRIVES[@]}]: " 1 "${#DISCOVERED_DRIVES[@]}")
TARGET_DRIVE="${DISCOVERED_DRIVES[$((drive_idx - 1))]}"

# Determine default drive tag for backup folder naming
TARGET_BASE=$(basename "$TARGET_DRIVE")
if [[ "$TARGET_DRIVE" =~ ^/dev/(sd[b-z]|nvme[1-9]|vd[b-z]) ]] && lsblk -n -o LABEL "$TARGET_DRIVE" 2>/dev/null | grep -qi "ventoy"; then
    DEFAULT_DRIVE_TAG="Ventoy-USB"
elif declare -f detect_machine_model >/dev/null 2>&1; then
    DEFAULT_DRIVE_TAG="$(detect_machine_model)"
else
    DEFAULT_DRIVE_TAG="Host-PC-${TARGET_BASE}"
fi

# 4. Dynamic Partition Discovery & Validation Scope
echo -e "\n${BOLD}[3/4] Partition Backup Scope for ${TARGET_DRIVE}${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Backing up an entire drive takes longer, whereas backing up specific partitions saves storage and speeds up recovery.${RESET}"

AVAILABLE_PARTS=()
while IFS= read -r pname; do
    if [ -n "$pname" ]; then
        AVAILABLE_PARTS+=("$pname")
    fi
done < <(lsblk -n -l -o NAME,TYPE "$TARGET_DRIVE" 2>/dev/null | awk '$2=="part"{print $1}')

echo -e "Available Partitions on ${TARGET_DRIVE}:"
if [ "${#AVAILABLE_PARTS[@]}" -gt 0 ]; then
    for p in "${AVAILABLE_PARTS[@]}"; do
        p_size=$(lsblk -n -o SIZE "/dev/$p" 2>/dev/null | xargs || echo "")
        p_fs=$(lsblk -n -o FSTYPE "/dev/$p" 2>/dev/null | xargs || echo "")
        p_label=$(lsblk -n -o LABEL "/dev/$p" 2>/dev/null | xargs || echo "")
        p_desc="${p_size}"
        [ -n "$p_fs" ] && p_desc="${p_desc}, ${p_fs}"
        [ -n "$p_label" ] && p_desc="${p_desc}, label: ${p_label}"
        echo -e "  • ${BOLD}${p}${RESET} (${p_desc})"
    done
    echo ""
    echo -e "  ${CYAN}[1]${RESET} Entire Disk Image: all partitions on ${TARGET_DRIVE} [Recommended]"
    if [ "${#AVAILABLE_PARTS[@]}" -ge 2 ]; then
        echo -e "  ${CYAN}[2]${RESET} First Two Partitions: ${AVAILABLE_PARTS[0]} + ${AVAILABLE_PARTS[1]} (Typical OS + Boot)"
    else
        echo -e "  ${CYAN}[2]${RESET} Single Partition: ${AVAILABLE_PARTS[0]}"
    fi
    echo -e "  ${CYAN}[3]${RESET} Custom selection (pick exact partition list from above)"
    scope_choice=$(prompt_choice "Select partition scope [1-3]: " 1 3)
else
    echo -e "  ${YELLOW}Notice: No partition table found on ${TARGET_DRIVE}. Backing up raw entire disk.${RESET}"
    scope_choice="1"
fi

case "$scope_choice" in
    1)
        PARTITIONS_LIST="all"
        ;;
    2)
        if [ "${#AVAILABLE_PARTS[@]}" -ge 2 ]; then
            PARTITIONS_LIST="${AVAILABLE_PARTS[0]} ${AVAILABLE_PARTS[1]}"
        else
            PARTITIONS_LIST="${AVAILABLE_PARTS[0]}"
        fi
        ;;
    3)
        while true; do
            echo -en "Enter partition names separated by space (e.g. ${AVAILABLE_PARTS[*]:0:2}): "
            read -r user_parts
            user_parts="$(echo "$user_parts" | xargs)"
            if [ -z "$user_parts" ]; then
                echo -e "  ${YELLOW}⚠️  Partition list cannot be empty. Please enter one or more partition names.${RESET}"
                continue
            fi
            
            # Validate every entered partition against AVAILABLE_PARTS
            valid_all=1
            invalid_list=()
            for up in $user_parts; do
                # Strip leading /dev/ if provided by user
                clean_p="${up#/dev/}"
                found_part=0
                for ap in "${AVAILABLE_PARTS[@]}"; do
                    if [ "$clean_p" = "$ap" ]; then
                        found_part=1
                        break
                    fi
                done
                if [ "$found_part" -eq 0 ]; then
                    valid_all=0
                    invalid_list+=("$up")
                fi
            done
            
            if [ "$valid_all" -eq 1 ]; then
                # Clean up partition list format (no /dev/ prefix)
                PARTITIONS_LIST=$(echo "$user_parts" | sed 's|/dev/||g')
                break
            else
                echo -e "  ${RED}⚠️  The following partition(s) do not exist on ${TARGET_DRIVE}: ${invalid_list[*]}${RESET}"
                echo -e "  ${DIM}Available on ${TARGET_DRIVE}: ${AVAILABLE_PARTS[*]}${RESET}"
            fi
        done
        ;;
esac

# Derive scope tag directly from partition list (e.g. 'all', 'sda2', or 'sda1-sda2')
if [ "$PARTITIONS_LIST" = "all" ]; then
    SCOPE_TAG="all"
else
    SCOPE_TAG=$(echo "$PARTITIONS_LIST" | tr ' ' '-')
fi

TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
DEFAULT_IMAGE_NAME="${DEFAULT_DRIVE_TAG}-${SCOPE_TAG}-${TIMESTAMP}-img"

echo -e "\n${BOLD}Backup Image Naming${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Image names must be unique to avoid overwriting previous snapshots, and spaces are sanitized to underscores for exFAT/SMB compatibility.${RESET}"
echo -en "Enter image folder name [Press Enter for default: '${DEFAULT_IMAGE_NAME}']: "
read -r user_img_name
IMAGE_NAME="${user_img_name:-$DEFAULT_IMAGE_NAME}"
IMAGE_NAME="$(echo "$IMAGE_NAME" | tr ' ' '_')"
DEST_DIR="${MOUNT_POINT}/${IMAGE_NAME}"

# 5. Select Engine
echo -e "\n${BOLD}[4/5] Imaging Engine Selection${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Clonezilla's native CLI ('ocs-sr') is the battle-tested standard with 15+ years of stability in terminal mode. Rescuezilla's CLI is labeled experimental and may format output differently.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Clonezilla Native Engine (ocs-sr) [Standard, Ultra-Reliable]"
echo -e "  ${CYAN}[2]${RESET} Rescuezilla Python Engine (rescuezillapy)"
engine_choice=$(prompt_choice "Select imaging engine [1-2]: " 1 2)

# 6. Rescue Mode Selection (Bad Sectors Handling)
echo -e "\n${BOLD}[5/5] Bad Sector & Hardware Rescue Handling${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: If the source drive has physical degradation (like SanDisk/Crucial SSDs with uncorrectable sectors), standard Partclone aborts immediately to protect data integrity. In Rescue Mode ('--rescue'), Partclone continues past bad blocks and zeroes unreadable sectors so imaging finishes successfully.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Standard Mode (Strict integrity check; abort if bad sectors are found)"
echo -e "  ${CYAN}[2]${RESET} 🚨 Rescue Mode (--rescue: bypass bad sectors, zero unreadable blocks, continue imaging)"
rescue_choice=$(prompt_choice "Select Rescue Mode [1-2, Default 1]: " 1 2)
RESCUE_FLAG=""
RESCUEZILLA_EXTRA=""
if [ "$rescue_choice" = "2" ]; then
    RESCUE_FLAG="--rescue"
    RESCUEZILLA_EXTRA="--rescue"
    echo -e "  ${YELLOW}⚠️  Rescue Mode enabled: '--rescue' flag will be passed to Partclone.${RESET}"
fi

# 7. Final Execution Confirmation
echo -e "\n${BOLD}--- Pre-Flight Configuration Summary ---${RESET}"
echo -e "  • Target Disk      : ${CYAN}${TARGET_DRIVE}${RESET}"
echo -e "  • Partitions       : ${CYAN}${PARTITIONS_LIST}${RESET}"
echo -e "  • Destination Path : ${CYAN}${DEST_DIR}${RESET}"
echo -e "  • Selected Engine  : ${CYAN}$([ "$engine_choice" = "2" ] && echo "Rescuezilla (rescuezillapy)" || echo "Clonezilla (ocs-sr)")${RESET}"
echo -e "  • Rescue Mode      : ${CYAN}$([ "$rescue_choice" = "2" ] && echo "ENABLED (--rescue)" || echo "Standard (Strict)")${RESET}"

echo -e "\n${DIM}  ℹ️  Why we ask for confirmation: Starting the backup initiates intensive disk reads and multi-gigabyte network writes. Verifying options now prevents imaging with incorrect parameters.${RESET}"
if ! prompt_yes_no "Start backup operation now? (y/n): "; then
    echo -e "${YELLOW}Backup aborted by user. No disk modifications were made.${RESET}"
    exit 0
fi

LOG_FILE="${LOG_DIR}/backup_${IMAGE_NAME}.log"
echo -e "\n${CYAN}Starting imaging pipeline. Real-time log saved to: ${LOG_FILE}...${RESET}\n"

BACKUP_EXIT_CODE=0
set +e
if [ "$engine_choice" = "1" ] || ! command -v rescuezillapy >/dev/null 2>&1; then
    mkdir -p /home/partimag
    if mountpoint -q /home/partimag; then
        umount -l /home/partimag 2>/dev/null || true
    fi
    mount --bind "$MOUNT_POINT" /home/partimag

    DRIVE_NAME="$(basename "$TARGET_DRIVE")"
    if [ "$PARTITIONS_LIST" = "all" ]; then
        ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -p true $RESCUE_FLAG savedisk "$IMAGE_NAME" "$DRIVE_NAME" 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    else
        ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -p true $RESCUE_FLAG saveparts "$IMAGE_NAME" $PARTITIONS_LIST 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    fi
else
    if [ "$PARTITIONS_LIST" = "all" ]; then
        /usr/sbin/rescuezillapy backup \
            --source "$TARGET_DRIVE" \
            --destination "$DEST_DIR" \
            --description "CLI_Backup" \
            $RESCUEZILLA_EXTRA \
            --compression-format gzip 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    else
        /usr/sbin/rescuezillapy backup \
            --source "$TARGET_DRIVE" \
            --partitions $PARTITIONS_LIST \
            --destination "$DEST_DIR" \
            --description "CLI_Backup" \
            $RESCUEZILLA_EXTRA \
            --compression-format gzip 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    fi
fi
set -e

# Record session state for diagnostic wizard
cat << STATE > "${SCRIPT_DIR}/latest_backup.env"
LATEST_LOG="${LOG_FILE}"
LATEST_IMAGE_NAME="${IMAGE_NAME}"
LATEST_DEST_DIR="${DEST_DIR}"
LATEST_TARGET_DRIVE="${TARGET_DRIVE}"
LATEST_PARTITIONS="${PARTITIONS_LIST}"
LATEST_EXIT_CODE="${BACKUP_EXIT_CODE}"
LATEST_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
STATE
ln -sf "$LOG_FILE" "${SCRIPT_DIR}/latest_backup.log"

if [ "$BACKUP_EXIT_CODE" -eq 0 ]; then
    echo -e "\n${GREEN}======================================================================${RESET}"
    echo -e "${GREEN}✓ Backup successfully completed!${RESET}"
    echo -e "  • Image saved to: ${BOLD}${DEST_DIR}${RESET}"
    echo -e "  • Log saved to:   ${BOLD}${LOG_FILE}${RESET}"
    echo -e "${GREEN}======================================================================${RESET}"
else
    echo -e "\n${RED}======================================================================${RESET}"
    echo -e "${RED}✗ Backup process finished with errors (Exit Code: ${BACKUP_EXIT_CODE})!${RESET}"
    echo -e "  • Check log file: ${BOLD}${LOG_FILE}${RESET}"
    echo -e "${RED}======================================================================${RESET}"
fi

# Chained post-run option
echo -e "\n${DIM}  ℹ️  Why we ask this: The Post-Backup Wizard automatically validates image integrity and analyzes logs for bad sectors or network errors.${RESET}"
if prompt_yes_no "Run the Post-Backup Diagnostic Wizard now? (y/n): "; then
    if [ -f "${SCRIPT_DIR}/post-backup-wizard.sh" ]; then
        bash "${SCRIPT_DIR}/post-backup-wizard.sh" "$LOG_FILE" --no-pause
    fi
fi

# Pause before closing terminal window
echo ""
read -n 1 -s -r -p "Execution finished. Press any key to close this terminal..."
echo ""

