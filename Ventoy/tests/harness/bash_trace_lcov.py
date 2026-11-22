#!/usr/bin/env python3
import sys
import os
import subprocess
import tempfile
import re

def main():
    if len(sys.argv) < 3:
        print("Usage: bash_trace_lcov.py <out_dir> <script_or_command...>")
        sys.exit(1)

    out_dir = sys.argv[1]
    cmd = sys.argv[2:]
    os.makedirs(out_dir, exist_ok=True)

    trace_log = tempfile.NamedTemporaryFile(delete=False, prefix="bash_cov_", suffix=".log")
    trace_path = trace_log.name
    trace_log.close()

    env = os.environ.copy()
    # Format: @@COV@@<file>@@<line>@@
    env["PS4"] = "@@COV@@${BASH_SOURCE[0]}@@${LINENO}@@"
    env["BASH_XTRACEFD"] = "7"

    # Wrapper script that opens fd 7 to trace_path and turns on set -x
    wrapper = f"""#!/usr/bin/env bash
exec 7>"{trace_path}"
set -x
"$@"
"""
    with tempfile.NamedTemporaryFile("w", delete=False, prefix="runner_", suffix=".sh") as f:
        f.write(wrapper)
        runner_path = f.name
    os.chmod(runner_path, 0o755)

    try:
        proc = subprocess.run([runner_path] + cmd, env=env)
    finally:
        os.unlink(runner_path)

    # Parse trace log
    file_lines = {}
    with open(trace_path, "r", errors="ignore") as f:
        for line in f:
            m = re.search(r"@@COV@@([^@]+)@@([0-9]+)@@", line)
            if m:
                fpath = os.path.abspath(m.group(1))
                lineno = int(m.group(2))
                if os.path.isfile(fpath):
                    if fpath not in file_lines:
                        file_lines[fpath] = {}
                    file_lines[fpath][lineno] = file_lines[fpath].get(lineno, 0) + 1

    os.unlink(trace_path)

    # Emit standard lcov.info
    lcov_path = os.path.join(out_dir, "coverage.info")
    with open(lcov_path, "w") as out:
        for fpath, lines in file_lines.items():
            out.write(f"TN:\nSF:{fpath}\n")
            total_lines = 0
            with open(fpath, "r", errors="ignore") as src:
                src_lines = src.readlines()
            for lnum, code in enumerate(src_lines, start=1):
                code_strip = code.strip()
                # Skip comments and empty lines
                if not code_strip or code_strip.startswith("#"):
                    continue
                total_lines += 1
                hits = lines.get(lnum, 0)
                out.write(f"DA:{lnum},{hits}\n")
            hits_count = len(lines)
            out.write(f"LF:{total_lines}\nLH:{hits_count}\nend_of_record\n")

    print(f"\n[+] Trace Coverage successfully written to: {lcov_path}")
    print(f"  • Files Instrumented: {len(file_lines)}")
    for fp in file_lines:
        print(f"    - {fp}: {len(file_lines[fp])} executable lines hit")

if __name__ == "__main__":
    main()
