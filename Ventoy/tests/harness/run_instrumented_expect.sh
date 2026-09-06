#!/usr/bin/env bash
# ==============================================================================
# run_instrumented_expect.sh
# Instruments Bash scripts via BASH_ENV & BASH_XTRACEFD to output lcov info
# ==============================================================================
set -euo pipefail

OUT_DIR="${1:-/tmp/live_coverage_branch}"
EXP_SCRIPT="${2:-Ventoy/tests/cases/test_backup_cli_prompts.exp}"

mkdir -p "$OUT_DIR"
TRACE_LOG="/tmp/bash_cov_trace_$$.log"
RAW_TERMINAL_LOG="${OUT_DIR}/terminal_output_raw.log"
CLEAN_TERMINAL_LOG="${OUT_DIR}/terminal_output_clean.txt"

rm -f "$TRACE_LOG" "$RAW_TERMINAL_LOG" "$CLEAN_TERMINAL_LOG"
touch "$TRACE_LOG"
chmod 666 "$TRACE_LOG"

COV_ENV="/tmp/cov_env_$$.sh"
cat << ENV_EOF > "$COV_ENV"
export PS4='@@COV@@\${BASH_SOURCE[0]}@@\${LINENO}@@\n'
exec 7>>"$TRACE_LOG"
export BASH_XTRACEFD=7
set -x
ENV_EOF
chmod 644 "$COV_ENV"

export BASH_ENV="$COV_ENV"

cleanup() {
    rm -f "$COV_ENV" 2>/dev/null || true
}
trap cleanup EXIT

echo "======================================================================"
echo "    🧪 RESCUEZILLA TEST & COVERAGE RUNNER (LCOV + BRANCH COVERAGE)    "
echo "======================================================================"
echo "  • Expect Script : ${EXP_SCRIPT}"
echo "  • Output Dir    : ${OUT_DIR}"
echo "======================================================================"

echo -e "\n[*] Executing test case and recording terminal output transcript..."
# Run expect directly, redirecting output to raw terminal log
expect "$EXP_SCRIPT" > "$RAW_TERMINAL_LOG" 2>&1 || true

# Display the transcript
cat "$RAW_TERMINAL_LOG"

# Produce clean, human-readable text output without ANSI escape codes
sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' "$RAW_TERMINAL_LOG" > "$CLEAN_TERMINAL_LOG"
echo -e "\n[+] Terminal Output Saved:"
echo "  • Raw Terminal Transcript  : ${RAW_TERMINAL_LOG}"
echo "  • Clean Text for Review    : ${CLEAN_TERMINAL_LOG}"

echo -e "\n[*] Processing line & branch coverage records using uv..."
uv run python - << PY_EOF
import re
import os
import sys

trace_path = "$TRACE_LOG"
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
                        file_lines[fpath] = set()
                    file_lines[fpath].add(lineno)

for fpath in list(file_lines.keys()):
    try:
        with open(fpath, "r", errors="ignore") as src:
            src_lines = src.readlines()
    except Exception:
        continue

    branches = []
    executed = file_lines[fpath]

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
            hits = 1 if lnum in file_lines[fpath] else 0
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

print(f"\n[+] LCOV Coverage Report Generated: {lcov_path}")
for fp in file_lines:
    br_list = file_branches.get(fp, [])
    br_hits = sum(1 for _, _, taken in br_list if taken > 0)
    print(f"  • {os.path.basename(fp)}: {len(file_lines[fp])} lines, {br_hits}/{len(br_list)} branches covered")

PY_EOF

rm -f "$TRACE_LOG" 2>/dev/null || true

if command -v genhtml >/dev/null 2>&1 && [ -f "${OUT_DIR}/coverage.info" ]; then
    HTML_DIR="${OUT_DIR}/html"
    mkdir -p "$HTML_DIR"
    echo -e "\n[*] Generating HTML coverage report with Branch Coverage enabled..."
    genhtml "${OUT_DIR}/coverage.info" \
        --output-directory "$HTML_DIR" \
        --title "Rescuezilla Scripts Coverage" \
        --branch-coverage \
        --legend \
        --show-details || true
    echo "  • Browsable HTML : ${HTML_DIR}/index.html"
fi
