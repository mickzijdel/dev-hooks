"""Shared fixtures for the dev-hooks test suite.

Every bundled script (the Python skill CLIs and the shell hooks) is exercised as a
subprocess, asserting on real output — never by importing internals.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
GOLDEN = ROOT / "tests" / "golden"
HOOKS = ROOT / "hooks" / "scripts"


@pytest.fixture(scope="session")
def golden_exit_codes():
    """Map of golden case name -> expected exit code, from golden/manifest.txt."""
    codes = {}
    for line in (GOLDEN / "manifest.txt").read_text().splitlines():
        if not line.strip():
            continue
        name, code = line.split("\t")
        codes[name] = int(code)
    return codes


def init_git_repo(path: Path, *, remote=None, email="t@t", name="t"):
    """Initialise a git repo at `path` with one commit; optional origin remote."""
    run = lambda *a: subprocess.run(  # noqa: E731
        ["git", *a], cwd=path, check=True, capture_output=True, text=True
    )
    run("init", "-q", "-b", "main")
    run("config", "user.email", email)
    run("config", "user.name", name)
    if remote:
        run("remote", "add", "origin", remote)
    return run


def make_transcript(path: Path, *, human_turns=0, extra_lines=None):
    """Write a minimal JSONL transcript with `human_turns` real user messages."""
    import json

    lines = []
    for i in range(human_turns):
        lines.append(
            json.dumps({"message": {"role": "user", "content": f"human message {i}"}})
        )
    for line in extra_lines or []:
        lines.append(line)
    path.write_text("\n".join(lines) + "\n")
    return path


requires_jq = pytest.mark.skipif(shutil.which("jq") is None, reason="jq not installed")
