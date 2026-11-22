#!/usr/bin/env python3
"""
bashcov.plugins.reporters.console_reporter
==========================================
ANSI Console summary table reporter.
"""

import os
import re
from typing import Dict, List


class ConsoleReporter:
    """Prints formatted summary tables to the terminal."""

    @staticmethod
    def print_summary(lcov_path: str) -> None:
        if not os.path.exists(lcov_path):
            print(f"Coverage file {lcov_path} not found.")
            return

        print("\n" + "=" * 78)
        print(f" {'SCRIPT FILE':<35} | {'LINES':<12} | {'FUNCTIONS':<11} | {'BRANCHES':<11}")
        print("=" * 78)

        current_file = ""
        lh, lf = 0, 0
        fnh, fnf = 0, 0
        brh, brf = 0, 0

        tot_lh, tot_lf = 0, 0
        tot_fnh, tot_fnf = 0, 0
        tot_brh, tot_brf = 0, 0

        def emit_row():
            nonlocal current_file, lh, lf, fnh, fnf, brh, brf
            nonlocal tot_lh, tot_lf, tot_fnh, tot_fnf, tot_brh, tot_brf
            if not current_file:
                return
            bname = os.path.basename(current_file)
            lpct = f"{(lh/lf*100):.1f}%" if lf > 0 else "N/A"
            fpct = f"{(fnh/fnf*100):.1f}%" if fnf > 0 else "N/A"
            bpct = f"{(brh/brf*100):.1f}%" if brf > 0 else "N/A"

            l_str = f"{lh}/{lf} ({lpct})"
            f_str = f"{fnh}/{fnf} ({fpct})"
            b_str = f"{brh}/{brf} ({bpct})"

            print(f" {bname:<35} | {l_str:<12} | {f_str:<11} | {b_str:<11}")

            tot_lh += lh
            tot_lf += lf
            tot_fnh += fnh
            tot_fnf += fnf
            tot_brh += brh
            tot_brf += brf

            lh, lf, fnh, fnf, brh, brf = 0, 0, 0, 0, 0, 0

        with open(lcov_path, "r", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith("SF:"):
                    current_file = line[3:]
                elif line.startswith("LH:"):
                    lh = int(line[3:])
                elif line.startswith("LF:"):
                    lf = int(line[3:])
                elif line.startswith("FNH:"):
                    fnh = int(line[4:])
                elif line.startswith("FNF:"):
                    fnf = int(line[4:])
                elif line.startswith("BRH:"):
                    brh = int(line[4:])
                elif line.startswith("BRF:"):
                    brf = int(line[4:])
                elif line == "end_of_record":
                    emit_row()

        print("-" * 78)
        tot_lpct = f"{(tot_lh/tot_lf*100):.1f}%" if tot_lf > 0 else "N/A"
        tot_fpct = f"{(tot_fnh/tot_fnf*100):.1f}%" if tot_fnf > 0 else "N/A"
        tot_bpct = f"{(tot_brh/tot_brf*100):.1f}%" if tot_brf > 0 else "N/A"

        tot_l_str = f"{tot_lh}/{tot_lf} ({tot_lpct})"
        tot_f_str = f"{tot_fnh}/{tot_fnf} ({tot_fpct})"
        tot_b_str = f"{tot_brh}/{tot_brf} ({tot_bpct})"

        print(f" {'OVERALL TOTALS':<35} | {tot_l_str:<12} | {tot_f_str:<11} | {tot_b_str:<11}")
        print("=" * 78 + "\n")
