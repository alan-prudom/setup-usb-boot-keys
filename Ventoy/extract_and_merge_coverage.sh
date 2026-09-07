#!/usr/bin/env bash
# ==============================================================================
# extract_and_merge_coverage.sh
# Finds, extracts, and merges live coverage data & terminal transcripts
# from Partition 4 (or running Rescuezilla VM) with local cumulative metrics.
# Supports the per-script folder structure with SHA256 staleness checking.
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
        cp -ra "${cand_p4}"/* "$LIVE_EXTRACT_DIR/" 2>/dev/null || true
        break
    fi
done

# 2. If not found on local mount, check running VM via SSH
if [ -z "$SOURCE_FOUND" ]; then
    if ssh -i /home/alan/.ssh/id_rsa -p 2222 -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@127.0.0.1 "true" 2>/dev/null; then
        echo -e "✓ Detected running Rescuezilla VM on SSH port 2222."
        echo "  • Fetching per-script coverage folders from VM Partition 4..."
        scp -r -i /home/alan/.ssh/id_rsa -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "ubuntu@127.0.0.1:/media/ubuntu/2C95D29B2DF0500E/live_coverage/*" "$LIVE_EXTRACT_DIR/" 2>/dev/null || \
        scp -r -i /home/alan/.ssh/id_rsa -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "ubuntu@127.0.0.1:/home/ubuntu/ntfs_usb/live_coverage/*" "$LIVE_EXTRACT_DIR/" 2>/dev/null || true
        SOURCE_FOUND="vm:ssh"
    fi
fi

if [ -z "$SOURCE_FOUND" ]; then
    echo -e "${YELLOW}Warning: Could not connect to Partition 4 or live VM.${RESET}"
    echo "Checking if prior extractions exist in $LIVE_EXTRACT_DIR..."
fi

echo -e "\n[*] Extracted Scripts / Artifacts in: ${CYAN}${LIVE_EXTRACT_DIR}${RESET}"
find "$LIVE_EXTRACT_DIR" -maxdepth 2

# 3. Locate all coverage.info files and re-base paths
LCOV_ARGS=()

# Find Base Cumulative Suite coverage.info
BASE_INFO=""
USER_NAME="${USER:-alan}"
for cand_base in \
    "${TARGET_DIR}/cumulative_coverage.info" \
    "/tmp/cumulative_${USER_NAME}_tests/coverage.info" \
    "/tmp/cumulative_all_scripts/coverage.info" \
    "/tmp/cumulative_coverage/coverage.info"; do
    if [ -f "$cand_base" ]; then
        BASE_INFO="$cand_base"
        break
    fi
done

if [ -z "$BASE_INFO" ]; then
    echo -e "\n[*] Base cumulative suite not cached. Generating base suite now..."
    local_test_out="/tmp/cumulative_${USER_NAME}_tests"
    bash "${SCRIPT_DIR}/tests/harness/run_cumulative_suite.sh" "$local_test_out"
    BASE_INFO="${local_test_out}/coverage.info"
fi

if [ -f "$BASE_INFO" ]; then
    LCOV_ARGS+=("-a" "$BASE_INFO")
fi

# Find all coverage.info files in per-script subdirectories or root
while IFS= read -r cov_file; do
    if [ -f "$cov_file" ]; then
        sed -i "s|/scripts/|${SCRIPT_DIR}/|g" "$cov_file"
        LCOV_ARGS+=("-a" "$cov_file")
    fi
done < <(find "$LIVE_EXTRACT_DIR" -type f -name "coverage.info")

# 4. Merge LCOV tracefiles
echo -e "\n[*] Merging automated test coverage with live manual runs..."
if [ "${#LCOV_ARGS[@]}" -gt 0 ]; then
    lcov --rc lcov_branch_coverage=1 "${LCOV_ARGS[@]}" -o "$MERGED_INFO"
else
    echo -e "${RED}Error: No coverage data found to merge.${RESET}"
    exit 1
fi

echo -e "\n======================================================================"
echo -e "${GREEN}✓ COVERAGE MERGE COMPLETE!${RESET}"
echo "======================================================================"
echo -e "  • Merged LCOV Data : ${CYAN}${MERGED_INFO}${RESET}"

# 5. Generate Browsable HTML Report
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
