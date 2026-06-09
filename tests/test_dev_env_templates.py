"""Content checks for the dev-env-setup CI templates.

These guard the gitleaks job that ships in every scaffolded repo: gitleaks-action
hard-requires a GITHUB_TOKEN to scan pull_request events (without it the job fails the
PR), and the standard pins the action at its current major. A plain file-content read is
enough — no subprocess needed — so the checks stay fast and offline.
"""

import ast
import json
import re

import pytest

from conftest import ROOT

TEMPLATES_DIR = ROOT / "skills" / "dev-env-setup" / "references" / "templates"
CI_TEMPLATES = ["ci.python.yml", "ci.ruby.yml", "ci.shell.yml"]
VERSION_FILE = ROOT / "skills" / "dev-env-setup" / "VERSION"
SKILL_MD = ROOT / "skills" / "dev-env-setup" / "SKILL.md"
MISSING_TEST_HOOK = ROOT / "hooks" / "scripts" / "missing-test-reminder.sh"

# Templates carrying shebang-based companion-step detectors for extensionless scripts.
SHEBANG_DETECTOR_TEMPLATES = [
    "hk.shell.pkl",
    "hk.python.pkl",
    "ci.shell.yml",
    "ci.python.yml",
]


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_pins_v3(name):
    text = (TEMPLATES_DIR / name).read_text()
    assert "gitleaks/gitleaks-action@v3" in text
    assert "gitleaks/gitleaks-action@v2" not in text


@pytest.mark.parametrize("name", CI_TEMPLATES)
def test_gitleaks_job_passes_github_token(name):
    text = (TEMPLATES_DIR / name).read_text()
    # The token env must sit on the gitleaks step (the action reads it to enumerate PR commits).
    assert "GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}" in text


@pytest.mark.parametrize("name", SHEBANG_DETECTOR_TEMPLATES)
def test_shebang_detector_matches_line_one_only(name):
    """The companion-step shebang detector must read line 1 only (head -n1), not the
    whole file. `grep -lE '^#!…'` matches a `#!` anywhere, so a shebang embedded in a
    fenced code block in docs gets misdetected as a script and the linter chokes parsing
    prose as code. Regression guard for that bug."""
    text = (TEMPLATES_DIR / name).read_text()
    # The buggy whole-file detector must be gone.
    assert "grep -lE '^#!" not in text, (
        f"{name} still uses the whole-file `grep -lE '^#!…'` detector"
    )
    # The line-1-only form must be present.
    assert "head -n1" in text, f"{name} is missing the `head -n1` line-1 detector"


def test_skill_doc_matches_version_stamp():
    """SKILL.md's '## The standard (vN)' header tracks the VERSION source of truth."""
    version = VERSION_FILE.read_text().strip()
    header = re.search(r"^## The standard \(v(\d+)\)", SKILL_MD.read_text(), re.M)
    assert header is not None, "SKILL.md is missing the '## The standard (vN)' header"
    assert header.group(1) == version


def _jscpd_dir_fragments(jscpd_json_path):
    """Dir fragments from a .jscpd.json's `**/<dir>/**` ignorePattern entries (file-shaped
    patterns like `**/db/schema.rb` are excluded)."""
    data = json.loads(jscpd_json_path.read_text())
    frags = set()
    for pat in data.get("ignorePattern", []):
        m = re.match(r"^\*\*/(.+)/\*\*$", pat)
        if m:
            frags.add(m.group(1))
    return frags


def test_missing_test_fallback_matches_jscpd_template():
    """missing-test-reminder.sh reads each repo's .jscpd.json at run time, but falls back to a
    hardcoded DEFAULT_VENDOR_DIRS when a repo has none. That fallback must stay identical to the
    dirs the shipped .jscpd.json template ignores — otherwise the standard and the hook drift."""
    template_dirs = _jscpd_dir_fragments(TEMPLATES_DIR / ".jscpd.json")
    m = re.search(r"DEFAULT_VENDOR_DIRS = (\{[^}]*\})", MISSING_TEST_HOOK.read_text())
    assert m is not None, "missing-test-reminder.sh is missing DEFAULT_VENDOR_DIRS"
    hook_dirs = ast.literal_eval(m.group(1))
    assert hook_dirs == template_dirs, (
        f"hook fallback {hook_dirs} != .jscpd.json template dirs {template_dirs}"
    )
