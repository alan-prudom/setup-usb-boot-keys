#!/usr/bin/env bash
# ==============================================================================
# host_support_hub.sh
# Host OS Master Support, Test & Deployment Hub
# Runs on Ubuntu Host Development PC. Orchestrates VMs, automated expect suites,
# coverage extractions from Partition 4, USB persistence deployments, and reports.
# ==============================================================================
set -u

BOLD="\033[1m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
DIM="\033[2m"
RESET="\033[0m"

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="${SCRIPT_DIR}/${SCRIPT_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/tests/results"
HTML_REPORT="${RESULTS_DIR}/merged_html/index.html"
MERGED_INFO="${RESULTS_DIR}/merged_cumulative_with_live.info"

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
                    echo -e "  ${RED}⚠️  Option '$choice' out of range [${min_val}-${max_val}].${RESET}" >&2
                fi
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Submenu: Host Coverage & Artifact Explorer
# ------------------------------------------------------------------------------
manage_host_coverage_submenu() {
    while true; do
        clear
        echo "======================================================================"
        echo -e "${BOLD}         📊 HOST COVERAGE, TRANSCRIPTS & ARTIFACT EXPLORER           ${RESET}"
        echo "======================================================================"
        echo "Results Directory : ${RESULTS_DIR}"
        echo "----------------------------------------------------------------------"

        local targets=(
            "run_rescuezilla_backup_cli.sh"
            "post-backup-wizard.sh"
            "rescue_suite_launcher.sh"
            "sda_rescue_backup.sh"
        )

        echo -e "${BOLD}Current Script Staleness & Coverage Overview:${RESET}"
        local live_base="${RESULTS_DIR}/live_runs"
        local idx=1
        for sname in "${targets[@]}"; do
            local sfile="${SCRIPT_DIR}/${sname}"
            local sdir="${live_base}/${sname%.sh}"
            local status="${DIM}[NO RUN RECORDED]${RESET}"
            local stats=""

            if [ -d "$sdir" ] && [ -f "${sdir}/metadata.env" ]; then
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
        echo -e "  ${CYAN}[5]${RESET} 🌐 Open Merged Browsable HTML Report in Browser"
        echo -e "  ${CYAN}[6]${RESET} 📄 View Extracted Clean Terminal Transcript for a Script"
        echo -e "  ${CYAN}[7]${RESET} 📥 Pull Latest Coverage & Traces from Partition 4 / VM"
        echo -e "  ${CYAN}[8]${RESET} ♻️  Reset Host Coverage Cache & Stored Traces"
        echo -e "  ${CYAN}[9]${RESET} <-- Return to Main Menu"
        echo "======================================================================"

        local sub_choice
        sub_choice=$(prompt_choice "Select option [1-9]: " 1 9)

        case "$sub_choice" in
            1|2|3|4)
                local sel_target="${targets[$((sub_choice - 1))]}"
                local clean_txt="${live_base}/${sel_target%.sh}/session_transcript_clean.txt"
                if [ -f "$clean_txt" ]; then
                    echo -e "\n================ [ Transcript: ${sel_target} ] ================"
                    cat "$clean_txt" | less -R || cat "$clean_txt"
                else
                    echo -e "\n${YELLOW}No transcript found for ${sel_target} in ${clean_txt}${RESET}"
                fi
                read -rp "Press Enter to return..." _
                ;;
            5)
                if [ -f "$HTML_REPORT" ]; then
                    echo -e "\nOpening ${HTML_REPORT}..."
                    xdg-open "$HTML_REPORT" 2>/dev/null || sensible-browser "$HTML_REPORT" 2>/dev/null || echo "Open file://${HTML_REPORT}"
                else
                    echo -e "\n${YELLOW}HTML Report not yet generated. Run Extract & Merge first.${RESET}"
                fi
                read -rp "Press Enter to return..." _
                ;;
            6)
                echo -e "\nSelect script transcript to view:"
                for i in "${!targets[@]}"; do
                    echo -e "  ${CYAN}[$((i+1))]${RESET} ${targets[$i]}"
                done
                local t_choice
                t_choice=$(prompt_choice "Select [1-${#targets[@]}]: " 1 "${#targets[@]}")
                local sel_t="${targets[$((t_choice - 1))]}"
                local clean_txt="${live_base}/${sel_t%.sh}/session_transcript_clean.txt"
                if [ -f "$clean_txt" ]; then
                    cat "$clean_txt" | less -R || cat "$clean_txt"
                else
                    echo -e "\n${YELLOW}No transcript found at ${clean_txt}${RESET}"
                fi
                read -rp "Press Enter to return..." _
                ;;
            7)
                echo -e "\n[*] Extracting and merging latest live coverage..."
                bash "${SCRIPT_DIR}/extract_and_merge_coverage.sh"
                read -rp "Press Enter to return..." _
                ;;
            8)
                echo -e "\n${RED}⚠️  Reset all extracted traces and merged coverage reports?${RESET}"
                echo -en "Type 'yes' to confirm: "
                read -r conf
                if [ "$conf" = "yes" ]; then
                    rm -rf "${RESULTS_DIR}"/*
                    echo -e "${GREEN}✓ Host results directory cleaned.${RESET}"
                fi
                sleep 1
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
        echo -e "${BOLD}       💻 RESCUEZILLA HOST SUPPORT & TEST ORCHESTRATOR               ${RESET}"
        echo "======================================================================"
        echo "Host Environment: Ubuntu Development System ($(uname -n))"
        echo "Repository Path : ${SCRIPT_DIR}"
        echo "Timestamp       : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================================"
        echo -e "\n${BOLD}Virtualization & Emulation:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} 🖥️  Launch QEMU Test VM (Interactive Selection: Option A or B)"
        echo -e "  ${CYAN}[2]${RESET} ⚡ Fast-Launch Option B Direct Persistence VM (with GTK display)"
        echo -e "\n${BOLD}Testing & Coverage Pipeline:${RESET}"
        echo -e "  ${CYAN}[3]${RESET} 🧪 Run Master Cumulative Automated Expect Suite (6 Test Cases)"
        echo -e "  ${CYAN}[4]${RESET} 📥 Extract Live Coverage & Transcripts from Partition 4 / VM"
        echo -e "  ${CYAN}[5]${RESET} 📊 Coverage & Artifact Explorer (Submenu: HTML, Transcripts, Staleness)"
        echo -e "\n${BOLD}USB Deployment & Maintenance:${RESET}"
        echo -e "  ${CYAN}[6]${RESET} 🚀 Deploy Four-Tier Redundancy & OpenSSH to Persistence Image"
        echo -e "  ${CYAN}[7]${RESET} 🩺 Run Host OBD Pre-Flight Health Audit"
        echo -e "\n  ${CYAN}[8]${RESET} 🚪 Exit"
        echo "======================================================================"

        local choice
        choice=$(prompt_choice "Select action [1-8]: " 1 8)

        case "$choice" in
            1)
                echo -e "\n[*] Launching QEMU VM Launcher..."
                sudo bash "${SCRIPT_DIR}/run_test_vm.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            2)
                echo -e "\n[*] Fast-launching Option B Direct Persistence VM via run_test_vm.sh..."
                sudo bash "${SCRIPT_DIR}/run_test_vm.sh" --boot 2
                read -rp "Press Enter to return to menu..." _
                ;;
            3)
                echo -e "\n[*] Executing Full Cumulative Automated Test Suite..."
                bash "${SCRIPT_DIR}/tests/harness/run_cumulative_suite.sh" "/tmp/cumulative_all_scripts"
                read -rp "Press Enter to return to menu..." _
                ;;
            4)
                echo -e "\n[*] Extracting and Merging Coverage Data..."
                bash "${SCRIPT_DIR}/extract_and_merge_coverage.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            5)
                manage_host_coverage_submenu
                ;;
            6)
                echo -e "\n[*] Deploying Four-Tier Redundancy & OpenSSH..."
                sudo bash "${SCRIPT_DIR}/deploy_four_tier_persistence.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            7)
                echo -e "\n[*] Running OBD Pre-Flight Check..."
                bash "${SCRIPT_DIR}/obd_preflight_check.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            8)
                echo -e "\nExiting Host Hub. Goodbye!"
                exit 0
                ;;
        esac
    done
}

main_menu
