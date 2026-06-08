"""Shared CLI base for the readability scripts.

Plain importable module (no PEP 723 block) — stdlib only. Imported by the sibling
scripts that run via ``uv run --script``; the script's own directory is on ``sys.path``
so the import resolves.
"""

import subprocess
import sys
from pathlib import Path


class ReadabilityCli:
    """Drives a single-metric analysis: print current value, or compare to a branch.

    Subclasses provide ``analyze``, ``print_current``, ``comparison_title`` and
    ``output_format`` (a printf-style format string), and may override
    ``comparison_delta``.
    """

    def __init__(self, argv, stdin):
        self.filename = argv[0] if len(argv) > 0 else None
        self.branch = argv[1] if len(argv) > 1 else None
        self._stdin = stdin

    def run(self):
        current = self.analyze(self._current_text())
        if not self.branch:
            self.print_current(current)
            return
        self._print_comparison(current)

    # --- subclass hooks -------------------------------------------------
    def analyze(self, text):
        raise NotImplementedError

    def print_current(self, value):
        raise NotImplementedError

    def comparison_title(self):
        raise NotImplementedError

    def output_format(self):
        raise NotImplementedError

    def comparison_delta(self, baseline, current):
        return current - baseline

    # --- internals ------------------------------------------------------
    def _current_text(self):
        text = self._read_file(self.filename) if self.filename else self._stdin.read()
        if not text.strip():
            self._exit_with_error("No input provided.")
        return text

    def _read_file(self, path):
        if not Path(path).exists():
            self._exit_with_error(f"File not found: {path}")
        return Path(path).read_text()

    def _print_comparison(self, current):
        baseline = self.analyze(self._branch_text())
        self._print_comparison_report(baseline, current)

    def _branch_text(self):
        if not self.filename:
            self._exit_with_error("Filename required for branch comparison")
        result = subprocess.run(
            ["git", "show", f"{self.branch}:{self.filename}"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0 or not result.stdout.strip():
            self._exit_with_error(f"Could not read file from branch '{self.branch}'")
        return result.stdout

    def _print_comparison_report(self, baseline, current):
        fmt = self.output_format()
        print(self.comparison_title())
        print(f"  {self.branch}: {fmt % baseline}")
        print(f"  current: {fmt % current}")
        print(f"  improvement: {fmt % self.comparison_delta(baseline, current)}")

    def _exit_with_error(self, message):
        print(message, file=sys.stderr)
        sys.exit(1)
