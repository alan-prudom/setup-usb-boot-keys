#!/usr/bin/env python3
"""
bashcov.plugins.reporters.html_reporter
=======================================
Invokes genhtml with canonical prefix resolution.
"""

import os
import shutil
import subprocess
from typing import Optional


class HtmlReporter:
    """Generates browsable HTML report from LCOV file using genhtml."""

    @staticmethod
    def generate(lcov_path: str, output_dir: str, prefix: Optional[str] = None) -> bool:
        if not shutil.which("genhtml"):
            print("Notice: 'genhtml' command not found. Install 'lcov' to view HTML reports.")
            return False

        os.makedirs(output_dir, exist_ok=True)
        cmd = ["genhtml", "--branch-coverage", lcov_path, "--output-directory", output_dir]
        if prefix:
            cmd.extend(["--prefix", prefix])

        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if proc.returncode == 0:
            print(f"  • Browsable HTML : {os.path.join(output_dir, 'index.html')}")
            return True
        else:
            print(f"genhtml failed:\n{proc.stdout}")
            return False
