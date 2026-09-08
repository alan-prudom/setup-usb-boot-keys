#!/usr/bin/env bash
# ==============================================================================
# run_with_coverage.sh
# Live USB Manual Testing Instrumentation Wrapper
# Designed to run in Rescuezilla Live / Ubuntu to record user sessions,
# capture line & branch coverage, record SHA256 source fingerprints for
# staleness detection, and store data in one folder per original script.
# ==============================================================================
set -euo pipefail

TARGET_SCRIPT="${1:-/scripts/run_rescuezilla_backup_cli.sh}"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "Error: Target script not found at '$TARGET_SCRIPT'" >&2
    exit 1
fi

SCRIPT_NAME=$(basename "$TARGET_SCRIPT" .sh)
SRC_REALPATH=$(realpath "$TARGET_SCRIPT")
SRC_SHA256=$(sha256sum "$SRC_REALPATH" | awk '{print $1}')
SRC_MTIME=$(stat -c %Y "$SRC_REALPATH" 2>/dev/null || echo "0")
SRC_LINES=$(wc -l < "$SRC_REALPATH" 2>/dev/null || echo "0")

# Detect base output directory on persistent partition or fallback to /tmp
BASE_DIR=""
for cand in "/home/ubuntu/ntfs_usb/live_coverage" "/media/ubuntu/2C95D29B2DF0500E/live_coverage" "/media/ubuntu/SHARED_FAT/live_coverage" "/tmp/live_coverage"; do
    parent=$(dirname "$cand")
    if [ -d "$parent" ] && [ -w "$parent" ]; then
        BASE_DIR="$cand"
        break
    fi
done

BASE_DIR="${BASE_DIR:-/tmp/live_coverage}"
SCRIPT_DIR="${BASE_DIR}/${SCRIPT_NAME}"
mkdir -p "$SCRIPT_DIR"

TRACE_LOG="${SCRIPT_DIR}/trace.log"
RAW_LOG="${SCRIPT_DIR}/session_transcript_raw.log"
CLEAN_LOG="${SCRIPT_DIR}/session_transcript_clean.txt"
META_FILE="${SCRIPT_DIR}/metadata.env"

touch "$TRACE_LOG" "$RAW_LOG"
chmod 666 "$TRACE_LOG" "$RAW_LOG" 2>/dev/null || true

echo "======================================================================"
echo "    🛡️ RESCUEZILLA LIVE MANUAL TEST & COVERAGE INSTRUMENTATION        "
echo "======================================================================"
echo "  • Target Script     : ${TARGET_SCRIPT}"
echo "  • Script Checksum   : ${SRC_SHA256:0:16}..."
echo "  • Script Output Dir : ${SCRIPT_DIR}"
echo "  • Transcript Target : ${CLEAN_LOG}"
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

# Record/Update Metadata fingerprint
cat << META_EOF > "$META_FILE"
SCRIPT_NAME="${SCRIPT_NAME}"
SCRIPT_PATH="${SRC_REALPATH}"
SCRIPT_SHA256="${SRC_SHA256}"
SCRIPT_MTIME="${SRC_MTIME}"
SCRIPT_LINES="${SRC_LINES}"
LAST_RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
META_EOF

echo -e "\n======================================================================"
echo "✓ Interactive Session Finished!"
echo "  • Clean Transcript  : ${CLEAN_LOG}"
echo "  • Raw Terminal Log  : ${RAW_LOG}"
echo "  • Trace Log File    : ${TRACE_LOG}"
echo "  • Script Metadata   : ${META_FILE}"

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
out_dir = "$SCRIPT_DIR"
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
        non_exec = {"fi", "done", "else", "do", "then", "esac", "{", "}", ";;", "in"}
        for lnum, code in enumerate(src_lines, start=1):
            code_strip = code.strip()
            if not code_strip or code_strip.startswith("#") or code_strip in non_exec:
                continue
            total_lines += 1
            hits = file_lines[fpath].get(lnum, 0)
            out.write(f"DA:{lnum},{hits}\n")
        hits_count = sum(1 for lnum in file_lines[fpath] if src_lines[lnum - 1].strip() not in non_exec and not src_lines[lnum - 1].strip().startswith("#"))
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

print(f"  • LCOV File Generated     : {lcov_path}")
PY_EOF

    if command -v genhtml >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/coverage.info" ]; then
        genhtml "${SCRIPT_DIR}/coverage.info" -o "${SCRIPT_DIR}/html" --branch-coverage --title "Live Manual Coverage: ${SCRIPT_NAME}" --legend || true
        echo "  • Browsable HTML Report   : ${SCRIPT_DIR}/html/index.html"
    fi
fi
echo "======================================================================"
