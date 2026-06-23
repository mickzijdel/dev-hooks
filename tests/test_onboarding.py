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
EXPLANATION_LEVELS = SKILL / "references" / "explanation-levels.md"
SKILL_MD = SKILL / "SKILL.md"

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

# Modern CLI quality-of-life tools added to the mise bundle.
MODERN_CLI_TOOLS = [
    "fd",
    "bat",
    "eza",
    "zoxide",
    "fzf",
    "delta",
    "lazygit",
    "yq",
    "hyperfine",
]
TOOLS += MODERN_CLI_TOOLS

TOOLS_DOC = SKILL / "references" / "tools.md"
PLAIN_WORDS = SKILL / "references" / "plain-words.md"


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
    # The safe habits the skill promises are actually encoded.
    assert "branch" in text.lower()
    assert "secret" in text.lower()


def test_claude_defaults_has_swappable_explanation_section():
    # The skill replaces this one section per experience level (step 9); the marker tells it
    # exactly what to swap, and the heading must match the per-rung blocks in explanation-levels.
    text = CLAUDE_DEFAULTS.read_text()
    assert "## How to explain things to me" in text
    assert (
        "explanation-levels.md" in text
    )  # the marker points the seeding step at the source


def test_explanation_levels_defines_four_rungs_and_checkin():
    text = EXPLANATION_LEVELS.read_text()
    low = text.lower()
    flat = " ".join(low.split())  # collapse line wraps so phrase checks survive reflow
    # All four ladder rungs are named (ascending experience).
    for phrase in (
        "new to all this",
        "never coded",
        "code a bit",
        "code confidently",
    ):
        assert phrase in low, f"missing rung: {phrase!r}"
    # Each rung has its own `### Rung N` block, and each carries the section heading the skill
    # swaps in — so a dropped rung fails here (the >= alone wouldn't catch it: the intro mentions
    # the heading once inline, inflating the count).
    for n in range(1, 5):
        assert f"### Rung {n}" in text, f"missing rung block: Rung {n}"
    assert (
        text.count("## How to explain things to me") == 5
    )  # 4 rung blocks + 1 intro mention
    # The self-renewing comfort check-in: a stamped date + a ~month cadence that resets the date.
    assert "calibration set on" in flat
    assert "month" in flat
    assert "reset the date" in flat  # the check-in resets the stamp so it recurs


def test_skill_wires_calibration_step():
    text = SKILL_MD.read_text()
    # The new step uses AskUserQuestion and points at the single source of truth.
    assert "AskUserQuestion" in text
    assert "explanation-levels.md" in text


def test_skill_mise_line_includes_modern_cli_tools():
    # The `mise use -g` install line must pin every modern CLI tool, so onboarding actually
    # installs what onboard_check.sh then probes for.
    text = SKILL_MD.read_text()
    for tool in MODERN_CLI_TOOLS:
        assert tool in text, f"{tool} not pinned in getting-started SKILL.md"


def test_tools_doc_explains_every_modern_cli_tool():
    text = TOOLS_DOC.read_text()
    for tool in MODERN_CLI_TOOLS:
        assert f"**{tool}**" in text, f"{tool} not documented in tools.md"


def test_claude_defaults_prefers_modern_tools():
    text = CLAUDE_DEFAULTS.read_text().lower()
    # The standing instruction to reach for rg/fd over grep/find.
    assert "rg" in text and "fd" in text
    assert "grep" in text and "find" in text


def test_plain_words_glossary_covers_new_jargon():
    low = PLAIN_WORDS.read_text().lower()
    for term in ("fuzzy finder", "syntax highlighting", "benchmark", "yaml", "symlink"):
        assert term in low, f"plain-words.md is missing {term!r}"


def test_skill_documents_agents_md_convention():
    text = SKILL_MD.read_text()
    assert "AGENTS.md" in text
    # The idempotent recipe must not clobber an existing real CLAUDE.md, and must symlink.
    assert "ln -s AGENTS.md CLAUDE.md" in text
    assert "mv CLAUDE.md AGENTS.md" in text  # migrate-don't-clobber path
    low = text.lower()
    assert "symlink" in low
    assert "wsl" in low  # the native-Windows privilege caveat is noted
