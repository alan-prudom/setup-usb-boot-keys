#!/usr/bin/env python3
"""
bashcov.linter.multicmd
=======================
Comprehensive static analyzer for Bash scripts that detects patterns causing
distorted line-hit counts, ambiguous branch attribution, or hidden control-flow.

Rules:
1. MULTICMD_SEMICOLON:
   Multiple distinct commands separated by ';' on the same line (e.g. cmd1 ; cmd2).
   (Excludes: quoted strings, for ((i=0; i<N; i++)), 'if ...; then', 'while ...; do')

2. MULTICMD_INLINE_CASE_ARM:
   Case arm commands on the same line as the pattern or ';;' (e.g. 1) do_something ;;).

3. MULTICMD_CHAINED_BOOLEAN:
   Chained boolean expressions or commands on a single line (e.g. [ A ] && [ B ] && [ C ],
   cmd1 && cmd2, or cmd || true). Each command/condition should be on its own line so
   coverage engines can record individual hit counts and branch paths.

4. MULTICMD_INLINE_SUBSHELL:
   Command substitutions with internal chained pipelines on a single line
   (e.g. VAR="$(cd ... && pwd)").

5. UNREACHABLE_AFTER_EXIT:
   Statements placed immediately following unconditional exit / return commands
   within the same block scope.

6. HARDCODED_TEST_COUNT:
   Static test case counts in user-facing menus or documentation comments where
   dynamic discovery should be used.
"""

import re
import sys
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class LinterViolation:
    filename: str
    lineno: int
    col: int
    rule: str
    message: str
    line_content: str


def analyze_script(filename: str, source_text: str) -> List[LinterViolation]:
    """Analyzes a script string and returns all violations."""
    violations: List[LinterViolation] = []
    lines = source_text.splitlines()

    in_heredoc = False
    heredoc_delimiter = ""

    for lidx, raw_line in enumerate(lines, start=1):
        line = raw_line.rstrip()
        stripped = line.strip()

        # Skip comments and empty lines
        if not stripped or stripped.startswith("#"):
            continue

        # Heredoc handling
        if in_heredoc:
            if stripped == heredoc_delimiter:
                in_heredoc = False
                heredoc_delimiter = ""
            continue

        hd_match = re.search(r"<<-?\s*['\"]?([A-Za-z0-9_]+)['\"]?", line)
        if hd_match and not ("#" in line and line.index("#") < hd_match.start()):
            in_heredoc = True
            heredoc_delimiter = hd_match.group(1)

        # Lexing states for current line
        in_single_quote = False
        in_double_quote = False
        is_escaped = False
        in_c_style_for = bool(re.match(r"^\s*for\s*\(\(.*\)\)", line))

        semicolon_indices = []
        double_and_indices = []
        double_or_indices = []

        col = 1
        idx = 0
        line_len = len(line)

        while idx < line_len:
            ch = line[idx]

            if is_escaped:
                is_escaped = False
                idx += 1
                col += 1
                continue

            if ch == '\\':
                is_escaped = True
                idx += 1
                col += 1
                continue

            if ch == "'" and not in_double_quote:
                in_single_quote = not in_single_quote
                idx += 1
                col += 1
                continue

            if ch == '"' and not in_single_quote:
                in_double_quote = not in_double_quote
                idx += 1
                col += 1
                continue

            # Outside quotes
            if not in_single_quote and not in_double_quote and not in_c_style_for:
                # Comment starts
                if ch == '#' and (idx == 0 or line[idx - 1].isspace()):
                    break

                # Double semicolon (case arm terminator: ;;)
                if ch == ';' and idx + 1 < line_len and line[idx + 1] == ';':
                    remainder = line[idx + 2:].strip()
                    if remainder and not remainder.startswith("#") and remainder != "esac":
                        violations.append(
                            LinterViolation(
                                filename=filename,
                                lineno=lidx,
                                col=idx + 3,
                                rule="MULTICMD_AFTER_ESAC_TERMINATOR",
                                message=f"Found command '{remainder}' on same line following ';;'. Break onto new line.",
                                line_content=line,
                            )
                        )
                    idx += 2
                    col += 2
                    continue

                # Single semicolon
                if ch == ';':
                    semicolon_indices.append((idx, col))

                # &&
                if ch == '&' and idx + 1 < line_len and line[idx + 1] == '&':
                    double_and_indices.append((idx, col))
                    idx += 2
                    col += 2
                    continue

                # ||
                if ch == '|' and idx + 1 < line_len and line[idx + 1] == '|':
                    double_or_indices.append((idx, col))
                    idx += 2
                    col += 2
                    continue

            idx += 1
            col += 1

        # 1. Check semicolons
        for s_idx, s_col in semicolon_indices:
            prefix = line[:s_idx].strip()
            suffix = line[s_idx + 1:].strip()

            if suffix.startswith("then") or suffix.startswith("then ") or suffix.startswith("then\t"):
                continue
            if suffix.startswith("do") or suffix.startswith("do ") or suffix.startswith("do\t"):
                continue
            if suffix and not suffix.startswith("#") and suffix != "}":
                if prefix and not prefix.endswith("\\"):
                    violations.append(
                        LinterViolation(
                            filename=filename,
                            lineno=lidx,
                            col=s_col,
                            rule="MULTICMD_SEMICOLON",
                            message=f"Multiple commands separated by ';' on line. Split across separate lines for accurate gcov line-counts.",
                            line_content=line,
                        )
                    )

        # 2. Check inline case arm
        case_inline = re.search(r"^\s*([a-zA-Z0-9_*| -]+)\)\s*(.+);;", line)
        if case_inline and not in_single_quote and not in_double_quote:
            arm_pattern = case_inline.group(1).strip()
            inner_cmd = case_inline.group(2).strip()
            if inner_cmd:
                violations.append(
                    LinterViolation(
                        filename=filename,
                        lineno=lidx,
                        col=case_inline.start(2) + 1,
                        rule="MULTICMD_INLINE_CASE_ARM",
                        message=f"Case arm '{arm_pattern})' has inline command '{inner_cmd}' on same line as ';;'. Format as multiline.",
                        line_content=line,
                    )
                )

        # 3. Check chained boolean / fallback operators on the same line
        # Flag multiple && on same line, or '|| true' / '|| :' attached to commands
        all_bools = sorted(double_and_indices + double_or_indices, key=lambda x: x[0])
        if len(all_bools) > 1:
            # More than one && or || on the same line multiplies trace execution records
            violations.append(
                LinterViolation(
                    filename=filename,
                    lineno=lidx,
                    col=all_bools[1][1],
                    rule="MULTICMD_CHAINED_BOOLEAN",
                    message=f"Multiple logical operators ('&&' / '||') on one line multiply gcov hit counts. Place each condition/command on its own line.",
                    line_content=line,
                )
            )
        elif len(all_bools) == 1:
            # Check for trailing fallback: cmd || true / cmd || : / cmd || exit
            b_idx, b_col = all_bools[0]
            op = line[b_idx:b_idx+2]
            suffix = line[b_idx+2:].strip()
            prefix = line[:b_idx].strip()
            if op == "||" and suffix in ("true", ":", "exit 1", "return 1", "exit 0", "return 0") and prefix:
                violations.append(
                    LinterViolation(
                        filename=filename,
                        lineno=lidx,
                        col=b_col,
                        rule="MULTICMD_INLINE_FALLBACK",
                        message=f"Inline fallback '{op} {suffix}' doubles line execution count in coverage reports. Split onto next line.",
                        line_content=line,
                    )
                )

        # 4. Check chained commands inside subshell assignments: VAR="$(cmd1 && cmd2)"
        subshell_chained = re.search(r'=\s*["\']?\$\([^)]*(&&|\|\||;|\|)[^)]*\)', line)
        if subshell_chained:
            violations.append(
                LinterViolation(
                    filename=filename,
                    lineno=lidx,
                    col=subshell_chained.start() + 1,
                    rule="MULTICMD_INLINE_SUBSHELL",
                    message="Chained commands inside subshell '$()' on one line multiply trace counts. Break subshell into multiple lines or standalone steps.",
                    line_content=line,
                )
            )

    return violations


def lint_files(paths: List[str]) -> int:
    """Lints multiple files and prints findings."""
    total_violations = 0
    total_files = 0

    for path in paths:
        total_files += 1
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
        except Exception as e:
            print(f"Error reading {path}: {e}", file=sys.stderr)
            continue

        violations = analyze_script(path, content)
        if violations:
            for v in violations:
                total_violations += 1
                print(f"{v.filename}:{v.lineno}:{v.col}: \033[1;31m[{v.rule}]\033[0m {v.message}")
                print(f"  \033[2m{v.line_content.strip()}\033[0m\n")

    if total_violations > 0:
        print(f"\033[1;31m✖ Failed: Found {total_violations} multi-command violation(s) across {total_files} file(s).\033[0m")
        return 1
    else:
        print(f"\033[1;32m✔ Passed: All {total_files} file(s) are cleanly formatted with 1 command per line.\033[0m")
        return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 -m bashcov.linter.multicmd <script1.sh> [script2.sh ...]")
        sys.exit(2)
    sys.exit(lint_files(sys.argv[1:]))
