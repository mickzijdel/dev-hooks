"""The plugins' function-hook modules (hooks/register.tsx) under Claude Code's own runner.

`claude plugin test` loads the plugin the way a session does and runs its *.test.ts(x)
files against the engine; there is no other way to exercise a mod. CI installs a pinned
CLI for this. Without a CLI, or with one whose mods rollout switch is off, both skip.
"""

import shutil
import subprocess

import pytest
from conftest import ASKS, DEV_HOOKS

CLAUDE = shutil.which("claude")
pytestmark = pytest.mark.skipif(CLAUDE is None, reason="no Claude CLI on PATH")

# Each plugin that ships a mod, with hooks its module must register.
MODS = {
    DEV_HOOKS: (
        "command.run{command=context-bar}",
        "command.run{command=session-facts}",
        "skill.prompt",
        "agent.spawn",
        "tool.call",
        "classic.Stop",
        "classic.PreToolUse",
        "session.end",
        "tool.call{tool=Bash}",
    ),
    ASKS: (
        "command.run{command=asks}",
        "turn.complete",
        "prompt.submit",
        "session.end",
        "tool.call{tool=AskUserQuestion}",
        "ui.render{component=Pane, requestId=asks}",
    ),
}
mods = pytest.mark.parametrize("plugin", MODS, ids=[p.name for p in MODS])


def _claude(plugin, *args):
    return subprocess.run(
        [CLAUDE, "plugin", *args, str(plugin)],
        capture_output=True,
        text=True,
        timeout=180,
    )


@mods
def test_module_validates(plugin):
    out = _claude(plugin, "validate", "--strict")
    assert out.returncode == 0, out.stdout + out.stderr
    for hook in MODS[plugin]:
        assert hook in out.stdout, f"{hook} not registered:\n{out.stdout}"


@mods
def test_module_tests_pass(plugin):
    out = _claude(plugin, "test")
    if "hooks modules are turned off" in out.stdout + out.stderr:
        pytest.skip("this Claude CLI has mods switched off")
    assert out.returncode == 0, out.stdout + out.stderr
    assert " 0 fail" in out.stdout, out.stdout


def test_validate_type_checks_the_module(tmp_path):
    """CI's only TypeScript check of the mods is validate's own (2.1.323+): a type error fails it."""
    copy = tmp_path / ASKS.name
    shutil.copytree(ASKS, copy, ignore=shutil.ignore_patterns("node_modules"))
    module = copy / "hooks" / "register.tsx"
    module.write_text(module.read_text() + '\nconst _wrong: number = "not a number"\n')
    out = _claude(copy, "validate", "--strict")
    assert out.returncode != 0, out.stdout
    assert "TS2322" in out.stdout + out.stderr, out.stdout + out.stderr
