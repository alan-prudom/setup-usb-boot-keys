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
        answer="${answer,,}"
        answer="${answer#"${answer%%[![:space:]]*}"}"
        answer="${answer%"${answer##*[![:space:]]}"}"
        if [ -z "$answer" ]; then
            echo -e "  ${YELLOW}⚠️  Empty response (Return key) is not accepted. You must explicitly type 'y' or 'n'.${RESET}"
            continue
        fi
        case "$answer" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo -e "  ${RED}⚠️  Invalid input '$answer'. Please type 'y' (yes) or 'n' (no).${RESET}"
                ;;
        esac
    done
}

# Rejects empty Return / Enter key; requires an integer within range (or 0)
prompt_choice() {
    local prompt_msg="$1"
    local min_val="$2"
    local max_val="$3"
    local choice=""
    while true; do
        echo -en "${prompt_msg}" >&2
        read -r choice
        choice="${choice#"${choice%%[![:space:]]*}"}"
        choice="${choice%"${choice##*[![:space:]]}"}"
        if [ -z "$choice" ]; then
            echo -e "  ${YELLOW}⚠️  Empty input (Return key) is not accepted. Please type a number between ${min_val} and ${max_val} (or 0).${RESET}" >&2
            continue
        fi
        if [ "$choice" = "0" ]; then
            echo "$choice"
            return 0
        elif [[ "$choice" =~ ^[0-9]+$ ]] && \
             [ "$choice" -ge "$min_val" ] && \
             [ "$choice" -le "$max_val" ]; then
            echo "$choice"
            return 0
        else
            echo -e "  ${RED}⚠️  Invalid option '$choice'. Please type a number between ${min_val} and ${max_val} (or 0).${RESET}" >&2
        fi
    done
}

clear 2>/dev/null || \
    true
echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🚀 LIVE COMMAND-LINE BACKUP ASSISTANT (RESCUE/CLONE)          ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"


# 1. Locate SSH Key & Load Helper Libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(readlink -f "$SCRIPT_DIR")"
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
    # Search common mount points if not found directly
    raw_found=""
    if raw_found=$(find /media/devmon /media/ubuntu /home/ubuntu -maxdepth 3 -name "id_rsa" 2>/dev/null); then
        if [ -n "$raw_found" ]; then
            KEY_FILE=$(head -n 1 <<< "$raw_found")
        fi
    fi
fi

if [ -z "$KEY_FILE" ] \
    || [ ! -f "$KEY_FILE" ]; then
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
    umount -l "$MOUNT_POINT" 2>/dev/null || \
        true
    sleep 1
fi

sshfs -o identityfile="$KEY_FILE",allow_other,StrictHostKeyChecking=no,reconnect \
    "alan@${REMOTE_SERVER}:${REMOTE_PATH}" "$MOUNT_POINT"

# Verify write capability
TEST_FILE="${MOUNT_POINT}/.write_test_$(date +%s)"
if touch "$TEST_FILE" 2>/dev/null \
    && rm -f "$TEST_FILE" 2>/dev/null; then
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
    if [ -n "$dname" ] \
        && [ -b "/dev/${dname}" ]; then
        # Exclude active persistence / live overlay block devices (e.g. casper-rw or backing /cow)
        d_label=""
        if raw_label=$(lsblk -lno LABEL "/dev/${dname}" 2>/dev/null); then
            d_label="${raw_label#"${raw_label%%[![:space:]]*}"}"
            d_label="${d_label%"${d_label##*[![:space:]]}"}"
        fi
        d_mounts=""
        if raw_mnt=$(lsblk -lno MOUNTPOINT "/dev/${dname}" 2>/dev/null); then
            d_mounts="$raw_mnt"
        fi
        if [ "$d_label" = "casper-rw" ] \
            || echo "$d_mounts" | grep -qE "^/cow$"; then
            continue
        fi
        DISCOVERED_DRIVES+=("/dev/${dname}")
    fi
done < <(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2=="disk" && $1 !~ /^(nbd|loop|ram|zram)/{print $1}')

if [ "${#DISCOVERED_DRIVES[@]}" -eq 0 ]; then
    echo -e "${RED}✗ Error: No suitable source disk block devices found on this system (live persistence container excluded)!${RESET}"
    exit 1
fi

for i in "${!DISCOVERED_DRIVES[@]}"; do
    dev_path="${DISCOVERED_DRIVES[$i]}"
    d_size=""
    if raw_size=$(lsblk -d -n -o SIZE "$dev_path" 2>/dev/null); then
        d_size="${raw_size#"${raw_size%%[![:space:]]*}"}"
        d_size="${d_size%"${d_size##*[![:space:]]}"}"
    fi
    [ -z "$d_size" ] && \
        d_size="Unknown"

    d_model=""
    if raw_model=$(lsblk -d -n -o MODEL "$dev_path" 2>/dev/null); then
        d_model="${raw_model#"${raw_model%%[![:space:]]*}"}"
        d_model="${d_model%"${d_model##*[![:space:]]}"}"
    fi
    d_tran=""
    if raw_tran=$(lsblk -d -n -o TRAN "$dev_path" 2>/dev/null); then
        d_tran="${raw_tran#"${raw_tran%%[![:space:]]*}"}"
        d_tran="${d_tran%"${d_tran##*[![:space:]]}"}"
    fi
    if [ -z "$d_model" ]; then
        d_model="Disk Device"
    fi
    if [ -n "$d_tran" ]; then
        d_model="${d_model} (${d_tran})"
    fi
    echo -e "  ${CYAN}[$((i + 1))]${RESET} ${dev_path} (${d_size}, ${d_model})"
done

echo ""
drive_choice=$(prompt_choice "Select disk block device [1-${#DISCOVERED_DRIVES[@]}]: " 1 "${#DISCOVERED_DRIVES[@]}")
drive_idx="$drive_choice"
if [ "$drive_idx" -lt 1 ] \
    || [ "$drive_idx" -gt "${#DISCOVERED_DRIVES[@]}" ]; then
    echo -e "${RED}✗ Error: Invalid drive selection index!${RESET}"
    exit 1
fi
TARGET_DRIVE="${DISCOVERED_DRIVES[$((drive_idx - 1))]}"

# Determine default drive tag for backup folder naming
TARGET_BASE=$(basename "$TARGET_DRIVE")
is_ventoy=0
if [[ "$TARGET_DRIVE" =~ ^/dev/(sd[b-z]|nvme[1-9]|vd[b-z]) ]]; then
    if raw_tgt_label=$(lsblk -n -o LABEL "$TARGET_DRIVE" 2>/dev/null); then
        if grep -qi "ventoy" <<< "$raw_tgt_label"; then
            is_ventoy=1
        fi
    fi
fi

if [ "$is_ventoy" -eq 1 ]; then
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
        p_size=""
        if raw_size=$(lsblk -n -o SIZE "/dev/$p" 2>/dev/null); then
            p_size="${raw_size#"${raw_size%%[![:space:]]*}"}"
            p_size="${p_size%"${p_size##*[![:space:]]}"}"
        fi
        p_fs=""
        if raw_fs=$(lsblk -n -o FSTYPE "/dev/$p" 2>/dev/null); then
            p_fs="${raw_fs#"${raw_fs%%[![:space:]]*}"}"
            p_fs="${p_fs%"${p_fs##*[![:space:]]}"}"
        fi
        p_label=""
        if raw_label=$(lsblk -n -o LABEL "/dev/$p" 2>/dev/null); then
            p_label="${raw_label#"${raw_label%%[![:space:]]*}"}"
            p_label="${p_label%"${p_label##*[![:space:]]}"}"
        fi
        p_desc="${p_size}"
        if [ -n "$p_fs" ]; then
            p_desc="${p_desc}, ${p_fs}"
        fi
        if [ -n "$p_label" ]; then
            p_desc="${p_desc}, label: ${p_label}"
        fi
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
            user_parts="${user_parts#"${user_parts%%[![:space:]]*}"}"
            user_parts="${user_parts%"${user_parts##*[![:space:]]}"}"
            if [ -z "$user_parts" ]; then
                echo -e "  ${YELLOW}⚠️  Partition list cannot be empty. Please enter one or more partition names.${RESET}"
                continue
            fi
            
            # Validate that entered partitions exist on the drive
            invalid_list=()
            valid_all=1
            for up in $user_parts; do
                clean_up="${up#/dev/}"
                found_part=0
                for ap in "${AVAILABLE_PARTS[@]}"; do
                    if [ "$clean_up" = "$ap" ]; then
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
                PARTITIONS_LIST="${user_parts//\/dev\//}"
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
    SCOPE_TAG="${PARTITIONS_LIST// /-}"
fi

TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
DEFAULT_IMAGE_NAME="${DEFAULT_DRIVE_TAG}-${SCOPE_TAG}-${TIMESTAMP}-img"

echo -e "\n${BOLD}Backup Image Naming${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Image names must be unique to avoid overwriting previous snapshots, and spaces are sanitized to underscores for exFAT/SMB compatibility.${RESET}"
echo -en "Enter image folder name [Press Enter for default: '${DEFAULT_IMAGE_NAME}']: "
read -r user_img_name
IMAGE_NAME="${user_img_name:-$DEFAULT_IMAGE_NAME}"
IMAGE_NAME="${IMAGE_NAME// /_}"
DEST_DIR="${MOUNT_POINT}/${IMAGE_NAME}"

# 5. Select Engine
echo -e "\n${BOLD}[4/5] Imaging Engine Selection${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Clonezilla's native CLI ('ocs-sr') is the battle-tested standard with 15+ years of stability in terminal mode. Rescuezilla's CLI is labeled experimental and may format output differently.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Clonezilla Native Engine (ocs-sr) [Standard, Ultra-Reliable]"
echo -e "  ${CYAN}[2]${RESET} Rescuezilla Python CLI (rescuezillapy) [Experimental GUI Backend]"
engine_choice=$(prompt_choice "Select imaging engine [1-2]: " 1 2)

# 6. Select Strict vs Rescue Mode
echo -e "\n${BOLD}[5/5] Error Tolerance & Rescue Mode${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Rescue Mode passes '--rescue' to Partclone, which writes zero blocks and continues cloning when bad sectors or filesystem bitmap mismatches occur instead of aborting.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Standard Mode [Strict: Abort on bad sectors or filesystem inconsistencies]"
echo -e "  ${CYAN}[2]${RESET} Rescue Mode   [Fault-Tolerant: Skip bad blocks and force imaging past errors]"
rescue_choice=$(prompt_choice "Select error tolerance mode [1-2]: " 1 2)

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
engine_label="Clonezilla (ocs-sr)"
if [ "$engine_choice" = "2" ]; then
    engine_label="Rescuezilla (rescuezillapy)"
fi
echo -e "  • Selected Engine  : ${CYAN}${engine_label}${RESET}"

rescue_label="Standard (Strict)"
if [ "$rescue_choice" = "2" ]; then
    rescue_label="ENABLED (--rescue)"
fi
echo -e "  • Rescue Mode      : ${CYAN}${rescue_label}${RESET}"

echo -e "\n${DIM}  ℹ️  Why we ask for confirmation: Starting the backup initiates intensive disk reads and multi-gigabyte network writes. Verifying options now prevents imaging with incorrect parameters.${RESET}"
if ! prompt_yes_no "Start backup operation now? (y/n): "; then
    echo -e "${YELLOW}Backup aborted by user. No disk modifications were made.${RESET}"
    exit 0
fi

LOG_FILE="${LOG_DIR}/backup_${IMAGE_NAME}.log"
echo -e "\n${CYAN}Starting imaging pipeline. Real-time log saved to: ${LOG_FILE}...${RESET}\n"

BACKUP_EXIT_CODE=0
set +e
has_rescuezillapy=1
if ! command -v rescuezillapy >/dev/null 2>&1; then
    has_rescuezillapy=0
fi

if [ "$engine_choice" = "1" ] \
    || [ "$has_rescuezillapy" -eq 0 ]; then
    mkdir -p /home/partimag
    if mountpoint -q /home/partimag; then
        umount -l /home/partimag 2>/dev/null || \
            true
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

    # Specific Triage for Partclone extfs bitmap free count mismatch
    has_bitmap_err=0
    if grep -q "bitmap free count err" "$LOG_FILE" 2>/dev/null; then
        has_bitmap_err=1
    elif [ -f "/var/log/partclone.log" ]; then
        if grep -q "bitmap free count err" /var/log/partclone.log 2>/dev/null; then
            has_bitmap_err=1
        fi
    fi
    if [ "$has_bitmap_err" -eq 1 ]; then
        echo -e "\n  ${YELLOW}🔍 Root Cause Identified: Partclone Filesystem Bitmap Inconsistency${RESET}"
        echo -e "     ${DIM}Partclone detected uncommitted journal transactions or a dirty filesystem on ${TARGET_DRIVE}.${RESET}"
        echo -e "     ${CYAN}Recommended Solutions:${RESET}"
        echo -e "       1. Re-run this assistant and select ${BOLD}Rescue Mode [2] (--rescue)${RESET} to bypass bitmap errors."
        echo -e "       2. Run ${BOLD}fsck -y <partition>${RESET} to repair filesystem metadata before backing up."
    fi
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

