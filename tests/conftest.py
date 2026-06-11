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
    """Initialise an empty git repo at `path` (no commits — HEAD doesn't resolve yet,
    deliberately exercising hooks against the brand-new-repo edge); optional origin
    remote. Returns a `run(*git_args)` helper so tests add/commit when they need to."""
    run = lambda *a: subprocess.run(  # noqa: E731
        ["git", *a], cwd=path, check=True, capture_output=True, text=True
    )
    run("init", "-q", "-b", "main")
    run("config", "user.email", email)
    run("config", "user.name", name)
    if remote:
        run("remote", "add", "origin", remote)
    return run


CHECKER = ROOT / "skills" / "dev-env-setup" / "scripts" / "dev_env_check.sh"


def run_checker(target):
    """Run the dev-env-setup compliance checker and parse its key=value output."""
    r = subprocess.run(
        ["bash", str(CHECKER), str(target)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    out = {}
    for line in r.stdout.splitlines():
        if "=" in line and not line.startswith("# "):
            key, _, value = line.partition("=")
            out[key] = value
    return out


def make_compliant_repo(
    path,
    *,
    readme=True,
    claude=True,
    cooldown=True,
    gitleaks_config=True,
    jscpd_runner=True,
):
    """Build a repo that satisfies everything the checker enforces at the current standard
    except optionally the README/CLAUDE.md docs, the uv cooldown, the .gitleaks.toml
    allowlist, or the shared jscpd runner (v14). Stamped at the current version (read from
    VERSION) so it stays compliant as the standard advances."""
    version = (ROOT / "skills" / "dev-env-setup" / "VERSION").read_text().strip()
    # Python stack; from v6 a Python repo must pin the uv cooldown in pyproject.toml.
    pyproject = "[project]\nname='x'\n"
    if cooldown:
        pyproject += '\n[tool.uv]\nexclude-newer = "4 days"\n'
    (path / "pyproject.toml").write_text(pyproject)
    (path / "mise.toml").write_text(
        f'[settings]\nlockfile = true\n[env]\nDEV_ENV_VERSION = "{version}"\n'
    )
    (path / "mise.lock").write_text("")
    (path / "hk.pkl").write_text('["gitleaks"] = Builtins.gitleaks\n')
    wf = path / ".github" / "workflows"
    wf.mkdir(parents=True)
    (wf / "ci.yml").write_text("name: ci\non: push\n")
    if readme:
        (path / "README.md").write_text("# x\n")
    if claude:
        (path / "CLAUDE.md").write_text("# project instructions\n")
    if gitleaks_config:
        (path / ".gitleaks.toml").write_text("[extend]\nuseDefault = true\n")
    if jscpd_runner:
        (path / "scripts").mkdir(exist_ok=True)
        (path / "scripts" / "run-jscpd.sh").write_text("#!/usr/bin/env bash\n")


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
