"""Tests for the getting-started onboarding skill (audit script + config templates).

The checker is exercised as a subprocess on the real machine, asserting on the *shape* of its
output (every tool reports installed|missing, the context keys take known values) rather than
on machine-specific results. The config templates are validated as parseable / non-empty.
"""

import json
import subprocess

from conftest import ONBOARDING

SKILL = ONBOARDING / "skills" / "getting-started"
CHECK = SKILL / "scripts" / "onboard_check.sh"
ALLOWLIST = SKILL / "references" / "templates" / "settings.allowlist.json"
CLAUDE_DEFAULTS = SKILL / "references" / "templates" / "CLAUDE.defaults.md"

TOOLS = [
    "claude",
    "git",
    "mise",
    "node",
    "pnpm",
    "python",
    "uv",
    "jq",
    "ripgrep",
    "gitleaks",
    "gh",
    "docker",
    "code",
]


def run_onboard():
    r = subprocess.run(["bash", str(CHECK)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    out = {}
    for line in r.stdout.splitlines():
        if "=" in line and not line.startswith("# "):
            key, _, value = line.partition("=")
            out[key] = value
    return out


def test_onboard_check_reports_context_keys():
    out = run_onboard()
    assert out["os"] in {"macos", "linux", "wsl", "unknown"}
    assert out["pkg_mgr"] in {"brew", "apt", "dnf", "pacman", "zypper", "none"}
    assert out["arch"]  # non-empty
    assert out["gh_auth"] in {"yes", "no", "unknown"}
    assert out["git_identity"] in {"yes", "no"}
    assert out["playwright_browsers"] in {"installed", "missing"}


def test_onboard_check_reports_installed_or_missing_per_tool():
    out = run_onboard()
    for tool in TOOLS:
        assert out[tool] in {"installed", "missing"}, f"{tool}={out.get(tool)!r}"


def test_onboard_check_reports_version_when_installed():
    # Whatever is present must carry a version line; whatever is missing must not.
    out = run_onboard()
    for tool in TOOLS:
        if out[tool] == "installed":
            assert f"{tool}_version" in out, f"missing version for installed {tool}"
        else:
            assert f"{tool}_version" not in out


def test_settings_allowlist_is_valid_json():
    data = json.loads(ALLOWLIST.read_text())
    allow = data["permissions"]["allow"]
    assert isinstance(allow, list) and allow
    assert all(isinstance(entry, str) for entry in allow)
    # Read-only commands are pre-approved; mutating ones must NOT be on the list.
    assert "Bash(git status:*)" in allow
    assert not any(entry.startswith("Bash(rm") for entry in allow)
    assert not any("push" in entry for entry in allow)


def test_settings_allowlist_seeds_main_guard_opt_in():
    # Beginners get the guard's opt-in commit/push-on-main confirmation switched on.
    data = json.loads(ALLOWLIST.read_text())
    assert data["env"]["DEV_HOOKS_GUARD_MAIN"] == "1"


def test_claude_defaults_template_present():
    text = CLAUDE_DEFAULTS.read_text()
    assert text.strip()
    # The beginner-safe habits the skill promises are actually encoded.
    assert "branch" in text.lower()
    assert "secret" in text.lower()
