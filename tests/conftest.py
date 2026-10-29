"""Shared fixtures for the dev-hooks test suite.

Every bundled script (the Python skill CLIs and the shell hooks) is exercised as a
subprocess, asserting on real output — never by importing internals.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture(autouse=True)
def _clean_dev_hooks_env(monkeypatch):
    """Hook subprocesses inherit the ambient environment (os.environ.copy()), and so does a
    suite run by verify-work from a live session. Every DEV_HOOKS_* there is the real
    session's: DEV_HOOKS_FIRE_LOG writes into the real hook-fires.jsonl, an opt-out flips a
    test, and the mod's DEV_HOOKS_FACTS_FILE hands every hook that session's facts (a memory
    written there silences memory-reminder's tests). Strip them all; tests set what they need.
    CLAUDE_PID goes too: in a suite run from a nested `claude -p` it names that run, and every
    hook would read the run as nested (reminder_is_nested_run)."""
    for var in [v for v in os.environ if v.startswith("DEV_HOOKS_")]:
        monkeypatch.delenv(var)
    monkeypatch.delenv("CLAUDE_PID", raising=False)


@pytest.fixture
def claude_pid():
    """A stand-in for the `claude` process a hook runs under, as a pid for CLAUDE_PID:
    claude_pid(nested=True) carries CLAUDE_CODE_CHILD_SESSION in its own environment, as a
    `claude` started from another session's shell does; nested=False is one a person started."""
    procs = []

    def start(nested):
        env = {k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_CHILD_SESSION"}
        if nested:
            env["CLAUDE_CODE_CHILD_SESSION"] = "1"
        procs.append(subprocess.Popen(["sleep", "60"], env=env))
        return str(procs[-1].pid)

    yield start
    for p in procs:
        p.kill()
        p.wait()


@pytest.fixture(autouse=True)
def _mise_trusts_real_home(monkeypatch):
    """Tests point HOME at tmp_path, and mise >= 2026.9 then no longer trusts the real
    ~/.config/mise — so every mise shim (jq included) a hook subprocess runs dies with
    "not trusted" and the hook silently sees empty input. Pin mise's dirs to the real
    HOME's (a cold cache costs ~20s per shim call) and pre-trust it."""
    home = str(Path.home())
    env = os.environ.get
    for var, default in (
        ("MISE_CONFIG_DIR", f"{env('XDG_CONFIG_HOME', home + '/.config')}/mise"),
        ("MISE_DATA_DIR", f"{env('XDG_DATA_HOME', home + '/.local/share')}/mise"),
        ("MISE_CACHE_DIR", f"{env('XDG_CACHE_HOME', home + '/.cache')}/mise"),
        ("MISE_STATE_DIR", f"{env('XDG_STATE_HOME', home + '/.local/state')}/mise"),
    ):
        if not env(var):
            monkeypatch.setenv(var, default)
    current = os.environ.get("MISE_TRUSTED_CONFIG_PATHS", "")
    if home not in current.split(":"):
        monkeypatch.setenv(
            "MISE_TRUSTED_CONFIG_PATHS", f"{current}:{home}" if current else home
        )


@pytest.fixture(autouse=True)
def _hermetic_hook_state(monkeypatch, tmp_path_factory, _mise_trusts_real_home):
    """The hooks keep per-session state under $XDG_STATE_HOME so it survives a reboot; give
    each test its own, outside tmp_path (a state dir inside a test's git repo would show in
    its porcelain). Runs after the mise fixture, which reads the real XDG_STATE_HOME."""
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path_factory.mktemp("state")))


DEV_HOOKS = ROOT / "plugins" / "dev-hooks"
ONBOARDING = ROOT / "plugins" / "coding-onboarding"
WRITING = ROOT / "plugins" / "writing"
FIXTURES = ROOT / "tests" / "fixtures"
GOLDEN = ROOT / "tests" / "golden"
THINKING = ROOT / "plugins" / "thinking-tools"
HOOKS = DEV_HOOKS / "hooks" / "scripts"
WRITING_HOOKS = WRITING / "hooks" / "scripts"
THINKING_HOOKS = THINKING / "hooks" / "scripts"


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
    run = lambda *a: subprocess.run(
        ["git", *a], cwd=path, check=True, capture_output=True, text=True
    )
    run("init", "-q", "-b", "main")
    run("config", "user.email", email)
    run("config", "user.name", name)
    if remote:
        run("remote", "add", "origin", remote)
    return run


CHECKER = DEV_HOOKS / "skills" / "dev-env-setup" / "scripts" / "dev_env_check.sh"


def parse_kv(stdout):
    """Parse the KEY=VALUE lines a checker/inventory script emits (ignoring `# ` summary
    lines). Shared by the dev-env checker and the dependency-upgrade inventory."""
    out = {}
    for line in stdout.splitlines():
        if "=" in line and not line.startswith("# "):
            key, _, value = line.partition("=")
            out[key] = value
    return out


def run_checker(target):
    """Run the dev-env-setup compliance checker and parse its key=value output."""
    r = subprocess.run(
        ["bash", str(CHECKER), str(target)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    return parse_kv(r.stdout)


def make_compliant_repo(
    path,
    *,
    readme=True,
    claude=True,
    cooldown=True,
    gitleaks_config=True,
    jscpd_runner=True,
    version_sync=True,
    exec_bit=True,
    sha_pinned=True,
    zizmor=True,
    actionlint=True,
    session_url_off=True,
):
    """Build a repo that satisfies everything the checker enforces at the current standard
    except optionally the README/CLAUDE.md docs, the uv cooldown, the .gitleaks.toml
    allowlist, the shared jscpd runner (v14), the exec-bit hk step (v15), SHA-pinned CI
    actions (v16), the zizmor / actionlint hk steps (v18), the shared version-sync gate
    (v23), or the .claude/settings.json that keeps the session link out of commits (v28).
    Stamped at the current version (read from VERSION) so it stays compliant as the
    standard advances."""
    version = (DEV_HOOKS / "skills" / "dev-env-setup" / "VERSION").read_text().strip()
    # Python stack; from v6 a Python repo must pin the uv cooldown in pyproject.toml.
    pyproject = "[project]\nname='x'\n"
    if cooldown:
        pyproject += '\n[tool.uv]\nexclude-newer = "4 days"\n'
    (path / "pyproject.toml").write_text(pyproject)
    (path / "mise.toml").write_text(
        f'[settings]\nlockfile = true\n[env]\nDEV_ENV_VERSION = "{version}"\n'
    )
    (path / "mise.lock").write_text("")
    hk = '["gitleaks"] = Builtins.gitleaks\n'
    if exec_bit:
        hk += '["exec-bit-scripts"] { check = "..." }\n'
    if zizmor:
        hk += '["zizmor"] = Builtins.zizmor\n'
    if actionlint:
        hk += '["actionlint"] = Builtins.actionlint\n'
    (path / "hk.pkl").write_text(hk)
    wf = path / ".github" / "workflows"
    wf.mkdir(parents=True)
    # v16: CI actions must be SHA-pinned. A 40-hex pin is "pinned"; a tag pin (@v6) is not.
    pin = ("a" * 40 + " # v1") if sha_pinned else "v6"
    (wf / "ci.yml").write_text(
        "name: ci\non: push\njobs:\n  x:\n    steps:\n"
        f"      - uses: actions/checkout@{pin}\n"
    )
    if readme:
        (path / "README.md").write_text("# x\n")
    if claude:
        (path / "CLAUDE.md").write_text("# project instructions\n")
    if gitleaks_config:
        (path / ".gitleaks.toml").write_text("[extend]\nuseDefault = true\n")
    if jscpd_runner:
        (path / "scripts").mkdir(exist_ok=True)
        (path / "scripts" / "run-jscpd.sh").write_text("#!/usr/bin/env bash\n")
    if version_sync:
        (path / "scripts").mkdir(exist_ok=True)
        (path / "scripts" / "check_version_sync.sh").write_text("#!/usr/bin/env bash\n")
    if session_url_off:
        (path / ".claude").mkdir(exist_ok=True)
        (path / ".claude" / "settings.json").write_text(
            '{\n  "attribution": {\n    "sessionUrl": false\n  }\n}\n'
        )


def make_transcript(path: Path, *, human_turns=0, extra_lines=None):
    """Write a minimal JSONL transcript with `human_turns` real user messages."""
    import json

    lines = []
    for i in range(human_turns):
        lines.append(
            json.dumps({"message": {"role": "user", "content": f"human message {i}"}})
        )
    lines.extend(extra_lines or [])
    path.write_text("\n".join(lines) + "\n")
    return path


requires_jq = pytest.mark.skipif(shutil.which("jq") is None, reason="jq not installed")
requires_python3 = pytest.mark.skipif(
    shutil.which("python3") is None, reason="python3 not installed"
)
