"""dev-hooks' function-hook module (hooks/register.tsx) under Claude Code's own runner.

`claude plugin test` loads the plugin the way a session does and runs its *.test.ts(x)
files against the engine; there is no other way to exercise a mod. CI has no Claude CLI,
and a CLI whose mods rollout switch is off refuses to run them, so both cases skip.
"""

import shutil
import subprocess

import pytest

from conftest import DEV_HOOKS

CLAUDE = shutil.which("claude")
pytestmark = pytest.mark.skipif(CLAUDE is None, reason="no Claude CLI on PATH")


def _claude(*args):
    return subprocess.run(
        [CLAUDE, "plugin", *args, str(DEV_HOOKS)],
        capture_output=True,
        text=True,
        timeout=180,
    )


def test_module_validates():
    out = _claude("validate", "--strict")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "command.run{command=context-bar}" in out.stdout


def test_module_tests_pass():
    out = _claude("test")
    if "hooks modules are turned off" in out.stdout + out.stderr:
        pytest.skip("this Claude CLI has mods switched off")
    assert out.returncode == 0, out.stdout + out.stderr
    assert " 0 fail" in out.stdout, out.stdout
