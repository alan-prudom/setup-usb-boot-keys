#!/usr/bin/env bash
# ==============================================================================
# Post-Backup Diagnostic & Log Extraction Wizard
# Designed for Rescuezilla, Clonezilla, and Live Rescue USB Environments
# ==============================================================================

set -u

# Styling
if [ -t 1 ]; then
    BOLD="\033[1m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    RED="\033[1;31m"
    CYAN="\033[1;36m"
    MAGENTA="\033[1;35m"
    RESET="\033[0m"
else
    BOLD=""
    GREEN=""
    YELLOW=""
    RED=""
    CYAN=""
    MAGENTA=""
    RESET=""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Strict Yes/No prompt function (rejects empty Return key)
prompt_yes_no() {
    local prompt_msg="$1"
    local answer=""
    while true; do
        echo -en "${prompt_msg}"
        read -r answer
        answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
        if [ -z "$answer" ]; then
            echo -e "  ${YELLOW}⚠️  Empty input (Return/Enter) rejected. A valid response ('y' or 'n') must be typed.${RESET}"
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

# 1. Locate target log file and state information
LOG_FILE="${1:-}"

# Check for latest_backup.env state file
if [ -f "${SCRIPT_DIR}/latest_backup.env" ]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/latest_backup.env" 2>/dev/null || true
    if [ -z "$LOG_FILE" ] && [ -n "${LATEST_LOG:-}" ] && [ -f "$LATEST_LOG" ]; then
        LOG_FILE="$LATEST_LOG"
    fi
fi

# Check for symlink
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    if [ -f "${SCRIPT_DIR}/latest_backup.log" ]; then
        LOG_FILE="${SCRIPT_DIR}/latest_backup.log"
    fi
fi

# Check for newest backup_*.log in script directory or /media
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    NEWEST_LOG=$(ls -t "${SCRIPT_DIR}"/backup_*.log /media/*/*/backup_*.log 2>/dev/null | head -n 1 || true)
    if [ -n "$NEWEST_LOG" ] && [ -f "$NEWEST_LOG" ]; then
        LOG_FILE="$NEWEST_LOG"
    fi
fi

# Fallback to system logs
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    if [ -f "/tmp/rescuezilla.log" ]; then
        LOG_FILE="/tmp/rescuezilla.log"
    elif [ -f "/var/log/clonezilla.log" ]; then
        LOG_FILE="/var/log/clonezilla.log"
    elif [ -f "/var/log/partclone.log" ]; then
        LOG_FILE="/var/log/partclone.log"
    fi
fi

# 2. Analyze state
has_log=0
status_type="UNKNOWN"
error_count=0
warning_count=0

if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    has_log=1
    # Filter benign lines that contain 'error' but are not actual backup failures
    error_count=$(grep -iE "error|failed|fatal|corrupt|abort|read error|input/output error|no space left" "$LOG_FILE" 2>/dev/null \
        | grep -viE "error_count|0 errors|no error|grub-probe: error: cannot find a GRUB drive|check if udevd rules|img_out_err|dmraid.table" \
        | wc -l || true)

    warning_count=$(grep -iE "warning|retry|bad sector" "$LOG_FILE" 2>/dev/null | wc -l || true)

    # Check Clonezilla and Rescuezilla completion markers
    if grep -iE "Ending /usr/sbin/ocs-sr|End of saveparts job|End of savedisk job|Finished!|backup completed successfully|restore completed successfully|clone completed successfully|successfully saved|completed with 0 errors" "$LOG_FILE" >/dev/null 2>&1; then
        if [ "$error_count" -eq 0 ]; then
            status_type="SUCCESS"
        else
            status_type="SUCCESS_WITH_WARNINGS"
        fi
    elif [ "$error_count" -gt 0 ]; then
        status_type="FAILED"
    else
        status_type="COMPLETED_OR_UNKNOWN"
    fi
fi

# 3. Print Header & Assessment
clear 2>/dev/null || true
echo -e "${CYAN}======================================================================${RESET}"
echo -e "${BOLD}       🛡️  POST-BACKUP DIAGNOSTIC & LOG EXTRACTION WIZARD           ${RESET}"
echo -e "${CYAN}======================================================================${RESET}"

echo -e "\n${BOLD}📊 Operational Assessment:${RESET}"
case "$status_type" in
    "SUCCESS")
        echo -e "  ${GREEN}██████████████████████████████████████████████████████████████${RESET}"
        echo -e "  ${GREEN}█  🟢 STATUS: BACKUP COMPLETED SUCCESSFULLY (Zero Errors)     █${RESET}"
        echo -e "  ${GREEN}██████████████████████████████████████████████████████████████${RESET}"
        ;;
    "SUCCESS_WITH_WARNINGS")
        echo -e "  ${YELLOW}██████████████████████████████████████████████████████████████${RESET}"
        echo -e "  ${YELLOW}█  🟡 STATUS: COMPLETED WITH ${error_count} WARNINGS / NON-FATAL ERRORS  █${RESET}"
        echo -e "  ${YELLOW}██████████████████████████████████████████████████████████████${RESET}"
        ;;
    "FAILED")
        echo -e "  ${RED}██████████████████████████████████████████████████████████████${RESET}"
        echo -e "  ${RED}█  🔴 STATUS: BACKUP OPERATION FAILED (${error_count} errors detected)      █${RESET}"
        echo -e "  ${RED}██████████████████████████████████████████████████████████████${RESET}"
        ;;
    *)
        echo -e "  ${YELLOW}██████████████████████████████████████████████████████████████${RESET}"
        echo -e "  ${YELLOW}█  ⚪ STATUS: NO ACTIVE LOG COMPLETED YET / SESSION UNKNOWN    █${RESET}"
        echo -e "  ${YELLOW}██████████████████████████████████████████████████████████████${RESET}"
        ;;
esac

echo -e "\n${BOLD}📋 Session Telemetry:${RESET}"
echo -e "  • Primary Log Target : ${CYAN}${LOG_FILE:-None}${RESET}"
if [ -n "${LATEST_IMAGE_NAME:-}" ]; then
    echo -e "  • Image Name         : ${BOLD}${LATEST_IMAGE_NAME}${RESET}"
fi
if [ -n "${LATEST_DEST_DIR:-}" ]; then
    echo -e "  • Destination Path   : ${CYAN}${LATEST_DEST_DIR}${RESET}"
fi
if [ -n "${LATEST_TARGET_DRIVE:-}" ]; then
    echo -e "  • Source Drive       : ${CYAN}${LATEST_TARGET_DRIVE}${RESET} (${LATEST_PARTITIONS:-all})"
fi
if [ "$has_log" -eq 1 ]; then
    echo -e "  • Log Size           : $(du -h "$LOG_FILE" 2>/dev/null | awk '{print $1}') ($(wc -l < "$LOG_FILE") lines)"
    echo -e "  • Detected Errors    : ${RED}${error_count}${RESET}"
    echo -e "  • Detected Warnings  : ${YELLOW}${warning_count}${RESET}"
    echo -e "  • Last Log Timestamp : $(date -r "$LOG_FILE" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")"
else
    echo -e "  • Log Status         : ${RED}Not Found (Live session active or stateless run)${RESET}"
fi

# Function: Generate Unified Diagnostic Bundle
create_bundle() {
    local out_dir="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local bundle_dir="${out_dir}/backup_diagnostic_${timestamp}"

    mkdir -p "$bundle_dir"
    echo -e "\n${CYAN}📦 Generating Diagnostic Bundle in: ${bundle_dir}...${RESET}"

    if [ "$has_log" -eq 1 ]; then
        cp -v "$LOG_FILE" "${bundle_dir}/backup_operation.log"
    fi
    if [ -f "${SCRIPT_DIR}/latest_backup.env" ]; then
        cp -v "${SCRIPT_DIR}/latest_backup.env" "${bundle_dir}/"
    fi
    dmesg -T > "${bundle_dir}/kernel_dmesg.log" 2>/dev/null || true
    journalctl -b > "${bundle_dir}/system_journal.log" 2>/dev/null || true
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL > "${bundle_dir}/block_devices.txt" 2>/dev/null || true
    fdisk -l > "${bundle_dir}/partition_tables.txt" 2>/dev/null || true
    df -h > "${bundle_dir}/filesystem_usage.txt" 2>/dev/null || true

    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [ -b "$disk" ]; then
            dev_name=$(basename "$disk")
            smartctl -a "$disk" > "${bundle_dir}/smart_${dev_name}.log" 2>/dev/null || true
        fi
    done

    sync
    echo -e "${GREEN}✓ Diagnostic bundle successfully created at:${RESET} ${BOLD}${bundle_dir}${RESET}"
}

# Interactive Wizard Menu
while true; do
    echo -e "\n${BOLD}🎛️  Wizard Menu Options:${RESET}"
    echo -e "  ${CYAN}[1]${RESET} Inspect Error Summary & Diagnostic Root Cause"
    echo -e "  ${CYAN}[2]${RESET} Export Full Diagnostic Bundle to NTFS Data Partition"
    echo -e "  ${CYAN}[3]${RESET} Save Log Bundle to Persistent Home Directory (~/saved_logs)"
    echo -e "  ${CYAN}[4]${RESET} Export Log Bundle to Remote Server via SCP / SSH"
    echo -e "  ${CYAN}[5]${RESET} Run SMART Health Test on Connected Disks"
    echo -e "  ${CYAN}[6]${RESET} Reboot System"
    echo -e "  ${CYAN}[7]${RESET} Power Off System"
    echo -e "  ${CYAN}[8]${RESET} Exit Wizard to Shell"
    echo -en "\n${BOLD}Select an action [1-8]: ${RESET}"
    read -r choice
    choice="$(echo "$choice" | xargs)"

    case "$choice" in
        1)
            echo -e "\n${BOLD}🔍 Recent Error & Warning Snippets:${RESET}"
            if [ "$has_log" -eq 1 ]; then
                echo -e "${CYAN}--- Error Matches in $LOG_FILE ---${RESET}"
                grep -iE "error|failed|fatal|corrupt|abort|read error|input/output error|no space left" "$LOG_FILE" 2>/dev/null \
                    | grep -viE "error_count|0 errors|no error|grub-probe: error: cannot find a GRUB drive|check if udevd rules|img_out_err|dmraid.table" \
                    | tail -n 20 || echo "No explicit errors found."
                echo -e "${CYAN}----------------------------------${RESET}"
                echo -e "\n${BOLD}Last 15 lines of log:${RESET}"
                tail -n 15 "$LOG_FILE"
            else
                echo -e "${YELLOW}No active log file available to inspect.${RESET}"
            fi
            ;;
        2)
            create_bundle "$SCRIPT_DIR"
            ;;
        3)
            mkdir -p "$HOME/saved_logs"
            create_bundle "$HOME/saved_logs"
            ;;
        4)
            echo -en "${BOLD}Enter remote server SSH destination (e.g. alan@192.168.1.34:/media/alan/home40/logs): ${RESET}"
            read -r remote_dest
            if [ -n "$remote_dest" ]; then
                tmp_dir="/tmp/bundle_export_$(date +%Y%m%d_%H%M%S)"
                create_bundle "$tmp_dir"
                echo -e "${CYAN}Transmitting bundle over SSH/SCP to ${remote_dest}...${RESET}"
                scp -r "$tmp_dir"/* "$remote_dest" 2>/dev/null && echo -e "${GREEN}✓ Export complete!${RESET}" || echo -e "${RED}✗ Transfer failed. Verify network connectivity.${RESET}"
                rm -rf "$tmp_dir"
            fi
            ;;
        5)
            echo -e "\n${BOLD}🩺 SMART Drive Health Telemetry:${RESET}"
            for d in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
                if [ -b "$d" ]; then
                    echo -e "\n${CYAN}Disk $d:${RESET}"
                    smartctl -H "$d" 2>/dev/null || echo "SMART not supported on $d"
                fi
            done
            ;;
        6)
            if prompt_yes_no "Are you sure you want to reboot the system? (y/n): "; then
                echo -e "${YELLOW}Rebooting system...${RESET}"
                sync
                reboot 2>/dev/null || systemctl reboot || true
                break
            fi
            ;;
        7)
            if prompt_yes_no "Are you sure you want to power off the system? (y/n): "; then
                echo -e "${YELLOW}Shutting down system...${RESET}"
                sync
                poweroff 2>/dev/null || systemctl poweroff || true
                break
            fi
            ;;
        8)
            echo -e "${GREEN}Exiting wizard.${RESET}"
            break
            ;;
        "")
            echo -e "${YELLOW}⚠️  Empty input (Return/Enter) rejected. Please select an action between 1 and 8.${RESET}"
            ;;
        *)
            echo -e "${RED}⚠️  Invalid selection '$choice'. Please choose 1-8.${RESET}"
            ;;
    esac
done
