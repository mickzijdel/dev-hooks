"""Tests for the weekly-automation-review skill's prompt-log reader.

The reader command is documented *in the SKILL.md itself*, so these tests extract that
exact command and run it against a deliberately corrupted log — guarding the property that
one crash-corrupted line (a block of NUL bytes, seen live) can never make the reader drop the
rest of the file and blind the review to its strongest signal.
"""

import json
import os
import re
import subprocess
from datetime import datetime, timedelta, timezone


from conftest import ROOT, requires_jq

pytestmark = requires_jq

SKILL = (
    ROOT
    / "plugins"
    / "thinking-tools"
    / "skills"
    / "weekly-automation-review"
    / "SKILL.md"
)

NUL_BLOCK = b"\x00" * 64  # crash-time zero padding, as observed in a real log


def _ts(days_ago):
    when = datetime.now(timezone.utc) - timedelta(days=days_ago)
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def _rec(days_ago, prompt):
    return {
        "ts": _ts(days_ago),
        "cwd": "/repo",
        "session_id": "s",
        "len": len(prompt),
        "prompt": prompt,
    }


def _line(rec):
    return (json.dumps(rec) + "\n").encode()


def _documented_reader():
    """Extract the fenced bash block from SKILL.md that reads the prompt log."""
    for block in re.findall(r"```bash\n(.*?)```", SKILL.read_text(), re.DOTALL):
        if "prompts.jsonl" in block and "jq" in block:
            return block
    raise AssertionError(
        "no prompt-log reader block found in weekly-automation-review SKILL.md"
    )


def _write_corrupted_log(home):
    """A log whose second physical line is NUL-padding + a valid record (the live failure
    mode), plus a truncated fragment, an in-window spillover record, and an out-of-window
    record that must be filtered by the 7-day cutoff."""
    log_dir = home / ".claude" / "automation-review"
    log_dir.mkdir(parents=True)
    log = log_dir / "prompts.jsonl"
    with log.open("wb") as f:
        f.write(_line(_rec(1, "alpha")))
        f.write(NUL_BLOCK + _line(_rec(2, "beta")))  # would abort a plain `jq -c`
        f.write(
            b'{"ts":"2026-01-01T00:00:00Z","prompt":"truncated\n'
        )  # unparseable fragment
        f.write(_line(_rec(9, "too-old")))  # outside the 7-day window
    (log_dir / "prompts.jsonl.1").write_bytes(
        _line(_rec(3, "gamma"))
    )  # rotation spillover
    return log


def _run(cmd, home):
    return subprocess.run(
        ["bash", "-c", cmd],
        env={**os.environ, "HOME": str(home)},
        capture_output=True,
        text=True,
    )


def _prompts(stdout):
    out = []
    for line in stdout.splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line)["prompt"])
    return out


def test_documented_reader_recovers_past_nul_corruption(tmp_path):
    _write_corrupted_log(tmp_path)
    r = _run(_documented_reader(), tmp_path)
    got = set(_prompts(r.stdout))
    # Every in-window record survives, including the one glued to the NUL block and the
    # spillover file; the out-of-window record is filtered by the cutoff.
    assert {"alpha", "beta", "gamma"} <= got
    assert "too-old" not in got


def test_naive_jq_reader_is_blinded_by_the_corruption(tmp_path):
    """The property the fix exists for: a plain `jq -c` aborts on the NUL line, so it recovers
    strictly fewer in-window records than the documented reader."""
    log = _write_corrupted_log(tmp_path)
    naive = f"jq -c 'select(.ts >= (now - 7*86400 | strftime(\"%Y-%m-%dT%H:%M:%SZ\")))' {log} 2>/dev/null"
    naive_got = set(_prompts(_run(naive, tmp_path).stdout))
    tolerant_got = set(_prompts(_run(_documented_reader(), tmp_path).stdout))
    assert naive_got < tolerant_got  # naive misses records the tolerant reader keeps
