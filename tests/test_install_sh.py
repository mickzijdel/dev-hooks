"""Tests for the coding-onboarding bootstrap installer (install.sh) and its overlay page.

install.sh is exercised as a subprocess against a *stub* `claude` binary (pointed at via the
ONBOARD_CLAUDE_BIN seam) so nothing is actually installed and no network is touched. The stub
prints canned `auth status` / `plugin … list` JSON driven by env vars and appends every
invocation to a log file, letting us assert both the read-only `--check` report and which
real install commands the script would and wouldn't run.
"""

import os
import subprocess

from conftest import ONBOARDING, ROOT

INSTALL = ROOT / "install.sh"
ONBOARD_HTML = ONBOARDING / "onboarding" / "onboard.html"
PLAIN_WORDS = (
    ONBOARDING / "skills" / "getting-started" / "references" / "plain-words.md"
)
SKILL_MD = ONBOARDING / "skills" / "getting-started" / "SKILL.md"
ROOT_README = ROOT / "README.md"

RAW_BASE = "raw.githubusercontent.com/mickzijdel/dev-hooks/main"
HTML_REL_PATH = "plugins/coding-onboarding/onboarding/onboard.html"
INSTALL_RAW_URL = f"{RAW_BASE}/install.sh"

STUB = """#!/bin/bash
# Stub `claude` for install.sh tests. Logs argv; answers from STUB_* env vars.
echo "$*" >>"$STUB_LOG"
if [ "$1" = "--version" ]; then
  echo "claude 9.9.9 (stub)"
elif [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  if [ "${STUB_LOGGED_IN:-1}" = "1" ]; then echo '{"loggedIn": true}'; else echo '{"loggedIn": false}'; fi
elif [ "$1" = "plugin" ] && [ "$2" = "marketplace" ] && [ "$3" = "list" ]; then
  if [ "${STUB_MARKETPLACE:-1}" = "1" ]; then echo '{"marketplaces":[{"name":"dev-hooks"}]}'; else echo '{}'; fi
elif [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  if [ "${STUB_PLUGIN:-1}" = "1" ]; then echo '{"plugins":[{"name":"coding-onboarding"}]}'; else echo '{}'; fi
fi
exit 0
"""


def make_stub(tmp_path):
    """Write the stub claude binary + its log file; return (stub_path, log_path)."""
    stub = tmp_path / "claude-stub"
    stub.write_text(STUB)
    stub.chmod(0o755)
    log = tmp_path / "calls.log"
    log.write_text("")
    return stub, log


def run_install(tmp_path, *args, logged_in=1, marketplace=1, plugin=1, assume_yes=True):
    """Run install.sh against the stub claude. Returns (CompletedProcess, log_text)."""
    stub, log = make_stub(tmp_path)
    env = {
        **os.environ,
        "ONBOARD_CLAUDE_BIN": str(stub),
        "ONBOARD_NO_BROWSER": "1",
        "STUB_LOG": str(log),
        "STUB_LOGGED_IN": str(logged_in),
        "STUB_MARKETPLACE": str(marketplace),
        "STUB_PLUGIN": str(plugin),
    }
    if assume_yes:
        env["ONBOARD_ASSUME_YES"] = "1"
    r = subprocess.run(
        ["bash", str(INSTALL), *args],
        capture_output=True,
        text=True,
        env=env,
        stdin=subprocess.DEVNULL,
        timeout=30,
    )
    return r, log.read_text()


def parse_kv(text):
    out = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("# "):
            key, _, value = line.partition("=")
            out[key] = value
    return out


# ── --check: read-only report ────────────────────────────────────────────────────────


def test_check_reports_expected_shape(tmp_path):
    r, _ = run_install(
        tmp_path, "--check", logged_in=1, marketplace=1, plugin=0, assume_yes=False
    )
    assert r.returncode == 0, r.stderr
    out = parse_kv(r.stdout)
    assert out["os"] in {"macos", "linux", "wsl", "windows", "unknown"}
    assert out["tty"] in {"yes", "no"}
    assert out["claude"] == "installed"
    assert out["logged_in"] == "yes"
    assert out["marketplace"] == "present"
    assert out["plugin"] == "missing"


def test_check_reports_unknowns_when_claude_missing(tmp_path):
    # No stub: point ONBOARD_CLAUDE_BIN at a non-existent path so resolve fails.
    env = {
        **os.environ,
        "ONBOARD_CLAUDE_BIN": str(tmp_path / "nope"),
        "ONBOARD_NO_BROWSER": "1",
    }
    r = subprocess.run(
        ["bash", str(INSTALL), "--check"],
        capture_output=True,
        text=True,
        env=env,
        stdin=subprocess.DEVNULL,
        timeout=30,
    )
    assert r.returncode == 0, r.stderr
    out = parse_kv(r.stdout)
    # When claude is genuinely absent on the runner this is missing; on a dev box with a real
    # claude on PATH the override still wins (the bad path) → missing. Either way:
    assert out["claude"] == "missing"
    assert out["logged_in"] == "unknown"
    assert out["marketplace"] == "unknown"
    assert out["plugin"] == "unknown"


# ── Idempotency + fresh-machine install paths ─────────────────────────────────────────


def test_fast_forward_runs_no_install_commands(tmp_path):
    # Everything already present → nothing should be added.
    r, log = run_install(tmp_path, logged_in=1, marketplace=1, plugin=1)
    assert r.returncode == 0, r.stderr
    assert "already done" in r.stdout
    assert "marketplace add" not in log
    assert "install coding-onboarding" not in log


def test_fresh_machine_adds_marketplace_then_plugin(tmp_path):
    # Logged in, but the add-on store + plugin are missing → both get installed, in order.
    r, log = run_install(tmp_path, logged_in=1, marketplace=0, plugin=0)
    assert r.returncode == 0, r.stderr
    assert "marketplace add mickzijdel/dev-hooks" in log
    assert "plugin install coding-onboarding@dev-hooks" in log
    assert log.index("marketplace add") < log.index("install coding-onboarding")


def test_does_not_hang_without_a_keyboard(tmp_path):
    # stdin is /dev/null and no ONBOARD_ASSUME_YES — the /dev/tty degrade path must let the
    # script finish on its own (the 30s timeout in run_install enforces "doesn't hang").
    r, _ = run_install(tmp_path, logged_in=1, marketplace=1, plugin=1, assume_yes=False)
    assert r.returncode == 0, r.stderr


# ── URL / path parity ─────────────────────────────────────────────────────────────────


def test_install_sh_points_at_real_paths():
    # The overlay URL is assembled from a base + relative path; assert both halves are present
    # and the file they point at actually exists, so the raw link can never 404.
    text = INSTALL.read_text()
    assert RAW_BASE in text
    assert HTML_REL_PATH in text
    assert ONBOARD_HTML.exists()
    assert "https://claude.ai/install.sh" in text


def test_root_readme_advertises_the_one_liner():
    assert INSTALL_RAW_URL in ROOT_README.read_text()


# ── Overlay page ──────────────────────────────────────────────────────────────────────


def test_onboard_html_is_self_contained_and_featured():
    html = ONBOARD_HTML.read_text()
    assert "documentPictureInPicture" in html
    assert "localStorage" in html
    assert '<input type="checkbox"' in html
    assert "wsl" in html.lower()
    assert "clipboard" in html  # copy buttons
    # Self-contained: no external scripts/styles/images.
    assert "<script src=" not in html
    assert '<link rel="stylesheet"' not in html
    assert 'src="http' not in html


# ── Plain-words / beginner-voice guardrails ───────────────────────────────────────────


def test_plain_words_glossary_defines_core_terms():
    text = PLAIN_WORDS.read_text().lower()
    for term in ("terminal", "plugin", "package manager"):
        assert term in text, f"plain-words.md should define {term!r}"


def test_skill_links_plain_words_and_bootstrap():
    text = SKILL_MD.read_text()
    assert "plain-words" in text
    assert "install.sh" in text


def test_user_facing_copy_explains_jargon_not_assumes_it():
    # The script and page introduce "terminal" with an everyday explanation rather than
    # assuming the reader knows it.
    assert "instead of clicking" in ONBOARD_HTML.read_text()
    assert "terminal" in INSTALL.read_text()
