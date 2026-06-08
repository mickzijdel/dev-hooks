"""Example: testing a Claude Code plugin's bundled scripts as subprocesses.

readoc-style — run each script/CLI exactly as it ships (PEP 723 Python via
`uv run --script`, or a shell hook via `bash ...`) and assert on its real output.
Drop this in tests/ and adapt to your scripts. Run with `uv run pytest`.
"""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_pep723_cli_runs():
    """A PEP 723 Python CLI runs self-contained via its shebang."""
    result = subprocess.run(
        [str(ROOT / "bin" / "your-cli"), "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "usage" in result.stdout.lower()


def test_hook_emits_valid_json(tmp_path):
    """A SessionStart/Stop hook script emits parseable JSON (or stays silent)."""
    proc = subprocess.run(
        ["bash", str(ROOT / "hooks" / "scripts" / "your-hook.sh")],
        input=json.dumps({"cwd": str(tmp_path)}),
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0
    if proc.stdout.strip():
        json.loads(proc.stdout)  # must be valid JSON when it speaks
