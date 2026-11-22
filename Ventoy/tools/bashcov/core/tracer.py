#!/usr/bin/env python3
"""
bashcov.core.tracer
===================
Manages Bash execution tracing environments and wrappers.
"""

import os
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional


class BashTracer:
    """Configures environment and runs commands under PS4/XTRACE tracing."""

    def __init__(self, trace_file: str):
        self.trace_file = os.path.abspath(trace_file)
        os.makedirs(os.path.dirname(self.trace_file), exist_ok=True)
        # Ensure trace file exists and is writable
        open(self.trace_file, "a").close()

    def get_env(self) -> Dict[str, str]:
        """Returns the dictionary of environment variables required to trace bash."""
        env = os.environ.copy()
        env_file = os.path.join(tempfile.gettempdir(), f"bashcov_env_{os.getpid()}.sh")
        with open(env_file, "w") as f:
            f.write(f"""export PS4='@@COV@@${{BASH_SOURCE[0]}}@@${{LINENO}}@@\\n'
exec 7>>"{self.trace_file}"
export BASH_XTRACEFD=7
set -x
""")
        env["BASH_ENV"] = env_file
        return env

    def run_command(self, cmd: List[str], cwd: Optional[str] = None) -> int:
        """Executes a command under bash coverage tracing."""
        env = self.get_env()
        proc = subprocess.run(cmd, env=env, cwd=cwd)
        return proc.returncode
