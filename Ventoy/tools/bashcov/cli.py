#!/usr/bin/env python3
"""
bashcov CLI entrypoint
======================
General-purpose Bash test runner, static analyzer, and coverage framework.

Commands:
  bashcov run       Execute test suite under coverage and generate reports
  bashcov lint      Run static analysis for multi-command line violations
  bashcov report    Generate HTML and summary reports from existing trace/lcov
"""

import argparse
import glob
import os
import sys

from .core.tracer import BashTracer
from .core.lcov_generator import LcovGenerator
from .plugins.runners.expect_runner import ExpectRunner
from .plugins.collectors.local import LocalCollector
from .plugins.reporters.console_reporter import ConsoleReporter
from .plugins.reporters.html_reporter import HtmlReporter
from .linter.multicmd import lint_files


def cmd_lint(args: argparse.Namespace) -> int:
    targets = []
    for item in args.paths:
        if os.path.isdir(item):
            for ext in ("*.sh", "*.bash"):
                targets.extend(glob.glob(os.path.join(item, "**", ext), recursive=True))
        else:
            targets.append(item)
    return lint_files(targets)


def cmd_run(args: argparse.Namespace) -> int:
    out_dir = os.path.abspath(args.output_dir)
    collector = LocalCollector(out_dir)
    collector.prepare()

    tracer = BashTracer(collector.master_trace)
    tracer_env = tracer.get_env()

    # Discover tests
    runner = ExpectRunner()
    test_files = runner.discover_tests(args.tests_dir, args.pattern)
    if not test_files:
        print(f"No test files found in {args.tests_dir} matching {args.pattern}")
        return 1

    print("=" * 70)
    print(f"    🧪 BASHCOV TEST & COVERAGE ENGINE (Driver: {args.driver})")
    print("=" * 70)
    print(f"  • Tests Found : {len(test_files)}")
    print(f"  • Output Dir  : {out_dir}")
    print("=" * 70)

    failed = 0
    for tpath in test_files:
        tname = os.path.basename(tpath)
        print(f"\n[*] Running: \033[1;36m{tname}\033[0m...")
        header = f"\n{'='*70}\n>>> TEST: {tname}\n{'='*70}\n"
        collector.append_transcript(header)

        res = runner.run_test(tpath, tracer_env)
        collector.append_transcript(res.output)

        if res.passed:
            print(f"    \033[1;32m✓ {tname} passed ({res.duration_sec}s)\033[0m")
        else:
            print(f"    \033[1;31m✖ {tname} failed (exit {res.exit_code}, {res.duration_sec}s)\033[0m")
            failed += 1

    collector.finalize_transcripts()
    print(f"\n[+] Transcripts saved:")
    print(f"  • Raw : {collector.raw_transcript}")
    print(f"  • Clean Text: {collector.clean_transcript}")

    # Generate LCOV
    print("\n[*] Processing traces and generating LCOV report...")
    lcov_file = os.path.join(out_dir, "coverage.info")
    generator = LcovGenerator(
        trace_path=collector.master_trace,
        source_paths=args.sources,
        path_filter=args.filter
    )
    generator.parse_trace()
    generator.analyze_structure()
    generator.write_lcov(lcov_file)

    # Console Summary
    ConsoleReporter.print_summary(lcov_file)

    # HTML Report
    if args.html:
        html_dir = os.path.join(out_dir, "html")
        HtmlReporter.generate(lcov_file, html_dir, prefix=args.prefix)

    return 0 if failed == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(prog="bashcov", description="General-Purpose Bash Coverage & Static Analysis Toolkit")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # Subcommand: lint
    lint_p = subparsers.add_parser("lint", help="Static analysis for multi-command lines")
    lint_p.add_argument("paths", nargs="+", help="Files or directories to lint")
    lint_p.set_defaults(func=cmd_lint)

    # Subcommand: run
    run_p = subparsers.add_parser("run", help="Run tests and generate coverage")
    run_p.add_argument("--tests-dir", default="tests/cases", help="Directory containing test cases")
    run_p.add_argument("--pattern", default="*.exp", help="Test file match pattern")
    run_p.add_argument("--driver", default="expect", choices=["expect"], help="Test execution driver plugin")
    run_p.add_argument("--output-dir", default="coverage_results", help="Directory for traces, logs, and coverage")
    run_p.add_argument("--sources", nargs="*", default=[], help="Source files to include in coverage")
    run_p.add_argument("--filter", default="", help="Substring filter for traced filenames")
    run_p.add_argument("--prefix", default="", help="Prefix strip for genhtml HTML reports")
    run_p.add_argument("--html", action="store_true", default=True, help="Generate browsable HTML report")
    run_p.set_defaults(func=cmd_run)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
