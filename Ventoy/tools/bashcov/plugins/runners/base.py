#!/usr/bin/env python3
"""
bashcov.plugins.runners.base
============================
Abstract base class for test runners.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, List, Optional


@dataclass
class TestResult:
    test_name: str
    passed: bool
    exit_code: int
    duration_sec: float
    output: str


class BaseRunner(ABC):
    """Abstract base runner interface."""

    @abstractmethod
    def discover_tests(self, test_dir: str, pattern: str) -> List[str]:
        """Discovers test cases matching the pattern."""
        pass

    @abstractmethod
    def run_test(self, test_path: str, env: Dict[str, str], cwd: Optional[str] = None) -> TestResult:
        """Runs a single test case under the provided environment."""
        pass
