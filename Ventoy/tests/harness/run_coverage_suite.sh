#!/usr/bin/env bash
# ==============================================================================
# run_coverage_suite.sh
# Master Coverage Test Harness using kcov and expect
# Measures Line & Branch coverage across Rescuezilla / Ventoy scripts
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENTOY_DIR="$(cd "${TESTS_DIR}/.." && pwd)"

COV_OUT_DIR="${1:-${VENTOY_DIR}/coverage_results}"
mkdir -p "$COV_OUT_DIR"

echo "======================================================================"
echo "      🧪 RESCUEZILLA AUTOMATED TEST & COVERAGE RUNNER (kcov)          "
echo "======================================================================"
echo "  • Target Repository : ${VENTOY_DIR}"
echo "  • Coverage Output   : ${COV_OUT_DIR}"
echo "======================================================================"

# Discover and run all .exp test cases under kcov
for test_case in "${TESTS_DIR}/cases"/*.exp; do
    if [ -f "$test_case" ]; then
        tname=$(basename "$test_case" .exp)
        echo -e "\n[*] Executing Test Case: \033[1;36m${tname}\033[0m..."
        
        # Run expect driving the script under kcov
        kcov \
            --include-path="${VENTOY_DIR}" \
            --exclude-path="${TESTS_DIR}" \
            "${COV_OUT_DIR}" \
            expect "$test_case" "${VENTOY_DIR}/run_rescuezilla_backup_cli.sh"
    fi
done

echo -e "\n======================================================================"
echo "✓ Coverage Suite Completed!"
echo "  • Output directory: ${COV_OUT_DIR}"
if [ -f "${COV_OUT_DIR}/kcov.info" ]; then
    echo "  • lcov data file : ${COV_OUT_DIR}/kcov.info"
fi
echo "======================================================================"

# If genhtml is available, generate clean HTML report
if command -v genhtml >/dev/null 2>&1 && [ -f "${COV_OUT_DIR}/kcov.info" ]; then
    HTML_DIR="${COV_OUT_DIR}/html"
    mkdir -p "$HTML_DIR"
    echo "[*] Generating HTML coverage report into ${HTML_DIR}..."
    genhtml "${COV_OUT_DIR}/kcov.info" --output-directory "$HTML_DIR" --title "Rescuezilla Scripts Coverage" --legend || true
    echo "  • Browsable HTML : ${HTML_DIR}/index.html"
fi
