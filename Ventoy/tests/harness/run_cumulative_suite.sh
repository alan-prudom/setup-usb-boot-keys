#!/usr/bin/env bash
# ==============================================================================
# run_cumulative_suite.sh
# Runs all expect test cases, aggregates coverage, captures all transcripts,
# and generates merged lcov & HTML reports with branch coverage.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENTOY_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
OUT_DIR="${1:-${VENTOY_DIR}/coverage_results}"

mkdir -p "$OUT_DIR"
MASTER_TRACE="${OUT_DIR}/master_trace.log"
TRANSCRIPT_RAW="${OUT_DIR}/session_transcript_raw.log"
TRANSCRIPT_CLEAN="${OUT_DIR}/session_transcript_clean.txt"

rm -f "$MASTER_TRACE" "$TRANSCRIPT_RAW" "$TRANSCRIPT_CLEAN"
touch "$MASTER_TRACE" "$TRANSCRIPT_RAW"
chmod 666 "$MASTER_TRACE" "$TRANSCRIPT_RAW"

echo "======================================================================"
echo "    🧪 MASTER CUMULATIVE TEST & BRANCH COVERAGE SUITE (uv + expect)   "
echo "======================================================================"
echo "  • Tests Directory : ${TESTS_DIR}/cases"
echo "  • Output Directory: ${OUT_DIR}"
echo "======================================================================"

# Global environment file loaded by subshells
COV_ENV="/tmp/master_cov_env_$$.sh"
cat << ENV_EOF > "$COV_ENV"
export PS4='@@COV@@\${BASH_SOURCE[0]}@@\${LINENO}@@\n'
exec 7>>"$MASTER_TRACE"
export BASH_XTRACEFD=7
set -x
ENV_EOF
chmod 644 "$COV_ENV"
export BASH_ENV="$COV_ENV"

cleanup() {
    rm -f "$COV_ENV" 2>/dev/null || true
}
trap cleanup EXIT

# Run each test case sequentially
for test_file in "${TESTS_DIR}/cases"/*.exp; do
    if [ -f "$test_file" ]; then
        tname=$(basename "$test_file")
        echo -e "\n[*] Running: \033[1;36m${tname}\033[0m..."
        {
            echo "======================================================================"
            echo ">>> TEST RUN: ${tname} [$(date '+%Y-%m-%d %H:%M:%S')]"
            echo "======================================================================"
            expect "$test_file"
            echo ""
        } >> "$TRANSCRIPT_RAW" 2>&1
        echo "    ✓ ${tname} passed."
    fi
done

# Generate clean text transcript
sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' "$TRANSCRIPT_RAW" > "$TRANSCRIPT_CLEAN"
echo -e "\n[+] Full Terminal Transcripts Saved:"
echo "  • Raw Terminal Log   : ${TRANSCRIPT_RAW}"
echo "  • Clean Text for Review: ${TRANSCRIPT_CLEAN}"

echo -e "\n[*] Calculating cumulative line & branch coverage using uv..."
uv run python - << PY_EOF
import re
import os

trace_path = "$MASTER_TRACE"
out_dir = "$OUT_DIR"
file_lines = {}
file_branches = {}

if os.path.exists(trace_path):
    with open(trace_path, "r", errors="ignore") as f:
        for line in f:
            m = re.search(r"@@COV@@([^@]+)@@([0-9]+)@@", line)
            if m:
                fpath = os.path.abspath(m.group(1))
                lineno = int(m.group(2))
                if os.path.isfile(fpath) and "Ventoy" in fpath and not "tests" in fpath:
                    if fpath not in file_lines:
                        file_lines[fpath] = {}
                    file_lines[fpath][lineno] = file_lines[fpath].get(lineno, 0) + 1

for fpath in list(file_lines.keys()):
    try:
        with open(fpath, "r", errors="ignore") as src:
            src_lines = src.readlines()
    except Exception:
        continue

    branches = []
    executed = set(file_lines[fpath].keys())
    in_case = False
    branch_num = 0

    for idx, raw_line in enumerate(src_lines, start=1):
        line = raw_line.strip()
        if line.startswith("if ") or line.startswith("if [") or line.startswith("elif ") or line.startswith("elif ["):
            next_idx = idx + 1
            while next_idx <= len(src_lines) and not src_lines[next_idx - 1].strip():
                next_idx += 1
            then_hit = 1 if (idx in executed and next_idx in executed) else 0
            else_hit = 1 if (idx in executed and not then_hit) else (1 if idx in executed else 0)
            branches.append((idx, 0, then_hit))
            branches.append((idx, 1, else_hit))
        elif line.startswith("case ") and " in" in line:
            in_case = True
            branch_num = 0
        elif in_case and line == "esac":
            in_case = False
        elif in_case and re.match(r"^[a-zA-Z0-9_*| -]+\)", line):
            arm_hit = 1 if idx in executed else 0
            branches.append((idx, branch_num, arm_hit))
            branch_num += 1

    file_branches[fpath] = branches

lcov_path = os.path.join(out_dir, "coverage.info")
with open(lcov_path, "w") as out:
    for fpath in file_lines:
        out.write(f"TN:\nSF:{fpath}\n")
        with open(fpath, "r", errors="ignore") as src:
            src_lines = src.readlines()
        total_lines = 0
        for lnum, code in enumerate(src_lines, start=1):
            code_strip = code.strip()
            if not code_strip or code_strip.startswith("#"):
                continue
            total_lines += 1
            hits = file_lines[fpath].get(lnum, 0)
            out.write(f"DA:{lnum},{hits}\n")
        hits_count = len(file_lines[fpath])
        out.write(f"LF:{total_lines}\nLH:{hits_count}\n")

        branches = file_branches.get(fpath, [])
        if branches:
            br_hit_count = 0
            for lnum, brid, taken in branches:
                out.write(f"BRDA:{lnum},0,{brid},{taken}\n")
                if taken > 0:
                    br_hit_count += 1
            out.write(f"BRF:{len(branches)}\nBRH:{br_hit_count}\n")
        out.write("end_of_record\n")

print(f"\n[+] Cumulative Coverage Report Generated: {lcov_path}")
for fp in sorted(file_lines.keys()):
    br_list = file_branches.get(fp, [])
    br_hits = sum(1 for _, _, taken in br_list if taken > 0)
    print(f"  • {os.path.basename(fp)}: {len(file_lines[fp])} lines, {br_hits}/{len(br_list)} branches covered")

PY_EOF

# Generate HTML report
if command -v genhtml >/dev/null 2>&1 && [ -f "${OUT_DIR}/coverage.info" ]; then
    HTML_DIR="${OUT_DIR}/html"
    mkdir -p "$HTML_DIR"
    echo -e "\n[*] Generating HTML coverage report with Branch Coverage enabled..."
    genhtml "${OUT_DIR}/coverage.info" \
        --output-directory "$HTML_DIR" \
        --title "Cumulative Rescuezilla Coverage" \
        --branch-coverage \
        --legend \
        --show-details || true
    echo "  • Browsable HTML : ${HTML_DIR}/index.html"
fi
