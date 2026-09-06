#!/usr/bin/env bash
# ==============================================================================
# run_with_coverage.sh
# Live USB Manual Testing Instrumentation Wrapper
# Designed to run in Rescuezilla Live / Ubuntu to record user sessions,
# capture line & branch coverage, and output browsable lcov HTML reports.
# ==============================================================================
set -euo pipefail

TARGET_SCRIPT="${1:-/scripts/run_rescuezilla_backup_cli.sh}"

# Detect output directory on persistent partition or fallback to /tmp
OUT_DIR=""
for cand in "/home/ubuntu/ntfs_usb/live_coverage" "/media/ubuntu/2C95D29B2DF0500E/live_coverage" "/media/ubuntu/SHARED_FAT/live_coverage" "/tmp/live_coverage"; do
    parent=$(dirname "$cand")
    if [ -d "$parent" ] && [ -w "$parent" ]; then
        OUT_DIR="$cand"
        break
    fi
done

OUT_DIR="${OUT_DIR:-/tmp/live_coverage}"
mkdir -p "$OUT_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
TRACE_LOG="${OUT_DIR}/trace_${TIMESTAMP}.log"
RAW_LOG="${OUT_DIR}/terminal_raw_${TIMESTAMP}.log"
CLEAN_LOG="${OUT_DIR}/terminal_clean_${TIMESTAMP}.txt"

touch "$TRACE_LOG" "$RAW_LOG"
chmod 666 "$TRACE_LOG" "$RAW_LOG"

echo "======================================================================"
echo "    🛡️ RESCUEZILLA LIVE MANUAL TEST & COVERAGE INSTRUMENTATION        "
echo "======================================================================"
echo "  • Target Script     : ${TARGET_SCRIPT}"
echo "  • Coverage Output   : ${OUT_DIR}"
echo "  • Raw Terminal Log  : ${RAW_LOG}"
echo "======================================================================"
echo -e "\nStarting session. Everything you type and see will be recorded.\n"
sleep 1

# Setup Bash tracing
COV_ENV="/tmp/live_cov_env_$$.sh"
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

# Run script interactively via script(1) to capture full terminal I/O
script -q -c "bash '$TARGET_SCRIPT'" "$RAW_LOG" || true

# Strip ANSI codes for clean human-readable review
sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' "$RAW_LOG" > "$CLEAN_LOG"

echo -e "\n======================================================================"
echo "✓ Interactive Session Finished!"
echo "  • Transcript (Clean Text) : ${CLEAN_LOG}"
echo "  • Transcript (Raw Log)    : ${RAW_LOG}"

# Compute coverage immediately using python3 or uv
PYTHON_BIN=""
if command -v uv >/dev/null 2>&1; then
    PYTHON_BIN="uv run python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
fi

if [ -n "$PYTHON_BIN" ]; then
    echo "[*] Generating lcov coverage report using $PYTHON_BIN..."
    $PYTHON_BIN - << PY_EOF
import re
import os

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
                if os.path.isfile(fpath) and not "tests" in fpath:
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
        out.write(f"LF:{total_lines}\nLH:{len(file_lines[fpath])}\n")

        branches = file_branches.get(fpath, [])
        if branches:
            br_hit_count = 0
            for lnum, brid, taken in branches:
                out.write(f"BRDA:{lnum},0,{brid},{taken}\n")
                if taken > 0:
                    br_hit_count += 1
            out.write(f"BRF:{len(branches)}\nBRH:{br_hit_count}\n")
        out.write("end_of_record\n")

print(f"  • LCOV File Generated     : {lcov_path}")
PY_EOF

    if command -v genhtml >/dev/null 2>&1 && [ -f "${OUT_DIR}/coverage.info" ]; then
        genhtml "${OUT_DIR}/coverage.info" -o "${OUT_DIR}/html" --branch-coverage --title "Live Manual Coverage" --legend || true
        echo "  • Browsable HTML Report   : ${OUT_DIR}/html/index.html"
    fi
fi
echo "======================================================================"
