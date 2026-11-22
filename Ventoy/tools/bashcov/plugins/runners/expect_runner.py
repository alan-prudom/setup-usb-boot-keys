#!/usr/bin/env python3
"""
bashcov.plugins.runners.expect_runner
=====================================
Expect (.exp) test runner plugin.
"""

import glob
import os
import subprocess
import time
from typing import Dict, List, Optional
from .base import BaseRunner, TestResult


class ExpectRunner(BaseRunner):
    """Executes .exp Expect test cases."""

    def discover_tests(self, test_dir: str, pattern: str = "*.exp") -> List[str]:
        search_path = os.path.join(test_dir, pattern)
        return sorted(glob.glob(search_path))

    def run_test(self, test_path: str, env: Dict[str, str], cwd: Optional[str] = None) -> TestResult:
        tname = os.path.basename(test_path)
        start_time = time.time()

        proc = subprocess.run(
            ["expect", test_path],
            env=env,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        duration = time.time() - start_time
        return TestResult(
            test_name=tname,
            passed=(proc.returncode == 0),
            exit_code=proc.returncode,
            duration_sec=round(duration, 2),
            output=proc.stdout
        )
