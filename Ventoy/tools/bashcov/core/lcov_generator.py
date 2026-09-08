#!/usr/bin/env python3
"""
bashcov.core.lcov_generator
===========================
Universal, general-purpose LCOV generator for Bash execution traces.

Features:
- Reads xtrace formatted files (PS4='@@COV@@${BASH_SOURCE[0]}@@${LINENO}@@\n')
- Cumulative hit frequency tracking (DA:<lineno>,<count>)
- AST / Regex function scanning to emit FN, FNDA, FNF, FNH
- Branch tracking for if/elif and case constructs (BRDA, BRF, BRH)
- Configurable non-executable token exclusion (fi, done, else, esac, ;;, etc.)
- Normalization to canonical realpaths to prevent split directories in genhtml
"""

import os
import re
from typing import Dict, List, Set, Tuple


class LcovGenerator:
    DEFAULT_NON_EXEC = {"fi", "done", "else", "do", "then", "esac", "{", "}", ";;", "in"}

    def __init__(
        self,
        trace_path: str,
        source_paths: List[str],
        exclude_tokens: Set[str] = None,
        path_filter: str = ""
    ):
        self.trace_path = trace_path
        self.source_paths = [os.path.abspath(p) for p in source_paths]
        self.exclude_tokens = exclude_tokens or self.DEFAULT_NON_EXEC
        self.path_filter = path_filter
        self.file_lines: Dict[str, Dict[int, int]] = {}
        self.file_branches: Dict[str, List[Tuple[int, int, int]]] = {}
        self.file_functions: Dict[str, List[Tuple[int, str]]] = {}

    def parse_trace(self) -> None:
        """Parses the trace log and aggregates execution frequencies."""
        if not os.path.exists(self.trace_path):
            return

        with open(self.trace_path, "r", errors="ignore") as f:
            for line in f:
                m = re.search(r"@@COV@@([^@]+)@@([0-9]+)@@", line)
                if m:
                    fpath = os.path.abspath(m.group(1))
                    lineno = int(m.group(2))
                    if os.path.isfile(fpath):
                        if self.path_filter and self.path_filter not in fpath:
                            continue
                        if "tests" in fpath:
                            continue
                        if fpath not in self.file_lines:
                            self.file_lines[fpath] = {}
                        self.file_lines[fpath][lineno] = self.file_lines[fpath].get(lineno, 0) + 1

        # Also initialize any specified source files even if they had 0 hits
        for spath in self.source_paths:
            if os.path.isfile(spath) and spath not in self.file_lines:
                if not self.path_filter or self.path_filter in spath:
                    if "tests" not in spath:
                        self.file_lines[spath] = {}

    def analyze_structure(self) -> None:
        """Analyzes source file lines to discover branches and functions."""
        for fpath in list(self.file_lines.keys()):
            try:
                with open(fpath, "r", errors="ignore") as src:
                    src_lines = src.readlines()
            except Exception:
                continue

            branches = []
            executed = set(self.file_lines[fpath].keys())
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

            self.file_branches[fpath] = branches

            # Discover function declarations
            funcs = []
            for idx, raw_line in enumerate(src_lines, start=1):
                m = re.match(r"^([a-zA-Z0-9_-]+)\s*\(\)\s*\{?", raw_line.strip())
                if not m:
                    m = re.match(r"^function\s+([a-zA-Z0-9_-]+)\s*(?:\{\s*)?$", raw_line.strip())
                if m:
                    funcs.append((idx, m.group(1)))
            self.file_functions[fpath] = funcs

    def write_lcov(self, out_path: str) -> None:
        """Writes standard LCOV file."""
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as out:
            for fpath in sorted(self.file_lines.keys()):
                out.write(f"TN:\nSF:{fpath}\n")
                try:
                    with open(fpath, "r", errors="ignore") as src:
                        src_lines = src.readlines()
                except Exception:
                    continue

                funcs = self.file_functions.get(fpath, [])
                func_headers = {lnum for lnum, _ in funcs}
                fn_hits = 0
                for lnum, fname in funcs:
                    body_hit = 0
                    for test_ln in range(lnum + 1, min(lnum + 15, len(src_lines) + 1)):
                        if test_ln in self.file_lines[fpath]:
                            body_hit = self.file_lines[fpath][test_ln]
                            break
                    out.write(f"FN:{lnum},{fname}\n")
                    out.write(f"FNDA:{body_hit},{fname}\n")
                    if body_hit > 0:
                        fn_hits += 1

                if funcs:
                    out.write(f"FNF:{len(funcs)}\nFNH:{fn_hits}\n")

                total_lines = 0
                for lnum, code in enumerate(src_lines, start=1):
                    code_strip = code.strip()
                    if not code_strip or code_strip.startswith("#") or code_strip in self.exclude_tokens or lnum in func_headers:
                        continue
                    total_lines += 1
                    hits = self.file_lines[fpath].get(lnum, 0)
                    out.write(f"DA:{lnum},{hits}\n")

                hits_count = sum(
                    1 for lnum in self.file_lines[fpath]
                    if src_lines[lnum - 1].strip() not in self.exclude_tokens
                    and not src_lines[lnum - 1].strip().startswith("#")
                    and lnum not in func_headers
                )
                out.write(f"LF:{total_lines}\nLH:{hits_count}\n")

                branches = self.file_branches.get(fpath, [])
                if branches:
                    br_hit_count = 0
                    for lnum, brid, taken in branches:
                        out.write(f"BRDA:{lnum},0,{brid},{taken}\n")
                        if taken > 0:
                            br_hit_count += 1
                    out.write(f"BRF:{len(branches)}\nBRH:{br_hit_count}\n")

                out.write("end_of_record\n")
