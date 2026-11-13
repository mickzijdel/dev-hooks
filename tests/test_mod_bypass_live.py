"""Live check, opt-in (DEV_HOOKS_LIVE=1): which of the dev-hooks mod's hooks does this
machine's Claude Code send events past?

A plugin seated above a mod can continue an event past it; Claude Code's debug log then has
`dev-hooks: <event> bypassed by <plugin>`. The module is built to survive the bypasses
listed in KNOWN (see "The dev-hooks mod" in CLAUDE.md). A new one means a feature has
silently stopped, so this test fails on it. It starts a real `claude -p` run, which needs a
login and costs about a dollar, so CI never runs it.
"""

import os
import re
import shutil
import subprocess

import pytest
from conftest import DEV_HOOKS

CLAUDE = shutil.which("claude")
pytestmark = pytest.mark.skipif(
    CLAUDE is None or os.environ.get("DEV_HOOKS_LIVE") != "1",
    reason="live run: set DEV_HOOKS_LIVE=1 on a machine with a logged-in Claude CLI",
)

# Events the built-in cc-plugin-sec-default sends past user mods in a team organization,
# each with what keeps working without the mod's hook.
KNOWN = {
    "classic.Stop": "the Stop command hooks run directly (no stand-down mark is made)",
    "classic.PreToolUse": "the guard's ask goes to Claude Code's own permission prompt",
    "skill.prompt": "the Skill tool call records the skill",
}

BYPASS_RE = re.compile(r"\bdev-hooks: (\S+) bypassed by (\S+)")
DELIVERED_RE = re.compile(r"dev-hooks@inline[^\n]*\btool\.call settled")
# One Bash call: the run raises session.start, turn.start, PreToolUse, tool.call and Stop.
# An event it never raises (skill.prompt, agent.spawn) can't show a bypass here.
PROMPT = "Run exactly this one Bash command and report its output, nothing else: echo live-check"


def test_no_unknown_event_is_sent_past_the_mod(tmp_path):
    log = tmp_path / "debug.log"
    work = tmp_path / "work"
    work.mkdir()
    run = subprocess.run(
        [CLAUDE, "-p", "--no-session-persistence", "--max-turns", "3"]
        + ["--plugin-dir", str(DEV_HOOKS), "--debug-file", str(log), PROMPT],
        cwd=work,
        env={**os.environ, "DEV_HOOKS_PROBE": "1"},
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert log.exists(), f"claude wrote no debug log:\n{run.stdout}\n{run.stderr}"
    text = log.read_text(encoding="utf-8", errors="replace")
    assert "hooks module dev-hooks@inline loaded" in text, (
        "the dev-hooks mod did not load in the live run"
    )
    # Without a delivered-event line, a reworded log would pass with nothing found.
    assert DELIVERED_RE.search(text), (
        "no `dev-hooks@inline … tool.call settled` line: the debug log format changed"
    )
    unknown = {
        (event, by) for event, by in BYPASS_RE.findall(text) if event not in KNOWN
    }
    assert not unknown, (
        f"events sent past the dev-hooks mod that it is not built for: {sorted(unknown)}"
    )
