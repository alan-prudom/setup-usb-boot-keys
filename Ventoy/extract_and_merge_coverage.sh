#!/usr/bin/env bash
# ==============================================================================
# extract_and_merge_coverage.sh
# Finds, extracts, and merges live coverage data & terminal transcripts
# from Partition 4 (or a running Rescuezilla QEMU VM) with local test metrics.
# ==============================================================================
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/tests/results"
LIVE_EXTRACT_DIR="${TARGET_DIR}/live_runs"
MERGED_INFO="${TARGET_DIR}/merged_cumulative_with_live.info"
MERGED_HTML="${TARGET_DIR}/merged_html"

mkdir -p "$LIVE_EXTRACT_DIR"

echo "======================================================================"
echo -e "${BOLD}      📥 RESCUEZILLA COVERAGE & TRANSCRIPT EXTRACTOR & MERGER        ${RESET}"
echo "======================================================================"

SOURCE_FOUND=""

# 1. Check direct physical mount of Partition 4 on host
for cand_p4 in \
    "/media/devmon/sdb4-usb-Generic-_SD_MMC_/live_coverage" \
    "/media/alan/2C95D29B2DF0500E/live_coverage" \
    "/media/alan/SHARED_FAT/live_coverage"; do
    if [ -d "$cand_p4" ] && [ -n "$(ls -A "$cand_p4" 2>/dev/null)" ]; then
        SOURCE_FOUND="dir:$cand_p4"
        echo -e "✓ Found local Partition 4 storage at: ${CYAN}${cand_p4}${RESET}"
        cp -v "${cand_p4}"/* "$LIVE_EXTRACT_DIR/" 2>/dev/null || true
        break
    fi
done

# 2. If not found on local mount, check running VM via SSH
if [ -z "$SOURCE_FOUND" ]; then
    if ssh -i /home/alan/.ssh/id_rsa -p 2222 -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@127.0.0.1 "true" 2>/dev/null; then
        echo -e "✓ Detected running Rescuezilla VM on SSH port 2222."
        echo "  • Fetching coverage files from VM Partition 4 (/media/ubuntu/2C95D29B2DF0500E/live_coverage)..."
        scp -i /home/alan/.ssh/id_rsa -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "ubuntu@127.0.0.1:/media/ubuntu/2C95D29B2DF0500E/live_coverage/*" "$LIVE_EXTRACT_DIR/" 2>/dev/null || \
        scp -i /home/alan/.ssh/id_rsa -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "ubuntu@127.0.0.1:/home/ubuntu/ntfs_usb/live_coverage/*" "$LIVE_EXTRACT_DIR/" 2>/dev/null || true
        SOURCE_FOUND="vm:ssh"
    fi
fi

if [ -z "$SOURCE_FOUND" ]; then
    echo -e "${YELLOW}Warning: Could not connect to Partition 4 or live VM.${RESET}"
    echo "Checking if prior extractions exist in $LIVE_EXTRACT_DIR..."
fi

echo -e "\n[*] Extracted Files in: ${CYAN}${LIVE_EXTRACT_DIR}${RESET}"
ls -lh "$LIVE_EXTRACT_DIR"

# 3. If coverage.info exists in extracted files, rebase guest paths to host paths
if [ -f "${LIVE_EXTRACT_DIR}/coverage.info" ]; then
    sed -i "s|/scripts/|${SCRIPT_DIR}/|g" "${LIVE_EXTRACT_DIR}/coverage.info"
fi

# 4. Locate Base Cumulative Suite coverage.info
BASE_INFO=""
for cand_base in \
    "${TARGET_DIR}/cumulative_coverage.info" \
    "/tmp/cumulative_all_scripts/coverage.info" \
    "/tmp/cumulative_coverage/coverage.info"; do
    if [ -f "$cand_base" ]; then
        BASE_INFO="$cand_base"
        break
    fi
done

if [ -z "$BASE_INFO" ]; then
    echo -e "\n[*] Base cumulative suite not cached. Generating base suite now..."
    bash "${SCRIPT_DIR}/tests/harness/run_cumulative_suite.sh" "/tmp/cumulative_all_scripts"
    BASE_INFO="/tmp/cumulative_all_scripts/coverage.info"
fi

# 5. Merge LCOV tracefiles
echo -e "\n[*] Merging automated test coverage with live manual runs..."
LCOV_ARGS=("-a" "$BASE_INFO")
if [ -f "${LIVE_EXTRACT_DIR}/coverage.info" ]; then
    LCOV_ARGS+=("-a" "${LIVE_EXTRACT_DIR}/coverage.info")
fi

lcov --rc lcov_branch_coverage=1 "${LCOV_ARGS[@]}" -o "$MERGED_INFO"

echo -e "\n======================================================================"
echo -e "${GREEN}✓ COVERAGE MERGE COMPLETE!${RESET}"
echo "======================================================================"
echo -e "  • Merged LCOV Data : ${CYAN}${MERGED_INFO}${RESET}"

# 6. Generate Browsable HTML Report
if command -v genhtml >/dev/null 2>&1; then
    mkdir -p "$MERGED_HTML"
    genhtml "$MERGED_INFO" \
        --output-directory "$MERGED_HTML" \
        --branch-coverage \
        --title "Combined Rescuezilla Automated & Live Test Coverage" \
        --legend \
        --show-details >/dev/null 2>&1 || true
    echo -e "  • Merged HTML View : ${CYAN}file://${MERGED_HTML}/index.html${RESET}"
fi

echo -e "\n--- Cumulative Summary ---"
lcov --rc lcov_branch_coverage=1 --summary "$MERGED_INFO"
echo "======================================================================"
