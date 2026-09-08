#!/usr/bin/env python3
"""
bashcov.plugins.collectors.local
================================
Local filesystem trace collector plugin.
"""

import os
import shutil
from typing import Optional


class LocalCollector:
    """Collects and organizes traces on the local machine."""

    def __init__(self, out_dir: str):
        self.out_dir = os.path.abspath(out_dir)
        os.makedirs(self.out_dir, exist_ok=True)
        self.master_trace = os.path.join(self.out_dir, "master_trace.log")
        self.raw_transcript = os.path.join(self.out_dir, "session_transcript_raw.log")
        self.clean_transcript = os.path.join(self.out_dir, "session_transcript_clean.txt")

    def prepare(self) -> None:
        """Cleans prior runs in the output directory, prompting for sudo if root-owned."""
        import subprocess
        for path in [self.master_trace, self.raw_transcript, self.clean_transcript]:
            if os.path.exists(path):
                try:
                    os.remove(path)
                except PermissionError:
                    print(f"\033[1;33m⚠️  Notice: {path} is owned by root. Requesting sudo to remove...\033[0m")
                    subprocess.run(["sudo", "rm", "-f", path], check=True)
            try:
                open(path, "a").close()
            except PermissionError:
                subprocess.run(["sudo", "rm", "-rf", self.out_dir], check=True)
                os.makedirs(self.out_dir, exist_ok=True)
                open(path, "a").close()

    def append_transcript(self, text: str) -> None:
        with open(self.raw_transcript, "a", encoding="utf-8", errors="replace") as f:
            f.write(text)

    def finalize_transcripts(self) -> None:
        """Generates clean transcript without ANSI color escapes or carriage returns."""
        import re
        if os.path.exists(self.raw_transcript):
            with open(self.raw_transcript, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            clean = re.sub(r"\x1B\[[0-9;]*[a-zA-Z]", "", content)
            clean = clean.replace("\r", "")
            with open(self.clean_transcript, "w", encoding="utf-8") as f:
                f.write(clean)
