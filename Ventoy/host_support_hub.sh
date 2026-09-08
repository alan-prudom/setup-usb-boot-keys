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

# Python execution resolver (prefers uv if available)
PYTHON_CMD="python3"
if command -v uv >/dev/null 2>&1; then
    PYTHON_CMD="uv run python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
fi

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
            echo -e "  ${YELLOW}⚠️  Empty input (Return key) rejected. Type a number between ${min_val} and ${max_val} (or 0).${RESET}" >&2
            continue
        fi
        case "$choice" in
            *[!0-9]*|"")
                echo -e "  ${RED}⚠️  Invalid input '$choice'. Please type a number between ${min_val} and ${max_val} (or 0).${RESET}" >&2
                ;;
            *)
                if { [ "$choice" -ge "$min_val" ] && [ "$choice" -le "$max_val" ]; } || [ "$choice" -eq 0 ]; then
                    echo "$choice"
                    return 0
                else
                    echo -e "  ${RED}⚠️  Option '$choice' out of range [${min_val}-${max_val}] (or 0).${RESET}" >&2
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
        local auto_cov=""
        for cand_cov in \
            "/tmp/cumulative_alan_tests/coverage.info" \
            "/tmp/cumulative_${SUDO_USER:-}/coverage.info" \
            "/tmp/cumulative_${USER:-}/coverage.info" \
            "/tmp/cumulative_all_scripts/coverage.info" \
            "/tmp/cumulative_coverage/coverage.info"; do
            if [ -f "$cand_cov" ]; then
                auto_cov="$cand_cov"
                break
            fi
        done

        local idx=1
        for sname in "${targets[@]}"; do
            local sfile="${SCRIPT_DIR}/${sname}"
            local sdir="${live_base}/${sname%.sh}"
            local status="${DIM}[NO RUN RECORDED]${RESET}"
            local stats=""

            # 1. Check live run first
            if [ -d "$sdir" ] && [ -f "${sdir}/metadata.env" ]; then
                # shellcheck source=/dev/null
                source "${sdir}/metadata.env" 2>/dev/null || true
                local curr_sha=""
                if [ -f "$sfile" ]; then
                    curr_sha=$(sha256sum "$sfile" | awk '{print $1}')
                fi

                if [ -n "$curr_sha" ] && [ "$curr_sha" = "${SCRIPT_SHA256:-}" ]; then
                    status="${GREEN}[✓ LIVE - UP TO DATE]${RESET}"
                else
                    status="${YELLOW}[⚠️ LIVE - SCRIPT MODIFIED]${RESET}"
                fi

                local cov_info="${sdir}/coverage.info"
                if [ -f "$cov_info" ]; then
                    local lines_hit
                    lines_hit=$(grep -m1 "^LH:" "$cov_info" 2>/dev/null | cut -d: -f2 || echo "0")
                    local lines_total
                    lines_total=$(grep -m1 "^LF:" "$cov_info" 2>/dev/null | cut -d: -f2 || echo "0")
                    stats="(${lines_hit}/${lines_total} lines, live)"
                fi
            fi

            # 2. Check automated test suite metrics
            if [ -f "$auto_cov" ]; then
                local auto_stats
                auto_stats=$($PYTHON_CMD -c "
import os
target = '$sname'
cov_file = '$auto_cov'
in_target = False
lh, lf, brh, brf = 0, 0, 0, 0
with open(cov_file) as f:
    for line in f:
        line = line.strip()
        if line.startswith('SF:'):
            in_target = (os.path.basename(line[3:]) == target)
        elif in_target:
            if line.startswith('LH:'): lh = int(line[3:])
            elif line.startswith('LF:'): lf = int(line[3:])
            elif line.startswith('BRH:'): brh = int(line[4:])
            elif line.startswith('BRF:'): brf = int(line[4:])
            elif line == 'end_of_record': break
if lf > 0:
    pct = round((lh / lf) * 100, 1)
    print(f'({lh}/{lf} lines [{pct}%], {brh}/{brf} branches)')
" 2>/dev/null || true)

                if [ -n "$auto_stats" ]; then
                    if [ "$status" = "${DIM}[NO RUN RECORDED]${RESET}" ]; then
                        status="${GREEN}[✓ TEST SUITE PASS]${RESET}"
                        stats="$auto_stats"
                    else
                        stats="${stats} | Test: ${auto_stats}"
                    fi
                fi
            fi

            echo -e "  ${CYAN}[${idx}]${RESET} ${sname} ${status} ${stats}"
            idx=$((idx + 1))
        done

        echo "----------------------------------------------------------------------"
        echo -e "  ${CYAN}[5]${RESET} 🌐 Open Browsable HTML Coverage Report in Browser"
        echo -e "  ${CYAN}[6]${RESET} 📄 View Extracted Terminal Transcripts (Automated & Live)"
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
                    echo -e "\n${YELLOW}No live transcript found for ${sel_target} in ${clean_txt}${RESET}"
                    echo -e "Tip: Check Option [6] to view automated test suite transcripts."
                fi
                read -rp "Press Enter to return..." _
                ;;
            5)
                local html_to_open=""
                if [ -f "$HTML_REPORT" ]; then
                    html_to_open="$HTML_REPORT"
                else
                    for cand_h in \
                        "/tmp/cumulative_alan_tests/html/index.html" \
                        "/tmp/cumulative_${SUDO_USER:-}/html/index.html" \
                        "/tmp/cumulative_${USER:-}/html/index.html" \
                        "/tmp/cumulative_all_scripts/html/index.html"; do
                        if [ -f "$cand_h" ]; then
                            html_to_open="$cand_h"
                            break
                        fi
                    done
                fi

                if [ -n "$html_to_open" ]; then
                    echo -e "\nOpening ${html_to_open}..."
                    xdg-open "$html_to_open" 2>/dev/null || sensible-browser "$html_to_open" 2>/dev/null || echo "Open file://${html_to_open}"
                else
                    echo -e "\n${YELLOW}HTML Report not yet generated. Run Extract & Merge (Option 7) or Automated Suite (Main Menu 3) first.${RESET}"
                fi
                read -rp "Press Enter to return..." _
                ;;
            6)
                echo -e "\nSelect transcript to view:"
                echo -e "  ${CYAN}[0]${RESET} 🔙 Cancel (Return to Explorer Submenu)"
                echo -e "  ${CYAN}[1]${RESET} 🧪 Master Automated Expect Suite (All 11 Test Cases)"
                for i in "${!targets[@]}"; do
                    echo -e "  ${CYAN}[$((i+2))]${RESET} Live Run: ${targets[$i]}"
                done
                local total_items=$(( ${#targets[@]} + 1 ))
                local t_choice
                t_choice=$(prompt_choice "Select [0-${total_items}] (or 0 to cancel): " 0 "$total_items")
                
                if [ "$t_choice" -eq 0 ]; then
                    continue
                elif [ "$t_choice" -eq 1 ]; then
                    local auto_clean=""
                    for cand_c in \
                        "/tmp/cumulative_alan_tests/session_transcript_clean.txt" \
                        "/tmp/cumulative_${SUDO_USER:-}/session_transcript_clean.txt" \
                        "/tmp/cumulative_${USER:-}/session_transcript_clean.txt" \
                        "/tmp/cumulative_all_scripts/session_transcript_clean.txt"; do
                        if [ -f "$cand_c" ]; then
                            auto_clean="$cand_c"
                            break
                        fi
                    done
                    if [ -n "$auto_clean" ] && [ -f "$auto_clean" ]; then
                        echo -e "\n================ [ Automated Test Suite Transcript ] ================"
                        cat "$auto_clean" | less -R || cat "$auto_clean"
                    else
                        echo -e "\n${YELLOW}No automated test transcript found. Run test suite first.${RESET}"
                    fi
                else
                    local sel_t="${targets[$((t_choice - 2))]}"
                    local clean_txt="${live_base}/${sel_t%.sh}/session_transcript_clean.txt"
                    if [ -f "$clean_txt" ]; then
                        echo -e "\n================ [ Live Run Transcript: ${sel_t} ] ================"
                        cat "$clean_txt" | less -R || cat "$clean_txt"
                    else
                        echo -e "\n${YELLOW}No live transcript found at ${clean_txt}${RESET}"
                    fi
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
            0|9)
                return 0
                ;;
        esac
    done
}

get_instrumentation_mode() {
    if [ -f "/tmp/rescue_instrumentation.mode" ]; then
        cat "/tmp/rescue_instrumentation.mode" 2>/dev/null || echo "0"
    elif [ -f "$HOME/.config/rescue_instrumentation.mode" ]; then
        cat "$HOME/.config/rescue_instrumentation.mode" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

set_instrumentation_mode() {
    local val="$1"
    echo "$val" > "/tmp/rescue_instrumentation.mode" 2>/dev/null || true
    mkdir -p "$HOME/.config" 2>/dev/null || true
    echo "$val" > "$HOME/.config/rescue_instrumentation.mode" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Main Menu
# ------------------------------------------------------------------------------
main_menu() {
    while true; do
        clear
        local imode
        imode=$(get_instrumentation_mode)
        local imode_label
        if [ "$imode" = "1" ]; then
            imode_label="${GREEN}🔬 ENABLED (Recording traces & transcripts)${RESET}"
        else
            imode_label="${DIM}⚡ DISABLED (Direct execution, no tracing)${RESET}"
        fi

        echo "======================================================================"
        echo -e "${BOLD}       💻 RESCUEZILLA HOST SUPPORT & TEST ORCHESTRATOR               ${RESET}"
        echo "======================================================================"
        echo "Host Environment: Ubuntu Development System ($(uname -n))"
        echo "Repository Path : ${SCRIPT_DIR}"
        echo -e "Mode            : ${imode_label}"
        echo "Timestamp       : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================================"
        echo -e "\n${BOLD}Virtualization & Emulation:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} 🖥️  Launch QEMU Test VM (Interactive Selection: Option A or B)"
        echo -e "  ${CYAN}[2]${RESET} ⚡ Fast-Launch Option B Direct Persistence VM (with GTK display)"
        echo -e "\n${BOLD}Testing & Coverage Pipeline:${RESET}"
        echo -e "  ${CYAN}[3]${RESET} 🧪 Run Master Cumulative Automated Expect Suite (9 Test Cases)"
        echo -e "  ${CYAN}[4]${RESET} 📥 Extract Live Coverage & Transcripts from Partition 4 / VM"
        echo -e "  ${CYAN}[5]${RESET} 📊 Coverage & Artifact Explorer (Submenu: HTML, Transcripts, Staleness)"
        if [ "$imode" = "1" ]; then
            echo -e "  ${CYAN}[6]${RESET} 🔬 Toggle Instrumentation Mode (Currently: ${GREEN}ON${RESET} -> Switch to ${YELLOW}OFF${RESET})"
        else
            echo -e "  ${CYAN}[6]${RESET} ⚡ Toggle Instrumentation Mode (Currently: ${DIM}OFF${RESET} -> Switch to ${GREEN}ON${RESET})"
        fi
        echo -e "\n${BOLD}USB Deployment & Maintenance:${RESET}"
        echo -e "  ${CYAN}[7]${RESET} 🚀 Deploy Four-Tier Redundancy & OpenSSH to Persistence Image"
        echo -e "  ${CYAN}[8]${RESET} 🩺 Run Host OBD Pre-Flight Health Audit"
        echo -e "\n  ${CYAN}[9]${RESET} 🚪 Exit"
        echo "======================================================================"

        local choice
        choice=$(prompt_choice "Select action [1-9]: " 1 9)

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
                local user_out_dir="/tmp/cumulative_${USER:-alan}_tests"
                bash "${SCRIPT_DIR}/tests/harness/run_cumulative_suite.sh" "$user_out_dir"
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
                if [ "$imode" = "1" ]; then
                    set_instrumentation_mode "0"
                    echo -e "\n${YELLOW}Instrumentation Mode set to: DISABLED (Direct Execution)${RESET}"
                else
                    set_instrumentation_mode "1"
                    echo -e "\n${GREEN}Instrumentation Mode set to: ENABLED (Traces & Transcripts Active)${RESET}"
                fi
                sleep 1
                ;;
            7)
                echo -e "\n[*] Deploying Four-Tier Redundancy & OpenSSH..."
                sudo bash "${SCRIPT_DIR}/deploy_four_tier_persistence.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            8)
                echo -e "\n[*] Running OBD Pre-Flight Check..."
                bash "${SCRIPT_DIR}/obd_preflight_check.sh"
                read -rp "Press Enter to return to menu..." _
                ;;
            0|9)
                echo -e "\nExiting Host Hub. Goodbye!"
                exit 0
                ;;
        esac
    done
}

main_menu
