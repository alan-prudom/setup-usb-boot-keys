#!/usr/bin/env bash
# ==============================================================================
# live_rescue_hub.sh
# Live ISO Guest Support & Diagnostics Master Menu
# Runs inside Rescuezilla Live / Ubuntu. Provides interactive execution of
# CLI backup tools, post-backup wizard, OBD diagnostics, and coverage management.
# ==============================================================================
set -u

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
DIM="\033[2m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}"
if [ -d "/scripts" ]; then
    SCRIPTS_ROOT="/scripts"
fi

# Detect live coverage base directory on Partition 4 or fallback to /tmp
COV_BASE=""
for cand in "/home/ubuntu/ntfs_usb/live_coverage" "/media/ubuntu/2C95D29B2DF0500E/live_coverage" "/media/ubuntu/SHARED_FAT/live_coverage" "/tmp/live_coverage"; do
    parent=$(dirname "$cand")
    if [ -d "$parent" ] && [ -w "$parent" ]; then
        COV_BASE="$cand"
        break
    fi
done
COV_BASE="${COV_BASE:-/tmp/live_coverage}"

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
            echo -e "  ${YELLOW}⚠️  Empty input (Return key) is not accepted. Please type a number between ${min_val} and ${max_val}.${RESET}"
            continue
        fi
        case "$choice" in
            *[!0-9]*|"")
                echo -e "  ${RED}⚠️  Invalid input '$choice'. Please type a number between ${min_val} and ${max_val}.${RESET}"
                ;;
            *)
                if [ "$choice" -ge "$min_val" ] && [ "$choice" -le "$max_val" ]; then
                    echo "$choice"
                    return 0
                else
                    echo -e "  ${RED}⚠️  Option '$choice' out of range [${min_val}-${max_val}].${RESET}"
                fi
                ;;
        esac
    done
}

run_script_option() {
    local target_script="$1"
    local allow_instrumentation="${2:-1}"

    if [ ! -f "$target_script" ]; then
        echo -e "\n${RED}Error: Script '$target_script' not found!${RESET}"
        read -rp "Press Enter to return..." _
        return
    fi

    if [ "$allow_instrumentation" -eq 1 ]; then
        echo -e "\n${BOLD}Execution Mode Selection:${RESET}"
        echo -e "${DIM}  ℹ️  Why choose: Standard mode executes normally. Instrumented mode records full terminal I/O and tracks line/branch coverage into Partition 4.${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Standard Execution"
        echo -e "  ${CYAN}[2]${RESET} Instrumented with Line & Branch Coverage (${GREEN}Recommended${RESET})"
        local mode
        mode=$(prompt_choice "Select mode [1-2]: " 1 2)
        if [ "$mode" = "2" ]; then
            sudo "${SCRIPTS_ROOT}/run_with_coverage.sh" "$target_script"
        else
            sudo bash "$target_script"
        fi
    else
        sudo bash "$target_script"
    fi

    echo -e "\n${GREEN}Script execution finished.${RESET}"
    read -rp "Press Enter to return to menu..." _
}

# ------------------------------------------------------------------------------
# Submenu: Coverage Traces, Transcripts & Staleness Management
# ------------------------------------------------------------------------------
manage_coverage_submenu() {
    while true; do
        clear
        echo "======================================================================"
        echo -e "${BOLD}       📊 COVERAGE TRACES, TRANSCRIPTS & STALENESS MANAGER           ${RESET}"
        echo "======================================================================"
        echo -e "Coverage Store: ${CYAN}${COV_BASE}${RESET}"
        echo "----------------------------------------------------------------------"

        # List of known instrumented targets
        local targets=(
            "run_rescuezilla_backup_cli.sh"
            "post-backup-wizard.sh"
            "rescue_suite_launcher.sh"
            "sda_rescue_backup.sh"
        )

        echo -e "${BOLD}Current Script Status & Staleness Check:${RESET}"
        local idx=1
        for sname in "${targets[@]}"; do
            local sfile="${SCRIPTS_ROOT}/${sname}"
            local sdir="${COV_BASE}/${sname%.sh}"
            local status="${DIM}[NO RUN RECORDED]${RESET}"
            local stats=""

            if [ -d "$sdir" ] && [ -f "${sdir}/metadata.env" ]; then
                # Load metadata
                # shellcheck source=/dev/null
                source "${sdir}/metadata.env" 2>/dev/null || true
                local curr_sha=""
                if [ -f "$sfile" ]; then
                    curr_sha=$(sha256sum "$sfile" | awk '{print $1}')
                fi

                if [ -n "$curr_sha" ] && [ "$curr_sha" = "${SCRIPT_SHA256:-}" ]; then
                    status="${GREEN}[✓ VALID / UP TO DATE]${RESET}"
                else
                    status="${RED}[⚠️ OUT OF DATE - MODIFIED]${RESET}"
                fi

                local cov_info="${sdir}/coverage.info"
                if [ -f "$cov_info" ]; then
                    local lines_hit
                    lines_hit=$(grep -m1 "^LH:" "$cov_info" 2>/dev/null | cut -d: -f2 || echo "0")
                    local lines_total
                    lines_total=$(grep -m1 "^LF:" "$cov_info" 2>/dev/null | cut -d: -f2 || echo "0")
                    stats="(${lines_hit}/${lines_total} lines)"
                fi
            fi

            echo -e "  ${CYAN}[${idx}]${RESET} ${sname} ${status} ${stats}"
            idx=$((idx + 1))
        done

        echo "----------------------------------------------------------------------"
        echo -e "  ${CYAN}[5]${RESET} 📄 View Clean Terminal Transcript of a Script"
        echo -e "  ${CYAN}[6]${RESET} 🧹 Purge Stale Traces for a Script"
        echo -e "  ${CYAN}[7]${RESET} ♻️  Purge ALL Traces and Reset Coverage"
        echo -e "  ${CYAN}[8]${RESET} 🔄 Recompute LCOV & HTML for all recorded scripts"
        echo -e "  ${CYAN}[9]${RESET} <-- Return to Main Menu"
        echo "======================================================================"

        local sub_choice
        sub_choice=$(prompt_choice "Select option [1-9]: " 1 9)

        case "$sub_choice" in
            1|2|3|4)
                local sel_target="${targets[$((sub_choice - 1))]}"
                echo -e "\n[*] Launching Instrumented Session for: ${CYAN}${sel_target}${RESET}..."
                sudo "${SCRIPTS_ROOT}/run_with_coverage.sh" "${SCRIPTS_ROOT}/${sel_target}"
                read -rp "Press Enter to return..." _
                ;;
            5)
                echo -e "\nSelect script transcript to view:"
                for i in "${!targets[@]}"; do
                    echo -e "  ${CYAN}[$((i+1))]${RESET} ${targets[$i]}"
                done
                local t_choice
                t_choice=$(prompt_choice "Select [1-${#targets[@]}]: " 1 "${#targets[@]}")
                local sel_t="${targets[$((t_choice - 1))]}"
                local clean_txt="${COV_BASE}/${sel_t%.sh}/session_transcript_clean.txt"
                if [ -f "$clean_txt" ]; then
                    echo -e "\n================ [ Transcript: ${sel_t} ] ================"
                    cat "$clean_txt" | less -R || cat "$clean_txt"
                else
                    echo -e "\n${YELLOW}No transcript found at ${clean_txt}${RESET}"
                fi
                read -rp "Press Enter to return..." _
                ;;
            6)
                echo -e "\nSelect script traces to purge:"
                for i in "${!targets[@]}"; do
                    echo -e "  ${CYAN}[$((i+1))]${RESET} ${targets[$i]}"
                done
                local p_choice
                p_choice=$(prompt_choice "Select [1-${#targets[@]}]: " 1 "${#targets[@]}")
                local sel_p="${targets[$((p_choice - 1))]}"
                rm -rf "${COV_BASE}/${sel_p%.sh}"
                echo -e "\n${GREEN}✓ Purged traces for ${sel_p}.${RESET}"
                sleep 1
                ;;
            7)
                echo -e "\n${RED}⚠️  Are you sure you want to reset ALL coverage metrics on Partition 4?${RESET}"
                echo -en "Type 'yes' to confirm: "
                read -r conf
                if [ "$conf" = "yes" ]; then
                    rm -rf "${COV_BASE}"/*
                    echo -e "${GREEN}✓ All coverage traces reset.${RESET}"
                fi
                sleep 1
                ;;
            8)
                echo -e "\n[*] Recomputing LCOV coverage summaries..."
                for sname in "${targets[@]}"; do
                    local sdir="${COV_BASE}/${sname%.sh}"
                    if [ -f "${sdir}/trace.log" ]; then
                        echo "  • Processing ${sname}..."
                        python3 - << PY_RECOMP
import os, re
sdir = "${sdir}"
tlog = os.path.join(sdir, "trace.log")
file_lines = {}
file_branches = {}
if os.path.exists(tlog):
    with open(tlog, "r", errors="ignore") as f:
        for line in f:
            m = re.search(r"@@COV@@([^@]+)@@([0-9]+)@@", line)
            if m:
                fp = os.path.abspath(m.group(1))
                ln = int(m.group(2))
                if os.path.isfile(fp):
                    file_lines.setdefault(fp, set()).add(ln)
for fp in file_lines:
    with open(fp, "r", errors="ignore") as sf:
        sl = sf.readlines()
    branches = []
    ex = file_lines[fp]
    for idx, raw in enumerate(sl, start=1):
        l = raw.strip()
        if l.startswith("if ") or l.startswith("elif "):
            nxt = idx + 1
            while nxt <= len(sl) and not sl[nxt-1].strip(): nxt += 1
            th = 1 if (idx in ex and nxt in ex) else 0
            el = 1 if (idx in ex and not th) else (1 if idx in ex else 0)
            branches.append((idx, 0, th))
            branches.append((idx, 1, el))
    file_branches[fp] = branches
lpath = os.path.join(sdir, "coverage.info")
with open(lpath, "w") as out:
    for fp in file_lines:
        out.write(f"TN:\nSF:{fp}\n")
        with open(fp, "r", errors="ignore") as sf:
            sl = sf.readlines()
        tot = 0
        for ln, c in enumerate(sl, start=1):
            if not c.strip() or c.strip().startswith("#"): continue
            tot += 1
            out.write(f"DA:{ln},{1 if ln in file_lines[fp] else 0}\n")
        out.write(f"LF:{tot}\nLH:{len(file_lines[fp])}\n")
        brs = file_branches.get(fp, [])
        if brs:
            for ln, brid, tk in brs:
                out.write(f"BRDA:{ln},0,{brid},{tk}\n")
            out.write(f"BRF:{len(brs)}\nBRH:{sum(1 for _,_,tk in brs if tk>0)}\n")
        out.write("end_of_record\n")
PY_RECOMP
                    fi
                done
                echo -e "${GREEN}✓ LCOV regeneration complete.${RESET}"
                sleep 2
                ;;
            9)
                return 0
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        clear
        echo "======================================================================"
        echo -e "${BOLD}       🛡️ RESCUEZILLA LIVE GUEST RESCUE & DIAGNOSTICS HUB            ${RESET}"
        echo "======================================================================"
        echo "Environment    : Rescuezilla Live (Guest OS / RAM / Persistence)"
        echo "Scripts Root   : ${SCRIPTS_ROOT}"
        echo "Coverage Store : ${COV_BASE}"
        echo "Timestamp      : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================================"
        echo -e "\n${BOLD}Primary Operations:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} 🚀 Rescuezilla CLI Backup Assistant (Interactive / Auto)"
        echo -e "  ${CYAN}[2]${RESET} 🧙 Post-Backup Verification & Triage Wizard"
        echo -e "  ${CYAN}[3]${RESET} 🎯 Full Rescue Suite Launcher (10-Option Multi-Drive Suite)"
        echo -e "  ${CYAN}[4]${RESET} ⚡ Dedicated Full /dev/sda Rescue Backup (ddrescue / partclone)"
        echo -e "\n${BOLD}Diagnostics & Storage:${RESET}"
        echo -e "  ${CYAN}[5]${RESET} 🩺 On-Board Diagnostics (OBD) & Pre-Flight Check"
        echo -e "  ${CYAN}[6]${RESET} 🌐 Mount Remote Backup Destination (192.168.1.34:/home40)"
        echo -e "  ${CYAN}[7]${RESET} 📦 Export Diagnostic & Telemetry Bundle (to USB / network)"
        echo -e "\n${BOLD}Coverage & Transcripts:${RESET}"
        echo -e "  ${CYAN}[8]${RESET} 📊 Manage Traces, Text Transcripts & Staleness Submenu"
        echo -e "\n  ${CYAN}[9]${RESET} 🚪 Exit to Shell"
        echo "======================================================================"

        local choice
        choice=$(prompt_choice "Select task [1-9]: " 1 9)

        case "$choice" in
            1) run_script_option "${SCRIPTS_ROOT}/run_rescuezilla_backup_cli.sh" 1 ;;
            2) run_script_option "${SCRIPTS_ROOT}/post-backup-wizard.sh" 1 ;;
            3) run_script_option "${SCRIPTS_ROOT}/rescue_suite_launcher.sh" 1 ;;
            4) run_script_option "${SCRIPTS_ROOT}/sda_rescue_backup.sh" 1 ;;
            5) run_script_option "${SCRIPTS_ROOT}/obd_preflight_check.sh" 0 ;;
            6) run_script_option "${SCRIPTS_ROOT}/mount_home40_backup.sh" 0 ;;
            7) run_script_option "${SCRIPTS_ROOT}/export_diagnostic_bundle.sh" 0 ;;
            8) manage_coverage_submenu ;;
            9)
                echo -e "\nExiting Rescue Hub. Goodbye!"
                exit 0
                ;;
        esac
    done
}

main_menu
