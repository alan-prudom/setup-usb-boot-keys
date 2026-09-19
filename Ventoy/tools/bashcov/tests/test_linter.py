#!/usr/bin/env python3
"""
Unit and regression tests for bashcov.linter.multicmd
=====================================================
Covers every multi-command and AST-distorting pattern encountered
while establishing 1:1 coverage hit fidelity:

1. Inline Semicolons (MULTICMD_SEMICOLON)
2. Chained Boolean Operators (MULTICMD_CHAINED_BOOLEAN)
3. Inline Fallback Handlers (MULTICMD_INLINE_FALLBACK)
4. Inline Case Arm Statements (MULTICMD_INLINE_CASE_ARM)
5. Chained Subshells on Single Line (MULTICMD_INLINE_SUBSHELL)
6. Multiline Subshells with Internal Pipelines/Operators (MULTILINE_SUBSHELL_PIPELINE)
7. False-Positive Protections (grep regex quotes, semicolons in loops/ifs, single commands in subshells)
"""

import os
import sys
import unittest

tools_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

from bashcov.linter.multicmd import analyze_script


class TestMulticmdLinterRegressions(unittest.TestCase):

    # -------------------------------------------------------------------------
    # Regression Case 1: Chained Boolean Operators on one line (e.g. Line 72)
    # [ -n "$p" ] && [ -b "$p" ] && [ -z "$err" ] multiplied gcov hit counts
    # -------------------------------------------------------------------------
    def test_chained_boolean_operators(self):
        script = """#!/usr/bin/env bash
if [ -n "$p" ] && [ -b "$p" ]; then
    echo "valid"
fi
"""
        violations = analyze_script("case1.sh", script)
        self.assertTrue(
            any(v.rule == "MULTICMD_CHAINED_BOOLEAN" for v in violations),
            "Expected MULTICMD_CHAINED_BOOLEAN for chained '&&' on same line",
        )

    # -------------------------------------------------------------------------
    # Regression Case 2: Inline Semicolons
    # cmd1 ; cmd2 causes trace hits to stack on one line
    # -------------------------------------------------------------------------
    def test_inline_semicolon(self):
        script = """#!/usr/bin/env bash
mkdir -p /tmp/foo ; touch /tmp/foo/bar
"""
        violations = analyze_script("case2.sh", script)
        self.assertTrue(
            any(v.rule == "MULTICMD_SEMICOLON" for v in violations),
            "Expected MULTICMD_SEMICOLON for inline semicolon command separation",
        )

    # -------------------------------------------------------------------------
    # Regression Case 3: Inline Fallbacks (e.g. cmd || true, cmd || return 1)
    # Doubles line execution hit count in coverage reports
    # -------------------------------------------------------------------------
    def test_inline_fallback(self):
        script = """#!/usr/bin/env bash
smartctl -a /dev/sda > /tmp/out 2>/dev/null || true
detect_data_partition || return 1
"""
        violations = analyze_script("case3.sh", script)
        fallback_violations = [v for v in violations if v.rule == "MULTICMD_INLINE_FALLBACK"]
        self.assertEqual(len(fallback_violations), 2, "Expected 2 MULTICMD_INLINE_FALLBACK violations")

    # -------------------------------------------------------------------------
    # Regression Case 4: Inline Case Arm Terminations
    # 1) echo "one" ;; on same line obscures branch coverage
    # -------------------------------------------------------------------------
    def test_inline_case_arm(self):
        script = """#!/usr/bin/env bash
case "$opt" in
    1) echo "one" ;;
    2)
        echo "two"
        ;;
esac
"""
        violations = analyze_script("case4.sh", script)
        self.assertTrue(
            any(v.rule == "MULTICMD_INLINE_CASE_ARM" for v in violations),
            "Expected MULTICMD_INLINE_CASE_ARM for inline command before ';;'",
        )

    # -------------------------------------------------------------------------
    # Regression Case 5: Inline Chained Subshells (e.g. Line 29, Line 59)
    # answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
    # Forks 3 processes on line 29/59, resulting in 24x to 54x hit counts!
    # -------------------------------------------------------------------------
    def test_inline_chained_subshell(self):
        script = """#!/usr/bin/env bash
answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]' | xargs)"
choice="$(echo "$choice" | xargs)"
"""
        violations = analyze_script("case5.sh", script)
        subshell_violations = [v for v in violations if v.rule == "MULTICMD_INLINE_SUBSHELL"]
        self.assertEqual(len(subshell_violations), 2, "Expected 2 MULTICMD_INLINE_SUBSHELL violations")

    # -------------------------------------------------------------------------
    # Regression Case 6: MULTILINE Subshell with Internal Pipeline (NEW TARGET)
    # p_label=$(
    #     lsblk -n -o LABEL "/dev/$p" |
    #     xargs ||
    #     echo ""
    # )
    # Causes Bash AST line-number desynchronization, phantom hit inflation on
    # subsequent lines (e.g. line 252 doubled from 19 to 38 hits).
    # THIS TEST MUST INITIALLY FAIL before linter enhancement!
    # -------------------------------------------------------------------------
    def test_multiline_subshell_with_pipeline_fails(self):
        script = """#!/usr/bin/env bash
p_label=$(
    lsblk -n -o LABEL "/dev/$p" 2>/dev/null |
    xargs ||
    echo ""
)
p_desc="${p_size}"
"""
        violations = analyze_script("case6_target.sh", script)
        self.assertTrue(
            any(
                v.rule in ("MULTILINE_SUBSHELL_PIPELINE", "MULTICMD_MULTILINE_SUBSHELL")
                for v in violations
            ),
            "Linter failed to catch multiline subshell pipeline! Must be flagged to prevent Bash LINENO offset bugs.",
        )

    # -------------------------------------------------------------------------
    # Regression Case 7: False-Positive Protections (Clean Native Bash)
    # Ensure legitimate Bash constructs are NOT falsely flagged:
    # - Grep with pipe regex inside quotes: grep -iE "error|failed"
    # - Semicolons in C-style loops: for ((i=0; i<5; i++))
    # - Semicolons before then/do: if [ -f "$f" ]; then
    # - Single command in $(): model=$(tr -cd '[:alnum:]' < "$p")
    # - Native parameter expansions: ${answer,,}, ${answer#"${answer%%...}"}
    # -------------------------------------------------------------------------
    def test_false_positive_protections(self):
        script = """#!/usr/bin/env bash
# 1. Regex containing pipe inside double quotes
if raw_errs=$(grep -iE "error|failed|fatal" "$log_file" 2>/dev/null); then
    echo "found"
fi

# 2. C-style for loop with semicolons
for ((i=0; i<10; i++)); do
    echo "$i"
done

# 3. Standard if / while syntax
if [ -f "$file" ]; then
    echo "exists"
fi

# 4. Single command in subshell
model=$(tr -cd '[:alnum:]' < "$sys_file")

# 5. Native bash trimming (pure parameter expansion)
trimmed="${answer#"${answer%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
lowercase="${trimmed,,}"
"""
        violations = analyze_script("case7_clean.sh", script)
        self.assertEqual(
            violations,
            [],
            f"Expected 0 violations for clean native Bash constructs, but got: {violations}",
        )


if __name__ == "__main__":
    unittest.main()
