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
        echo -en "${prompt_msg}"
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

# 1. Locate SSH Key
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FILE="${SCRIPT_DIR}/id_rsa"
REMOTE_SERVER="192.168.1.34"
REMOTE_PATH="/media/alan/home40/Clonezilla"
MOUNT_POINT="/mnt/backup"
LOG_DIR="${SCRIPT_DIR}"

if [ ! -f "$KEY_FILE" ]; then
    KEY_FILE=$(find /media /mnt -name "id_rsa" 2>/dev/null | head -n 1)
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

# 3. Select Drive
echo -e "\n${BOLD}[2/4] Target Drive Selection${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Both the internal system SSD (/dev/sda) and the USB boot drive (/dev/sdb) are present. Selecting the correct drive prevents accidentally reading or cloning the wrong physical disk.${RESET}"
echo -e "  ${CYAN}[1]${RESET} /dev/sda (Internal 1TB Drive - Windows OS + User Data)"
echo -e "  ${CYAN}[2]${RESET} /dev/sdb (128GB USB / SD Drive - Ventoy Bootloader & Live OS)"
drive_choice=$(prompt_choice "Select drive to backup [1-2]: " 1 2)

if [ "$drive_choice" = "2" ]; then
    TARGET_DRIVE="/dev/sdb"
    DEFAULT_DRIVE_TAG="Ventoy-USB"
else
    TARGET_DRIVE="/dev/sda"
    DEFAULT_DRIVE_TAG="HP-ZBook"
fi

# 4. Select Partition Scope
echo -e "\n${BOLD}[3/4] Partition Backup Scope for ${TARGET_DRIVE}${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Backing up an entire 1TB disk takes much longer and consumes massive network storage, whereas backing up only the OS partitions (sda1+sda2) takes minutes and contains everything required to restore Windows.${RESET}"
if [ "$TARGET_DRIVE" = "/dev/sda" ]; then
    echo -e "  ${CYAN}[1]${RESET} Windows 11 Only: sda1 (System Reserved) + sda2 (OS) [Recommended]"
    echo -e "  ${CYAN}[2]${RESET} Entire Internal Disk: all partitions on /dev/sda"
    echo -e "  ${CYAN}[3]${RESET} Custom selection (specify exact partition list)"
else
    echo -e "  ${CYAN}[1]${RESET} Ventoy Core Partitions: sdb1 (Ventoy) + sdb2 (EFI) + sdb3 (Linux OS) [Recommended]"
    echo -e "  ${CYAN}[2]${RESET} Entire USB Drive: all partitions on /dev/sdb"
    echo -e "  ${CYAN}[3]${RESET} Custom selection (specify exact partition list)"
fi

scope_choice=$(prompt_choice "Select partition scope [1-3]: " 1 3)

case "$scope_choice" in
    1)
        if [ "$TARGET_DRIVE" = "/dev/sda" ]; then
            PARTITIONS_LIST="sda1 sda2"
            SCOPE_TAG="Win11"
        else
            PARTITIONS_LIST="sdb1 sdb2 sdb3"
            SCOPE_TAG="Ventoy-Core"
        fi
        ;;
    2)
        PARTITIONS_LIST="all"
        SCOPE_TAG="FullDisk"
        ;;
    3)
        while true; do
            echo -en "Enter partition names separated by space (e.g. sda1 sda2): "
            read -r user_parts
            user_parts="$(echo "$user_parts" | xargs)"
            if [ -n "$user_parts" ]; then
                PARTITIONS_LIST="$user_parts"
                break
            fi
            echo -e "  ${YELLOW}⚠️  Partition list cannot be empty.${RESET}"
        done
        SCOPE_TAG="Custom"
        ;;
esac

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
echo -e "\n${BOLD}[4/4] Imaging Engine Selection${RESET}"
echo -e "${DIM}  ℹ️  Why we ask this: Clonezilla's native CLI ('ocs-sr') is the battle-tested standard with 15+ years of stability in terminal mode. Rescuezilla's CLI is labeled experimental and may format output differently.${RESET}"
echo -e "  ${CYAN}[1]${RESET} Clonezilla Native Engine (ocs-sr) [Standard, Ultra-Reliable]"
echo -e "  ${CYAN}[2]${RESET} Rescuezilla Python Engine (rescuezillapy)"
engine_choice=$(prompt_choice "Select imaging engine [1-2]: " 1 2)

# 6. Final Execution Confirmation
echo -e "\n${BOLD}--- Pre-Flight Configuration Summary ---${RESET}"
echo -e "  • Target Disk      : ${CYAN}${TARGET_DRIVE}${RESET}"
echo -e "  • Partitions       : ${CYAN}${PARTITIONS_LIST}${RESET}"
echo -e "  • Destination Path : ${CYAN}${DEST_DIR}${RESET}"
echo -e "  • Selected Engine  : ${CYAN}$([ "$engine_choice" = "2" ] && echo "Rescuezilla (rescuezillapy)" || echo "Clonezilla (ocs-sr)")${RESET}"

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
        ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -p true savedisk "$IMAGE_NAME" "$DRIVE_NAME" 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    else
        ocs-sr -q2 -c -j2 -z1p -i 4096 -sfsck -scs -p true saveparts "$IMAGE_NAME" $PARTITIONS_LIST 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    fi
else
    if [ "$PARTITIONS_LIST" = "all" ]; then
        /usr/sbin/rescuezillapy backup \
            --source "$TARGET_DRIVE" \
            --destination "$DEST_DIR" \
            --description "CLI_Backup" \
            --compression-format gzip 2>&1 | tee "$LOG_FILE"
        BACKUP_EXIT_CODE="${PIPESTATUS[0]}"
    else
        /usr/sbin/rescuezillapy backup \
            --source "$TARGET_DRIVE" \
            --partitions $PARTITIONS_LIST \
            --destination "$DEST_DIR" \
            --description "CLI_Backup" \
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
        bash "${SCRIPT_DIR}/post-backup-wizard.sh" "$LOG_FILE"
    fi
fi
