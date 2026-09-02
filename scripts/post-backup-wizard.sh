#!/usr/bin/env bash
# ==============================================================================
# Post-Backup Diagnostic & Log Extraction Wizard
# Designed for Rescuezilla, Clonezilla, and Live Rescue USB Environments
#
# Usage:
#   ./post-backup-wizard.sh [optional_log_path]
# ==============================================================================

set -u

# Colors
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

# Locate target log file
LOG_FILE="${1:-/tmp/rescuezilla.log}"
if [ ! -f "$LOG_FILE" ]; then
    if [ -f "/var/log/clonezilla.log" ]; then
        LOG_FILE="/var/log/clonezilla.log"
    elif [ -f "/var/log/partclone.log" ]; then
        LOG_FILE="/var/log/partclone.log"
    fi
fi

# Analyze state
has_log=0
status_type="UNKNOWN"
error_count=0
warning_count=0

if [ -f "$LOG_FILE" ]; then
    has_log=1
    error_count=$(grep -iE "error|failed|fatal|corrupt|abort|read error|input/output error|no space left" "$LOG_FILE" 2>/dev/null | grep -viE "error_count|0 errors|no error" | wc -l || true)
    warning_count=$(grep -iE "warning|retry|bad sector" "$LOG_FILE" 2>/dev/null | wc -l || true)

    if grep -iE "backup completed successfully|restore completed successfully|clone completed successfully|successfully saved|completed with 0 errors" "$LOG_FILE" >/dev/null 2>&1; then
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

# Print Header & Banner
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
echo -e "  • Primary Log Target : ${CYAN}${LOG_FILE}${RESET}"
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

    if [ -f "$LOG_FILE" ]; then
        cp -v "$LOG_FILE" "${bundle_dir}/backup_operation.log"
    fi
    dmesg -T > "${bundle_dir}/kernel_dmesg.log" 2>/dev/null || true
    journalctl -b > "${bundle_dir}/system_journal.log" 2>/dev/null || true
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT,MODEL > "${bundle_dir}/block_devices.txt" 2>/dev/null || true
    fdisk -l > "${bundle_dir}/partition_tables.txt" 2>/dev/null || true
    df -h > "${bundle_dir}/filesystem_usage.txt" 2>/dev/null || true

    # Gather SMART health for internal disks
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
    echo -e "  ${CYAN}[2]${RESET} Export Full Diagnostic Bundle to Ventoy NTFS Data Partition"
    echo -e "  ${CYAN}[3]${RESET} Save Log Bundle to Persistent Home Directory (~/saved_logs)"
    echo -e "  ${CYAN}[4]${RESET} Export Log Bundle to Remote Server via SCP / SSH"
    echo -e "  ${CYAN}[5]${RESET} Run SMART Health Test on All Connected Disks"
    echo -e "  ${CYAN}[6]${RESET} Reboot System"
    echo -e "  ${CYAN}[7]${RESET} Power Off System"
    echo -e "  ${CYAN}[8]${RESET} Exit Wizard to Shell"
    echo -en "\n${BOLD}Select an action [1-8]: ${RESET}"
    read -r choice

    case "$choice" in
        1)
            echo -e "\n${BOLD}🔍 Recent Error & Warning Snippets:${RESET}"
            if [ "$has_log" -eq 1 ]; then
                echo -e "${CYAN}--- Error Matches in $LOG_FILE ---${RESET}"
                grep -iE "error|failed|fatal|corrupt|abort|read error|input/output error|no space left" "$LOG_FILE" 2>/dev/null | grep -viE "error_count|0 errors|no error" | tail -n 20 || echo "No explicit errors found."
                echo -e "${CYAN}----------------------------------${RESET}"
                echo -e "\n${BOLD}Last 15 lines of log:${RESET}"
                tail -n 15 "$LOG_FILE"
            else
                echo -e "${YELLOW}No active log file available to inspect.${RESET}"
            fi
            ;;
        2)
            # Find Ventoy Data Partition (NTFS or exFAT)
            ntfs_mount=""
            for m in /media/*/* /mnt/*; do
                if [ -d "$m" ] && [[ "$m" != *"/Ventoy" ]] && df -T "$m" 2>/dev/null | grep -iE "ntfs|fuseblk|exfat" >/dev/null 2>&1; then
                    ntfs_mount="$m"
                    break
                fi
            done
            if [ -z "$ntfs_mount" ]; then
                # Attempt to mount sdd4 / label partition
                mkdir -p /mnt/usb_data
                if mount /dev/sdd4 /mnt/usb_data 2>/dev/null; then
                    ntfs_mount="/mnt/usb_data"
                fi
            fi

            if [ -n "$ntfs_mount" ] && [ -d "$ntfs_mount" ]; then
                create_bundle "$ntfs_mount"
            else
                echo -e "${YELLOW}Could not auto-mount USB NTFS partition. Saving to /tmp/diagnostic_bundle...${RESET}"
                create_bundle "/tmp"
            fi
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
            echo -e "${YELLOW}Rebooting system...${RESET}"
            sync
            reboot 2>/dev/null || systemctl reboot || true
            break
            ;;
        7)
            echo -e "${YELLOW}Shutting down system...${RESET}"
            sync
            poweroff 2>/dev/null || systemctl poweroff || true
            break
            ;;
        8)
            echo -e "${GREEN}Exiting wizard.${RESET}"
            break
            ;;
        *)
            echo -e "${RED}Invalid selection. Please choose 1-8.${RESET}"
            ;;
    esac
done
